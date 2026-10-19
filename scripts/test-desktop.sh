#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/app/plugin" "$test_root/state"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/app/plugin/"
cp -r /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$test_root/app/"
cp "$source_root/tests/integration/DesktopNavigation.qml" "$test_root/app/shell.qml"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 \
  XDG_STATE_HOME="$test_root/state" timeout 20s dbus-run-session -- qs --no-color -p "$test_root/app" \
  > "$test_root/output" 2>&1 || { cat "$test_root/output"; exit 1; }
if ! rg -q DESKTOP_NAVIGATION_PASS "$test_root/output" \
    || rg -i 'DESKTOP_NAVIGATION_FAIL|ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/output"; then
  cat "$test_root/output"
  exit 1
fi
echo 'Quickshell desktop navigation integration passed.'
