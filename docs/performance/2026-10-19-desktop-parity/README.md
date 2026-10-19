# Desktop parity performance evidence, 19 October 2026

All ten release-parameter cases pass against main `68c50c0db198a2e88a247b36ac59735c42843ea6`. No budgets were changed and no forced garbage collection was used. Samples ran sequentially from frozen exports, without concurrent tests, builds, profilers or repository writes.

Production runtime: `9d5e8256b551eeb2eb461437b3e45872d097c9b3`. Offscreen harness uses the same commit. Wayland harness and final functional validation: `33ef49aeaad2b8052a303c281072f6ef77e5a2df`. The later commits change only fixture input isolation, bounded test waits and documentation; root production QML/JS hashes are identical and recorded in [manifest.json](manifest.json). All root QML/JS files in the base archive were byte-checked against main.

Raw passing reports: [offscreen](offscreen.json) and [native Wayland mini](wayland-mini.json). Each source/state uses a fresh process and three 10-second samples after 20-second settling. Navigation runs three rounds of twenty real Search/Library cycles.

| Case | Main median PSS (MiB) | Candidate (MiB) | Delta (MiB) | Feedback p95 (ms) | Loop lag p95 (ms) | Navigation growth (KiB) | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| navigation-1000 | 134.44 | 129.62 | -4.82 | 10.0 | 44.0 | 174 | Pass |
| navigation-10000 | 238.07 | 166.41 | -71.66 | 9.0 | 57.0 | 803 | Pass |
| full-1000 | 130.95 | 121.53 | -9.42 | 1.0 | 13.0 | — | Pass |
| full-10000 | 233.73 | 156.93 | -76.80 | 1.0 | 13.0 | — | Pass |
| closed-after-use-1000 | 129.04 | 119.45 | -9.58 | — | — | — | Pass |
| closed-after-use-10000 | 234.42 | 156.48 | -77.95 | — | — | — | Pass |
| closed-1000 | 107.60 | 105.28 | -2.32 | — | — | — | Pass |
| closed-10000 | 109.42 | 105.62 | -3.80 | — | — | — | Pass |
| mini-1000 | 172.90 | 170.78 | -2.12 | 1.0 | 17.0 | — | Pass |
| mini-10000 | 173.30 | 170.96 | -2.34 | 1.0 | 25.0 | — | Pass |

Closed and closed-after-use CPU and scheduler deltas are zero in every case (counter-resolution-limited samples). Closed PSS budget remains +2 MiB; full/navigation/mini remains +5 MiB. Local feedback and event-loop lag remain <=100 ms; navigation growth remains <=1024 KiB.

The 10k full view uses 76.80 MiB less PSS than main. The 10k navigation comparison saves 71.66 MiB and closes at 803 KiB growth. The collection ListView now uses positions rather than nested metadata as its native model; visible/buffered delegates read the existing JS records. Compact rows retain their density and show Save/duration plus an expandable action menu.

## Validation and limits

The final full `scripts/test.sh` passes Rust formatting, 26 tests and Clippy; plugin validation/qmllint; 249 QML tests; 19 helper tests; installer checks; five socket scenarios; four sampler tests; and isolated native app, authorization, queue, library, discovery, resource, table, popup/playback lifetime, history and mouse/keyboard/Ctrl-drag checks. Log path and SHA256 are in the manifest.

Fixtures have metadata only: no live audio, downloaded artwork, account/network activity, physical input dispatch or compositor input-to-photon latency was measured. The Wayland mini still renders the actual BarWidget on a native layer-shell window, but its private copied KeyboardPanel is input-transparent/unfocusable and omits click-dismissal surfaces, so desktop activity cannot close it. Input focus/dismissal behavior is excluded. Closed-cold and mini row labels identify matrix settings: cold loads no collection, and mini uses one paused representative track.

Existing one-query search results and selected-artist catalogs retain their documented behavior; this matrix does not bound every browsing path. Unsupported native queue jump/reorder/remove/clear operations remain disabled. The installed checkout stayed on main, with no deployment, tag or merge.

## Earlier failures preserved

[Earlier raw reports](earlier-runs/) retain failures rather than replacing them with passing results:

- `06e0ed5`: corrected-fixture 1k navigation failed memory/plateau, then stopped.
- `83dd68d`: lazily created row controls alone still failed navigation memory/lag/plateau; stopped before completing the matrix.
- `5df5f4a`: full eight-case matrix passed all memory/idle gates but failed 1k navigation growth and 10k lag.
- `9d5e825` first physical-desktop mini attempt: invalid because the popup was dismissed; no pass was recorded. The later harness isolates desktop input for both revisions.

Stopped raw reports retain their original `running` status alongside explicit stop markers. Full raw diagnostic logs remain under `~/.cache/omarchy-spotify/`, with report directories in the manifest. Earlier profiler/GC diagnostics were not release measurements and added no GC to production or the final fixture. A later functional rerun also exposed a fixed-150-ms popup-test race; `parity-tests-final-mini-isolation.log` preserves that failure. The test now polls actual cleanup with a 2-second failure bound rather than racing Qt exit transitions.

## Exact commands

```bash
env -u WAYLAND_DISPLAY PATH=/usr/lib/qt6/bin:$PATH QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 \
  TMPDIR=$HOME/.cache/omarchy-spotify/test-tmp CARGO_TARGET_DIR=$HOME/.cache/omarchy-spotify/target \
  bash scripts/test.sh

TMPDIR=$HOME/.cache/omarchy-spotify/test-tmp PYTHONDONTWRITEBYTECODE=1 \
python3 $HOME/.cache/omarchy-spotify/parity-candidate-9d5e825/scripts/benchmark-compare.py \
  /tmp/omarchy-spotify-baseline $HOME/.cache/omarchy-spotify/parity-candidate-9d5e825 \
  --output $HOME/.cache/omarchy-spotify/parity-release-offscreen-9d5e825 \
  --modes navigation full closed-after-use closed --rows 1000 10000 --seconds 10 --samples 3 --settle 20

TMPDIR=$HOME/.cache/omarchy-spotify/test-tmp PYTHONDONTWRITEBYTECODE=1 \
python3 $HOME/.cache/omarchy-spotify/parity-candidate-33ef49a/scripts/benchmark-compare.py \
  /tmp/omarchy-spotify-baseline $HOME/.cache/omarchy-spotify/parity-candidate-33ef49a \
  --output $HOME/.cache/omarchy-spotify/parity-release-wayland-33ef49a \
  --platform wayland --modes mini --rows 1000 10000 --seconds 10 --samples 3 --settle 20
```
