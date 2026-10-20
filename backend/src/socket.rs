use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf};

use anyhow::{Context, Result};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::watch,
};

use crate::{
    engine::{EngineSender, send_with_reply},
    protocol::{PROTOCOL_VERSION, ProtocolError, Request, ServerMessage},
    state::StateStore,
};

pub struct SocketGuard {
    path: PathBuf,
}

impl Drop for SocketGuard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

pub async fn serve(
    path: PathBuf,
    state: StateStore,
    commands: EngineSender,
    mut shutdown: watch::Receiver<bool>,
) -> Result<SocketGuard> {
    let parent = path
        .parent()
        .context("backend socket path has no parent directory")?;
    fs::create_dir_all(parent)
        .with_context(|| format!("failed to create socket directory {}", parent.display()))?;
    if path.exists() {
        fs::remove_file(&path)
            .with_context(|| format!("failed to remove stale socket {}", path.display()))?;
    }

    let listener = UnixListener::bind(&path)
        .with_context(|| format!("failed to bind backend socket {}", path.display()))?;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
        .with_context(|| format!("failed to secure backend socket {}", path.display()))?;
    let guard = SocketGuard { path };

    tokio::spawn(async move {
        loop {
            tokio::select! {
                accepted = listener.accept() => match accepted {
                    Ok((stream, _)) => {
                        tokio::spawn(handle_client(stream, state.clone(), commands.clone()));
                    }
                    Err(error) => {
                        log::warn!("backend socket accept failed: {error}");
                    }
                },
                changed = shutdown.changed() => {
                    if changed.is_err() || *shutdown.borrow() {
                        break;
                    }
                }
            }
        }
    });

    Ok(guard)
}

async fn handle_client(stream: UnixStream, state: StateStore, commands: EngineSender) {
    if let Err(error) = client_loop(stream, state, commands).await {
        log::debug!("backend client disconnected: {error}");
    }
}

async fn client_loop(stream: UnixStream, state: StateStore, commands: EngineSender) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();
    let mut states = state.subscribe();
    let initial = state.with(|snapshot| {
        encode_message(&ServerMessage::Event {
            v: PROTOCOL_VERSION,
            event: "state_changed",
            state: snapshot,
        })
    })?;
    write_encoded(&mut writer, &initial).await?;
    let (mut queue_revision, queue) = state.with(|snapshot| {
        (
            snapshot.queue_revision,
            encode_message(&ServerMessage::QueueChanged {
                v: PROTOCOL_VERSION,
                event: "queue_changed",
                queue: &snapshot.queue,
            }),
        )
    });
    write_encoded(&mut writer, &queue?).await?;

    loop {
        tokio::select! {
            line = lines.next_line() => {
                let Some(line) = line? else { break };
                let message = handle_line(&line, &state, &commands).await;
                write_message(&mut writer, &message).await?;
            }
            changed = states.changed() => {
                if changed.is_err() { break; }
                let (encoded, queue) = {
                    let snapshot = states.borrow_and_update();
                    let queue = if snapshot.queue_revision != queue_revision {
                        queue_revision = snapshot.queue_revision;
                        Some(encode_message(&ServerMessage::QueueChanged {
                            v: PROTOCOL_VERSION, event: "queue_changed", queue: &snapshot.queue,
                        })?)
                    } else { None };
                    let encoded = encode_message(&ServerMessage::Event {
                        v: PROTOCOL_VERSION,
                        event: "state_changed",
                        state: &snapshot,
                    })?;
                    (encoded, queue)
                };
                write_encoded(&mut writer, &encoded).await?;
                if let Some(queue) = queue { write_encoded(&mut writer, &queue).await?; }
            }
        }
    }
    Ok(())
}

async fn handle_line<'a>(
    line: &str,
    state: &StateStore,
    commands: &EngineSender,
) -> ServerMessage<'a> {
    let request: Request = match serde_json::from_str(line) {
        Ok(request) => request,
        Err(error) => {
            return ServerMessage::failure(
                0,
                ProtocolError::new("invalid_request", format!("invalid JSON request: {error}")),
            );
        }
    };
    if request.v != PROTOCOL_VERSION {
        return ServerMessage::failure(
            request.id,
            ProtocolError::new(
                "unsupported_version",
                format!(
                    "protocol version {} is unsupported; expected {}",
                    request.v, PROTOCOL_VERSION
                ),
            ),
        );
    }

    let result = match request.command {
        crate::protocol::Command::Hello => Ok(serde_json::json!({
            "protocol_version": PROTOCOL_VERSION,
            "backend_version": env!("CARGO_PKG_VERSION"),
            "engine": "librespot",
            "capabilities": { "queue_snapshot": true, "queue_activate": false, "queue_edit": false }
        })),
        crate::protocol::Command::Ping => Ok(serde_json::json!({ "pong": true })),
        crate::protocol::Command::GetState => state
            .with(|snapshot| serde_json::to_value(snapshot))
            .map_err(|error| ProtocolError::new("serialization_error", error.to_string())),
        command => send_with_reply(commands, command).await,
    };

    match result {
        Ok(value) => ServerMessage::success(request.id, value),
        Err(error) => ServerMessage::failure(request.id, error),
    }
}

async fn write_message(
    writer: &mut tokio::net::unix::OwnedWriteHalf,
    message: &ServerMessage<'_>,
) -> Result<()> {
    let encoded = encode_message(message)?;
    write_encoded(writer, &encoded).await
}

fn encode_message(message: &ServerMessage<'_>) -> Result<Vec<u8>> {
    let mut encoded = serde_json::to_vec(message).context("failed to encode backend message")?;
    encoded.push(b'\n');
    Ok(encoded)
}

async fn write_encoded(
    writer: &mut tokio::net::unix::OwnedWriteHalf,
    encoded: &[u8],
) -> Result<()> {
    writer
        .write_all(encoded)
        .await
        .context("failed to write backend message")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{BackendState, QueueSnapshot};
    use std::time::Duration;

    #[tokio::test]
    async fn position_ticks_do_not_repeat_queue_payloads() {
        let state = StateStore::new(BackendState::default());
        let (commands, _receiver) = tokio::sync::mpsc::channel(1);
        let (client, server) = UnixStream::pair().unwrap();
        let task = tokio::spawn(client_loop(server, state.clone(), commands));
        let mut lines = BufReader::new(client).lines();
        let initial = lines.next_line().await.unwrap().unwrap();
        assert!(!initial.contains("next_tracks"));
        assert!(
            lines
                .next_line()
                .await
                .unwrap()
                .unwrap()
                .contains("queue_changed")
        );
        state.update(|snapshot| {
            snapshot.queue = Some(QueueSnapshot {
                context_uri: "spotify:playlist:context".into(),
                current_track: None,
                next_tracks: vec![],
                prev_tracks: vec![],
                next_total: 0,
                truncated: false,
            });
            snapshot.queue_revision += 1;
            true
        });
        assert!(
            lines
                .next_line()
                .await
                .unwrap()
                .unwrap()
                .contains("state_changed")
        );
        assert!(
            lines
                .next_line()
                .await
                .unwrap()
                .unwrap()
                .contains("queue_changed")
        );
        state.update(|snapshot| {
            snapshot.position_ms = 1000;
            true
        });
        let tick = lines.next_line().await.unwrap().unwrap();
        assert!(tick.contains("state_changed"));
        assert!(!tick.contains("next_tracks"));
        assert!(
            tokio::time::timeout(Duration::from_millis(30), lines.next_line())
                .await
                .is_err()
        );
        task.abort();
    }
}
