# Backend protocol

The plugin backend listens at
`$XDG_RUNTIME_DIR/omarchy-spotify/backend.sock`. The socket and every message
are private to the current user. Transport is UTF-8 JSON, one object per line.

Protocol version 1 requests have a caller-chosen integer id and a flattened
command:

```json
{"v":1,"id":7,"command":"pause"}
```

A successful response keeps that id:

```json
{"type":"response","v":1,"id":7,"ok":true,"result":{}}
```

Failures set `ok` to false and return a stable machine-readable error code plus
a human-readable message. An unsupported protocol version is rejected rather
than guessed.

The server pushes a complete snapshot on connection and whenever playback
state changes:

```json
{"type":"event","v":1,"event":"state_changed","state":{"lifecycle":"ready"}}
```

The abbreviated example omits the remaining state fields. A real snapshot also
contains backend and protocol versions, session status, current client,
playback status, track metadata, position in milliseconds, native 16-bit
Connect volume, shuffle/repeat state, a monotonically increasing generation,
and a redacted error string. When the error needs dedicated UI, the snapshot
also includes an optional stable `error_code`; `audio_key_unavailable` means
Spotify refused the key required for local playback.

Version 1 commands are:

- `hello`, `ping`, and `get_state`;
- `activate`, `play`, `pause`, `toggle`, `stop`, `next`, and `previous`;
- `seek` with `position_ms` and `set_volume` with a value from 0 through 65535;
- `set_shuffle` and `set_repeat` (`off`, `context`, or `track`);
- `add_to_queue` with a Spotify URI; and
- `load` with either `context_uri` or `uris`, optional `offset_uri` or
  `offset_index`, optional `position_ms`, and `play` (true by default).

Adding an optional field or command is backward-compatible. Removing or
renaming a field, changing its meaning, or changing framing requires a new
protocol version. The Quickshell service uses this socket to start local playback (`load`)
and add to the local queue. Clients must retain MPRIS/Web API fallback
behavior when the socket is absent or reports an unsupported version.

The `hello` result advertises optional `capabilities`. Current backends return
`queue_snapshot: true`, `queue_activate: false`, and `queue_edit: false`. Older
version 1 backends without this capability retain the Web API queue fallback.
The client validates both envelope and handshake protocol versions before
sending playback commands. Pending requests have a five-second deadline and
fail exactly once on disconnect or timeout. A sent command with an unknown
outcome must never be automatically retried through another transport.

Native queues use a separate event on connection and whenever the authoritative
librespot `SetQueue` snapshot changes:

```json
{"type":"event","v":1,"event":"queue_changed","queue":{"context_uri":"spotify:playlist:...","current_track":{"uri":"spotify:track:...","provider":"context"},"next_tracks":[],"prev_tracks":[],"next_total":0,"truncated":false}}
```

The snapshot retains order and repeated URIs, with at most 100 upcoming and 20
previous entries. Entries contain only URI and Spotify provider. `next_total`
counts upcoming items before truncation; `truncated` indicates omitted upcoming
items. A null queue invalidates the snapshot when the native session disconnects.
Queue data is absent from ordinary state/position events and `get_state`;
reconnect to receive the latest queue snapshot. There is no queue polling.

The UI resolves uncached display metadata only while the queue page is open,
using bounded Web API metadata batches and a 200-entry account-local cache.
Unavailable metadata retains URI identity and a placeholder; it cannot change
queue order. Track/device changes invalidate Web queue snapshots and discard
in-flight responses for the previous playback identity.

Pinned librespot exposes `add_to_queue` but no public context-preserving queue
jump, reorder, remove, or clear methods. The UI disables those controls rather
than loading a replacement context. Batch add submits at most 100 tracks or
episodes sequentially, preserving deliberately selected repeats; a partial or
uncertain failure stops the batch without retrying the last item. Ordinary
playback controls continue through local MPRIS, with existing Web/Sonos paths
for remote receivers. Session recovery does not reconstruct lost contexts from
this bounded display snapshot.
