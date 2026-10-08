#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
cp "$source_root/"{AuthManager.qml,Api.js,OAuth.js} "$test_root/"
sed 's|import "../.." as Plugin|import "." as Plugin|' \
  "$source_root/tests/integration/AuthIdentity.qml" > "$test_root/shell.qml"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen timeout 15s \
  qs --no-color -p "$test_root" > "$test_root/output" 2>&1 || {
  cat "$test_root/output"
  exit 1
}
rg -q AUTH_IDENTITY_PASS "$test_root/output" || {
  cat "$test_root/output"
  exit 1
}
echo 'Quickshell authorization integration passed.'

mkdir -p "$test_root/app/plugin" "$test_root/state"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/app/plugin/"
cp -r /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$test_root/app/"
cp "$source_root/tests/integration/AppSmoke.qml" "$test_root/app/shell.qml"
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  # The full panel can load offscreen; the bar widget requires a compositor.
  sed -i '/Plugin.BarWidget {/d' "$test_root/app/shell.qml"
  app_platform=offscreen
else
  app_platform=wayland
fi
env QT_QPA_PLATFORM="$app_platform" QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/app-output" 2>&1 || {
  cat "$test_root/app-output"
  exit 1
}
rg -q APP_SMOKE_PASS "$test_root/app-output" || {
  cat "$test_root/app-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/app-output"; then
  exit 1
fi
echo 'Quickshell app smoke test passed.'

cp "$source_root/tests/integration/DiscoveryPipeline.qml" "$test_root/app/shell.qml"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/discovery-output" 2>&1 || {
  cat "$test_root/discovery-output"
  exit 1
}
rg -q DISCOVERY_PIPELINE_PASS "$test_root/discovery-output" || {
  cat "$test_root/discovery-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/discovery-output"; then
  exit 1
fi
echo 'Quickshell discovery pipeline integration passed.'

cp "$source_root/tests/integration/DiscoveryPersistence.qml" "$test_root/app/shell.qml"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/persistence-output" 2>&1 || {
  cat "$test_root/persistence-output"
  exit 1
}
rg -q DISCOVERY_PERSISTENCE_PASS "$test_root/persistence-output" || {
  cat "$test_root/persistence-output"
  exit 1
}
[[ $(stat -c %a "$test_root/state/persistence/discovery") == 700 ]]
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/persistence-output"; then
  exit 1
fi
echo 'Quickshell discovery persistence integration passed.'
