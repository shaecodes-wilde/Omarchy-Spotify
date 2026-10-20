#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export SPOTIFY_DESKTOP_KEEP_HINTS=1
exec "$source_root/scripts/test-quickshell.sh" DesktopEvents
