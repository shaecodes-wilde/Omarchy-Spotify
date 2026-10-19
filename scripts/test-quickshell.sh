#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
# Quickshell's IPC path must fit Unix socket's 108-byte limit.
test_runtime=$(mktemp -d /tmp/sqt.XXXXXX)
trap 'rm -rf -- "$test_root" "$test_runtime"' EXIT

app_platform=offscreen
test_wayland_display=""
if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  app_platform=wayland
  if [[ $WAYLAND_DISPLAY == /* ]]; then
    test_wayland_display=$WAYLAND_DISPLAY
  else
    test_wayland_display=${XDG_RUNTIME_DIR:?}/$WAYLAND_DISPLAY
  fi
fi

mkdir -p "$test_root/"{bin,config,data,cache,state,app/plugin/scripts}
# Tests cannot read the live keyring, operate user units, launch auth browsers,
# or let the session bus activate installed services.
cat > "$test_root/bin/isolated-command" <<'STUB'
#!/bin/sh
printf '%s\n' "${0##*/}" >> "$TEST_ISOLATION_LOG"
exit 1
STUB
chmod +x "$test_root/bin/isolated-command"
for name in secret-tool systemctl xdg-open socat; do
  cp "$test_root/bin/isolated-command" "$test_root/bin/$name"
done
for name in playback-runtime.sh setup-playback.sh configure-spotifyd.sh spotifyd-auth.sh \
    spotifyd-logout.sh return-from-auth.sh keyring-store.sh pkce.sh spotify-connect-device.py; do
  cp "$test_root/bin/isolated-command" "$test_root/app/plugin/scripts/$name"
done
# Model an installed, stopped receiver so startup does not synthesize setup errors.
cat > "$test_root/app/plugin/scripts/playback-runtime.sh" <<'STUB'
#!/bin/sh
printf '%s\n' "playback-runtime.sh" >> "$TEST_ISOLATION_LOG"
case "${1:-}" in
  check) exit 0 ;;
  unit) printf '%s\n' omarchy-spotify.service; exit 0 ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$test_root/app/plugin/scripts/playback-runtime.sh"
export PATH="$test_root/bin:$PATH"
export TEST_ISOLATION_LOG="$test_root/stub-commands.log"
export XDG_RUNTIME_DIR="$test_runtime"
export XDG_CONFIG_HOME="$test_root/config" XDG_DATA_HOME="$test_root/data"
export XDG_CACHE_HOME="$test_root/cache" XDG_STATE_HOME="$test_root/state"
export QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 QT_ACCESSIBILITY=0
export PYTHONDONTWRITEBYTECODE=1
unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE WAYLAND_DISPLAY
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$test_runtime/no-system-bus"
cat > "$test_root/dbus.conf" <<BUS
<busconfig><type>session</type><listen>unix:tmpdir=$test_runtime</listen><policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>
BUS

run_native() {
  local config=$1 marker=$2 description=$3 platform=${4:-offscreen} limit=${5:-15s}
  [[ ! -e "$test_runtime/omarchy-spotify/backend.sock" ]]
  local -a display_env=()
  if [[ $platform == wayland ]]; then display_env+=(WAYLAND_DISPLAY="$test_wayland_display"); fi
  if ! env -u WAYLAND_DISPLAY QT_QPA_PLATFORM="$platform" "${display_env[@]}" \
      timeout -k 2s "$limit" dbus-run-session --config-file="$test_root/dbus.conf" -- \
      qs --no-color -p "$config" > "$test_root/output" 2>&1; then
    cat "$test_root/output"
    exit 1
  fi
  if ! rg -q "$marker" "$test_root/output" \
      || rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/output"; then
    cat "$test_root/output"
    exit 1
  fi
  echo "Quickshell $description integration passed."
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    DesktopNavigation) marker=DESKTOP_NAVIGATION_PASS ;;
    DesktopEvents) marker=DESKTOP_EVENTS_PASS ;;
    PlaylistPopupLifetime) marker=PLAYLIST_POPUP_LIFETIME_PASS ;;
    *) echo "Unknown desktop fixture: $1" >&2; exit 2 ;;
  esac
  cp "$source_root/"*.qml "$source_root/"*.js "$test_root/app/plugin/"
  cp -r /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$test_root/app/"
  cp "$source_root/tests/integration/$1.qml" "$test_root/app/shell.qml"
  run_native "$test_root/app" "$marker" "$1" offscreen 20s
  exit
fi

cp "$source_root/"{AuthManager.qml,Api.js,OAuth.js} "$test_root/"
sed 's|import "../.." as Plugin|import "." as Plugin|' \
  "$source_root/tests/integration/AuthIdentity.qml" > "$test_root/shell.qml"
run_native "$test_root" AUTH_IDENTITY_PASS authorization

cp "$source_root/"*.qml "$source_root/"*.js "$test_root/app/plugin/"
cp -r /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$test_root/app/"
cp "$source_root/tests/integration/AppSmoke.qml" "$test_root/app/shell.qml"
if [[ $app_platform == offscreen ]]; then
  # The full panel loads offscreen; the bar widget requires a compositor.
  sed -i '/Plugin.BarWidget {/d' "$test_root/app/shell.qml"
fi
run_native "$test_root/app" APP_SMOKE_PASS 'app smoke' "$app_platform"

dbus-run-session --config-file="$test_root/dbus.conf" -- python3 "$source_root/tests/test_backend_client.py"
for spec in \
    'QueueState QUEUE_STATE_PASS queue-state' \
    'LibraryState LIBRARY_STATE_PASS library-state' \
    'DiscoveryPipeline DISCOVERY_PIPELINE_PASS discovery-pipeline' \
    'DiscoveryPersistence DISCOVERY_PERSISTENCE_PASS discovery-persistence' \
    'ResourcePolicy RESOURCE_POLICY_PASS resource-policy' \
    'TrackTable TRACK_TABLE_PASS track-table' \
    'PlaylistPopupLifetime PLAYLIST_POPUP_LIFETIME_PASS playlist-popup-lifetime'; do
  read -r fixture marker description <<< "$spec"
  cp "$source_root/tests/integration/$fixture.qml" "$test_root/app/shell.qml"
  run_native "$test_root/app" "$marker" "$description"
done
[[ $(stat -c %a "$test_root/state/persistence/discovery") == 700 ]]
python3 "$source_root/tests/test_benchmark_processes.py"

mkdir -p "$test_root/app/plugin/real"
cp "$source_root/"{BackendClient.qml,Api.js} "$test_root/app/plugin/real/"
cp "$source_root/tests/integration/PlaybackBackend.qml" "$test_root/app/plugin/BackendClient.qml"
cp "$source_root/tests/integration/PlaybackLifetime.qml" "$test_root/app/shell.qml"
run_native "$test_root/app" PLAYBACK_LIFETIME_PASS playback-lifetime
[[ ! -e "$test_runtime/omarchy-spotify/backend.sock" ]]
