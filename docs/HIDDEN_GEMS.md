# Hidden Gems: finding obscure music

Hidden Gems is this fork’s discovery feature. It uses your Last.fm listening
profile to find connected artists, verifies their Spotify monthly audience,
and matches playable tracks to Spotify’s catalog. The goal is to introduce
small artists that fit your taste while making room for deeper exploration.

## Set up your own profile

1. Keep scrobbling to Last.fm so your profile reflects what you enjoy.
2. Create an application API key at [Last.fm](https://www.last.fm/api/account/create).
3. In the player, open **Settings → Last.fm · Hidden gems**.
4. Enter your username and API key, then select **Apply Last.fm**.
5. Open **For you → Hidden gems**, choose the depth, and select **Refresh**.

No Last.fm login, password, API secret, write permission, or new Spotify scope
is required. The shipped username and API key are empty. Use your own key;
never commit it to a source checkout or include it in an issue report.

## Choose how obscure and how adventurous

| Mode | Eligible Spotify monthly listeners |
| --- | ---: |
| Obscure | 0–199,999 |
| Underground | 0–49,999 |
| Deep underground | 0–9,999 |

These are eligibility rules, not ranking bonuses. An artist at exactly 200,000
listeners does not qualify for Obscure. Missing counts, rounded descriptions,
ambiguous artist identities, and stale audience evidence cannot establish
eligibility. Every artist credited on a track must meet the selected ceiling,
including featured artists.

Obscure targets an audience mix of eight artists below 10,000 listeners, eight
between 10,000 and 50,000, and four between 50,000 and 200,000. Underground
targets 12 below 10,000 and eight between 10,000 and 50,000. Deep underground
selects only artists below 10,000. These are preferences: missing groups can be
filled from other eligible groups, but the ceiling is never relaxed.

Adventure is separate from audience size:

- **Close:** direct similarity connections to the listening seeds.
- **Balanced:** wider connections and further exploration through small artists.
- **Adventurous:** the same broader search, with ranking that favours less
  familiar similarity connections.

## How a feed is built

1. **Read your taste.** Import up to 5,000 scrobbles from the last 90 days, the
   weekly, monthly, and overall artist charts, and up to 100 loved tracks.
2. **Choose listening seeds.** Keep two strong anchors and rotate the remaining
   seeds through the weighted listening pool. Positive feedback influences seeds.
3. **Explore a wider artist graph.** Fetch up to 30 neighbours per seed. Broader
   adventure modes explore additional branches, then follow verified small
   artists outward. Candidate ordering gives different seed paths a turn within
   the lookup budget.
4. **Verify Spotify audience.** Resolve an exact artist-name match to a Spotify
   artist ID. Read the exact monthly listener label from that artist’s public
   Spotify page. Cache verified counts by artist ID for 24 hours. Last.fm counts
   and Spotify followers/popularity scores are never used as replacements.
5. **Rank the eligible artists.** Combine connection strength, similarity fit,
   absolute audience size, and connections to multiple seeds. Penalize familiar
   artists and artists shown within 30 days.
6. **Find an introduction.** Try each shortlisted artist’s five Last.fm top
   tracks, excluding imported listening history, loved tracks, and hidden picks.
   Match exact normalized track titles and artists to Spotify, require the
   resolved artist ID, and reject conflicting known ISRCs.
7. **Check collaborators and choose the feed.** Verify all credited artists,
   apply the audience mix, and show up to 20 tracks with one pick per artist.

The explanation under each pick shows its connection path and Spotify monthly
listener count. **More like this** influences local ranking and future seeds.
**Less like this · hide** hides that track. This feedback does not change
Spotify’s own recommendation system.

## Privacy and local data

Your Last.fm key is masked in the settings UI and stored in your local Omarchy
widget configuration. It is sent to Last.fm to make the public API requests;
it is not included in discovery cache files or logged request URLs. Public
Spotify page requests use no Spotify bearer token or private API endpoint.

History, feedback, previously shown picks, track matches, and audience evidence
are kept under `$XDG_STATE_HOME/omarchy-spotify/discovery`, or
`~/.local/state/omarchy-spotify/discovery` when `XDG_STATE_HOME` is unset. The
directory is private to your user. Discovery records are separated by Last.fm
username and Spotify account. Switching accounts or logging out cancels old
requests and clears the visible feed.

**Clear local discovery data** removes the plugin’s saved discovery history,
feedback, suggestions, and metadata caches. It does not delete your Last.fm
profile or Spotify library.

The public repository includes source, documentation, and synthetic test data.
It includes no configured Last.fm username/key, Spotify sessions, listening
history, or desktop configuration.

## Practical limits and troubleshooting

- **The first search can take several minutes.** Each run checks at most 120
  candidate artist identities, with extra collaborator checks sharing the
  audience-check budget, and makes at most 100 track searches. Last.fm requests
  are paced; public Spotify page requests are serial with at least 500 ms
  between uncached requests. Spotify catalog requests yield to interactive work.
- **Counts are a checked snapshot.** Spotify audiences change. Evidence is
  accepted for 24 hours, and the status shows the freshness window. The plugin
  cannot guarantee a count stays below the ceiling between checks.
- **Public page markup can change.** This is not an official Spotify monthly
  listener API. If the exact count is missing or its format changes, the count
  remains unknown. Network failures and rate limits stop the run with a visible
  message; there is no automatic retry loop or weaker-metric fallback.
- **A strict feed may be short.** Small artists may have sparse Last.fm metadata,
  an ambiguous name, no matching Spotify recording, or an oversized collaborator.
  Try another adventure level or Refresh to rotate the search. Fewer good,
  verified picks are preferable to padding the list above the ceiling.
- **New means new to the imported history.** The 90-day/5,000-scrobble and
  100-loved-track limits mean older listening and music heard elsewhere can
  reappear. Familiar-artist and recent-suggestion penalties reduce repeats but
  are not absolute bans.
- **The search is bounded.** It does not crawl every artist or guarantee the
  globally deepest match. The audience mix is a target, not a guaranteed quota.
- **Feeds refresh on demand.** Results are cached for 24 hours and refreshed on
  a later visit or with Refresh. There is no daily background polling.

Older Balanced obscurity settings migrate to Obscure. Legacy feeds ranked by
Last.fm audience are invalidated while preserving imported history and feedback.

## Implementation and verification

- `Discovery.js`: normalization, seed selection, graph merging, ranking,
  Spotify matching, exact audience parsing, and feed diversity.
- `LastFmApi.qml`: public Last.fm read transport, pacing, caching, and cancellation.
- `SpotifyAudience.qml`: public Spotify listener checks, daily caching, and
  bounded requests without additional credentials or runtime dependencies.
- `DiscoveryController.qml`: orchestration, identity checks, account-scoped
  persistence, collaborator checks, and strict admission to the visible feed.

The repository’s Qt tests cover listener boundaries, unknown/rounded counts,
artist identity ambiguity, band selection, cancellations, timeouts, and cache
freshness. Native Quickshell integration tests exercise all three tiers, deeper
exploration, mainstream collaborators, account changes, migration, and persistence.
These tests use synthetic profiles and mocked music-service responses.

Run `scripts/test.sh` in the documented validation environment for the full
project checks. The implementation adds no audio-analysis or model-training
dependency.

Built on [Omarchy Spotify by stappmus](https://github.com/stappmus/Omarchy-Spotify)
under the project’s [MIT license](../LICENSE).
