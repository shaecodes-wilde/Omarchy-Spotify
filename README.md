# Omarchy Spotify · Hidden Gems

Find small artists connected to the music you love, right inside Omarchy.

This is a discovery-focused fork of [stappmus/Omarchy-Spotify](https://github.com/stappmus/Omarchy-Spotify).
It keeps the upstream Quickshell player, themed mini-player, library, playlists,
Spotify Connect playback, keyboard controls, and Omasing integration, and adds
**Hidden Gems** for finding obscure music.

## What this fork adds

- **Obscure means a real audience ceiling.** Obscure admits artists with fewer
  than 200,000 total Last.fm listeners. Underground lowers that to 50,000,
  and Deep underground to 10,000. Counts equal to a ceiling are excluded.
- **A feed that actively looks for tiny artists.** Obscure aims for eight picks
  below 10,000 listeners, eight between 10,000 and 50,000, and four between
  50,000 and 200,000. Missing groups are filled with other eligible artists;
  the ceiling is never raised just to fill the list.
- **Explore beyond the obvious neighbours.** Last.fm listening history seeds
  a wider artist-similarity search. Balanced and Adventurous modes then walk
  outward through verified small artists to uncover more distant connections.
- **More artists, fewer repeats.** Each feed has up to 20 tracks, with one pick
  per artist. Rotating seeds draw from recent and long-term listening; familiar
  artists and picks shown within 30 days receive lower ranking scores.
- **Understand every recommendation.** Each pick shows its connection to your
  listening and its verified total Last.fm listener count. An oversized
  featured artist cannot slip past the audience ceiling.
- **Steer your own discoveries.** Use More like this to influence future seeds,
  or Less like this to hide a track. Feedback stays local to the plugin.
- **No extra music-data subscription.** Counts come from Last.fm’s official
  artist API and are cached for 24 hours. You supply your own Last.fm username and
  application API key; this repository includes no personal credentials.

The feed ranks metadata and listening connections; it does not analyze audio
or train a model. The metric counts Last.fm accounts that have listened to an
artist over time; it is not a monthly listener count or a Spotify audience
estimate. Unverified counts stay out of the feed.

## Install

```bash
omarchy plugin add https://github.com/shaecodes-wilde/Omarchy-Spotify.git --enable
```

Requires Omarchy 4 and a personal Spotify Premium account. Hidden Gems also
needs a Last.fm listening profile and your own [Last.fm application API key](https://www.last.fm/api/account/create).
Playback does not depend on setting up Last.fm.

### Enable Hidden Gems

1. Open the player’s **Settings → Last.fm · Hidden gems**.
2. Enter your Last.fm username and application API key, then select **Apply Last.fm**.
3. Open **For you → Hidden gems**. Choose your obscurity and adventure levels,
   then select **Refresh**.

| Obscurity | Strict total Last.fm listener ceiling |
| --- | ---: |
| Obscure (default) | <200,000 |
| Underground | <50,000 |
| Deep underground | <10,000 |

**Close** stays with direct artist connections. **Balanced** and **Adventurous**
search farther; Adventurous favours less familiar similarity connections.
A first uncached search can take several minutes. A strict tier may produce
fewer than 20 results, and a listener check that fails stays unverified.

See the [Hidden Gems guide](docs/HIDDEN_GEMS.md) for the discovery process,
privacy details, limits, and troubleshooting.
Already using the earlier Spotify listener checks? Follow the
[upgrade guide](docs/HIDDEN_GEMS.md#upgrade-from-spotify-listener-checks) to
verify the new metric and choose a deeper search without clearing your feedback.

## Why you will love it

- **Lightweight by design.** Enjoy your music without keeping a browser-sized
  desktop client running.
- **Made for Omarchy.** Every color follows your current theme automatically,
  including light themes.
- **Always within reach.** Play, pause, skip, seek, change volume, or open
  lyrics from the mini player in your bar. Your last song stays loaded, so
  Play picks up where you left off even after the player has gone idle.
- **Your full music library.** Search Spotify, browse artists and albums,
  manage playlists and the queue, and move playback between Spotify Connect
  devices.
- **Lyrics with Omasing.** Open the current song in Omasing and let it find the
  right lyrics and playback position automatically.

## Familiar from the first click

The layout is inspired by the Spotify client, so there is almost nothing new
to learn. Your library and playlists live in the sidebar, search stays at the
top, the player stays at the bottom, and artist and album names take you
straight to their pages.

Prefer to keep your hands on the keyboard? The whole app is designed for that
too.

| Shortcut | What it does |
| --- | --- |
| `Ctrl+F` or `/` | Search all of Spotify |
| `Ctrl+F` or `/` again | Toggle current area / all of Spotify |
| `Tab` / `F6` | Move between sidebar, search, the song list, and the player |
| `Arrow keys` | Move to a control; Enter activates |
| `C` | Row actions; arrows or Enter choose |
| `Space` | Play or pause |
| `Ctrl+Left` / `Ctrl+Right` | Previous or next song |
| `Shift+Left` / `Shift+Right` | Seek 10 seconds |
| `Ctrl+Up` / `Ctrl+Down` | Change volume |
| `M` | Mute or restore volume |
| `Ctrl+Shift+A` | Open the current song's artist |
| `Ctrl+Shift+B` | Open the current song's album |
| `Ctrl+/` | See every keyboard shortcut |
| `Ctrl+H` | Hide visible shortcut hints |

The first shortcut, Tab, or opening the player from the keyboard lights
matching controls with the next key. Hold Ctrl, Shift, or Alt to see those
chords; the matching hints remain until you release the held modifiers. While
hints are visible, the header keeps a **Ctrl+H · Hide hints** action in reach.
It turns hints off until you enable them again in Settings.

![Shortcut hints guiding focus down the Recently played song list](docs/media/shortcut-hints.gif)

The mini-player takes keyboard focus when it is opened from a shortcut. Use
`Tab` or the arrow keys to select every control, `Enter` to activate buttons,
left/right to adjust a selected slider, and `Esc` to close. The playback
shortcuts above work there too; `Ctrl+S` toggles shuffle, `Ctrl+R` cycles
repeat, `Ctrl+Shift+L` opens lyrics, `Ctrl+Shift+A` and `Ctrl+Shift+B` open the
current artist or album in the full player, and `O` expands the full player.

## See it in action

### Your playlists, instantly familiar

Everything is where you expect it to be—just faster, lighter, and dressed in
your Omarchy theme.

![Vietnam War Music playlist in Omarchy Spotify](docs/screenshots/vietnam-war-playlist.png)

### Everything from an artist, in one view

Top albums and EPs sit beside the artist's ten biggest songs, with their
**This Is** playlist and full catalog only a search away.

![Red Hot Chili Peppers artist page with Under the Bridge playing](docs/screenshots/red-hot-chili-peppers-under-the-bridge.png)

### Lyrics, already matched to the song

One click sends the current track to Omasing, where the lyrics are fetched and
lined up with your playback position—ready to auto-scroll as you listen.

![Omarchy Spotify beside Omasing lyrics for Under the Bridge](docs/screenshots/omasing-lyrics-under-the-bridge.png)

### A mini player that belongs in your desktop

The essentials are always one click away, without reopening the full app.

![Omarchy Spotify mini player playing Under the Bridge](docs/screenshots/mini-player-under-the-bridge.png)

## Set it up

To replace Omarchy's existing **Super+Shift+M · Music** binding, add this to
`~/.config/hypr/bindings.lua`:

```lua
  hl.unbind("SUPER + SHIFT + M") -- previously: Music
  o.bind("SUPER + SHIFT + M", "Omarchy Spotify",
    "omarchy shell -q quickshell.spotify.player togglePlayer")
```

Run `hyprctl reload` and check `hyprctl configerrors` after saving. Until the
binding is replaced, Omarchy's stock Music binding stays active and the
Settings choice below has no effect on the shortcut.

In Omarchy Spotify's Settings, choose whether that shortcut launches Omarchy's
Music app, toggles the full player, or toggles the mini-player. Separate
bindings can call `toggleMiniPlayer` or `toggleFullPlayer` on the same
`quickshell.spotify.player` target.

Raise or lower Spotify volume from a keybinding without opening the player:

```bash
omarchy shell -q quickshell.spotify.player volumeUp
omarchy shell -q quickshell.spotify.player volumeDown
```

Each step is 5%, the same as Ctrl+Up / Ctrl+Down. This changes Spotify's own
volume, including speakers, not the computer's output level.

Click the Spotify icon on the left side of the bar. The mini-player asks you
to **Set up and continue**, then Spotify sign-in finishes in your browser. You
can move the widget later with Omarchy's bar controls.

Local playback installs an exact-version backend only after its GitHub build
provenance matches this plugin version's tag and the checkout's backend inputs
still match that tagged source. If verification is unavailable, setup builds
the locked Rust source locally or offers Omarchy's packaged `spotifyd` fallback
instead of executing an unverified download.

## Seeing "Spotify is busy." or slow searches?

The plugin's Spotify Web API client ID is shared by every install worldwide,
and Spotify rate-limits requests **per app**, not per user. When that shared
quota runs out you see `Spotify is busy. Try again in N seconds.` and searches
that stall even though nothing is wrong on your side.

You can use a personal [Spotify Developer app](https://developer.spotify.com/dashboard)
with a separate quota. This does not provide unlimited requests or restore restricted endpoints.

1. Add `http://127.0.0.1:8989/login` as the app's redirect URI.
2. Set **Spotify Developer app client ID** in the plugin settings. Leave it empty
   to use the shipped app. Invalid IDs produce an error.
3. Authorize the selected app. Changing the ID clears the current session and
   account data; stored sessions are isolated by client ID.

Development apps require an eligible Premium owner and allowlisted users, and
have endpoint restrictions. See Spotify's [quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).
The local Connect authorization remains separate.

## Remove it completely

Run the bundled uninstaller from outside the plugin directory:

```bash
cd "$HOME" && "$HOME/.config/omarchy/plugins/quickshell.spotify/scripts/uninstall.sh"
```

It disables and removes the plugin, stops and removes both user services,
restarts the shell, and deletes all plugin-owned configuration, cached audio,
backend build files, installed binaries, playback state, runtime sockets, old
configuration backups, and matching GNOME Keyring entries.

If you prefer to inspect and paste the main steps individually:

```bash
plugin_dir="$HOME/.config/omarchy/plugins/quickshell.spotify"
cd "$HOME"
omarchy plugin disable quickshell.spotify 2>/dev/null || true
"$plugin_dir/scripts/remove-runtime.sh" --purge
omarchy plugin remove quickshell.spotify --yes
omarchy restart shell
```

The cleanup deliberately leaves unrelated software alone. A source checkout
outside Omarchy's plugin directory, separate plugins such as Omasing, and the
`spotifyd` package remain in place. If this plugin was the only reason you
installed the fallback package, remove it with:

```bash
omarchy pkg drop spotifyd
```

Very old installation instructions may also have added a custom Hyprland
shortcut. The uninstaller reports any such references without rewriting your
personal configuration. Check both the live config and, when applicable, its
chezmoi source:

```bash
rg -n 'quickshell\.spotify|Omarchy Spotify' \
  "$HOME/.config/hypr" "$HOME/.local/share/chezmoi" 2>/dev/null
```

Remove only the matching custom lines, apply the dotfiles change, and run
`hyprctl reload`. Omarchy's stock **Super+Shift+M** Music shortcut will then be
used again.

## More music, less app

- Discover Weekly, Release Radar, Daily Mixes, daylist, and more in **Discover**.
- Browse Liked Songs, saved albums, followed artists, podcasts, and books.
- Create playlists, add songs, reorder tracks, and turn followed playlists
  into your own editable copies when Spotify makes their contents available.
- Build a queue, start track radio, use shuffle and repeat, or set a sleep timer.
- Listen on this computer or switch to another Spotify Connect speaker or player.
- Choose the mini-player or full player independently for the bar icon and
  keyboard shortcut, use optional spinning vinyl artwork in the mini-player,
  show the title, artist, or both, and softly scroll overflowing text at an
  adjustable speed.
- Choose up to 320 kbps for local playback.

Your Spotify password is entered only on Spotify's own page. Omarchy Spotify
stores your saved session in GNOME Keyring and clears it when you log out.

Want the details? Read the [technical notes](docs/TECHNICAL.md) or see the
[memory benchmark](docs/BENCHMARK.md).

Omarchy Spotify is an independent project and is not affiliated with Spotify.
Spotify is a trademark of Spotify AB.

Licensed under the [MIT License](LICENSE).

## Hidden Gems documentation

Read the [Hidden Gems guide](docs/HIDDEN_GEMS.md) for the complete algorithm,
local data handling, and practical limits. The fork retains the upstream
[MIT license](LICENSE) and credits the original Omarchy Spotify project.
