# Performance policy

Performance is a release constraint. Compare the candidate with the base revision
using the same native fixture, Qt/Quickshell build, display backend, machine,
row count and settle period. Do not compare an isolated fixture's absolute memory
with the incremental live-shell figures in BENCHMARK.md.

The proposed gates are:

- Closed: candidate median PSS at most 2 MiB above base.
- Same populated full view: candidate median PSS at most 5 MiB above base.
- Hidden CPU and scheduler activity: investigate any repeatable increase. The
  executable screening thresholds are 0.1 CPU percentage points and 2 context
  switches/s to accommodate counter resolution/noise. These are not energy units.
- Local control feedback: p95 at most 100 ms. The fixture measures a cursor/control
  property update through the next QML event-loop turn. It does not measure OS
  input dispatch, compositor presentation, network response or artwork completion.
- Navigation cache plateau: after a warm navigation round, settled candidate PSS
  must grow by no more than 1 MiB over subsequent identical rounds. A failure
  requires investigation and a quiet repeat; it is not silently waived.

Use three 10-second samples after at least 20 seconds of settling for a release
comparison. Two 2-second samples are only harness smoke checks. Stop unrelated
builds/tests and heavy applications before the release run. Keep failed raw logs
and reports, and distinguish an incomplete matrix from a passing one.

## Discovery lifetime

Home's overview and cached Gems do not schedule a cold Last.fm pipeline. Only a
visible Gems surface calls `setDiscoverySurfaceVisible(id, true)`. The last
surface closing aborts Last.fm/Spotify discovery requests, stops paced work and
releases pipeline intermediates. This does not stop native playback or remote
playback monitoring. Fresh persisted recommendations remain immediately usable.

The controller is active by default for direct consumers; Service binds it to
Gems visibility. A refresh while no Gems surface is visible is ignored. Settings
changes while hidden do not restart discovery. Last.fm requests marked with zero
freshness (scrobble-history pages) are not retained in its response cache.

## Collection retention

Manually paging an active collection remains complete; there is no 200-row
visible-list truncation. Each library category retains the most recent *complete
page boundary* at or below 200 rows. When the category becomes inactive, or all UI
surfaces close, surplus metadata is released and its exact matching `next` cursor
is restored. For 30-row pages this is normally 180 rows. `Load more` reads every
remaining page again, without skipping or silently treating the prefix as a
complete collection. If no checkpoint exists, the category's loaded flag resets.

The selected playlist and selected detail buffer retain the same bounded page
checkpoint when all UI surfaces close. Their remembered restore depth survives
trimming, and hidden responses do not continue automatic restore paging. Panel
persists route/depth state before closing; opening a restored playlist can reload
the requested depth while visible. Account reset drops all checkpoint references.
This is bounded metadata retention, with no eager library indexing or database.

## Reproduction

Export the exact base commit into a separate directory, then run:

```bash
mkdir -p /tmp/spotify-base
git archive <base-sha> | tar -x -C /tmp/spotify-base
./scripts/benchmark-compare.py /tmp/spotify-base "$PWD" \
  --output /tmp/spotify-resource-report --seconds 10 --samples 3 --settle 20
```

The default matrix includes closed, full and repeated-navigation states with
1,000 and 10,000 metadata rows. Every source/state is a fresh Quickshell process,
with a private DBus session, runtime directory, config/cache/state/data directories
and stubbed keyring, systemctl and playback setup commands. Artwork and real
playback are deliberately absent. No installed plugin or real account is changed.
The same fixture comes from the candidate harness for both source revisions.

Mini-player content uses a real Wayland layer-shell window, which Qt's offscreen
backend does not provide. The offscreen report explicitly marks it skipped and
returns `partial` even if all available gates pass. Run the mini case separately
on Wayland (it briefly opens an isolated fixture window):

```bash
./scripts/benchmark-compare.py /tmp/spotify-base "$PWD" \
  --output /tmp/spotify-mini-report --platform wayland --modes mini \
  --seconds 10 --samples 3 --settle 20
```

`report.json` preserves every sample, medians, deltas, checks and limitations;
per-case logs preserve fixture diagnostics. A nonzero exit means a failed gate or
invalid fixture, not a measured pass. Process-set changes, PID reuse and missing
required `/proc` counters invalidate a sample. For real artwork, native audio and
same-process shell overhead, use the live benchmark methods in BENCHMARK.md.
