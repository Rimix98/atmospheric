# atmospheric — weather overlay on Quickshell

**v1.0.0** · MIT · Wayland and X11

A fullscreen transparent overlay: rain, snow, fog, thunderstorm, hail,
blizzard, sleet, rainbow and night — driven by Open-Meteo / met.no (Yr).
It never steals clicks or moves windows, and hides itself in clear weather.
Works on Wayland compositors with `wlr-layer-shell` and on X11.

## Quick start

```bash
git clone https://github.com/Rimix98/atmospheric.git
cd atmospheric
./install.sh
```

During install a city picker opens in the same terminal: arrows to navigate,
**`/`** to search any city in the world (needs network), **Enter** to pick,
**q** to skip. Then:

```bash
atmospheric      # start the overlay
```

Check state with `atmospheric status`; try effects with `atmospheric rain`,
`atmospheric snow`, `atmospheric auto`.

## Structure

```
atmospheric/
├── install.sh               # one-command install (from any directory)
├── atmospheric              # single command: install / rain / snow / status / autostart ...
├── shell.qml                # Scope: Config + Weather + IpcHandler + Variants<window>
├── OverlayWindowWayland.qml # wlr-layer-shell window (Wayland)
├── OverlayWindowX11.qml     # fullscreen X11 window (aboveWindows, click-through)
├── Config.qml               # ALL settings in one place
├── Weather.qml              # Open-Meteo + met.no (Yr) race, WMO mapping, timers
├── Radar.qml                # RainViewer reader fed by the Rust daemon (unix socket, JSON)
├── radar-backend/           # Rust daemon: RainViewer network + PNG decode (cargo build --release)
├── WeatherOverlay.qml       # effect selection from weather state
├── effects/
│   ├── Rain.qml             # QtQuick.Particles: elongated drops along the wind
│   ├── Snow.qml             # SVG flakes, two depth layers, rotation (+ blizzard)
│   ├── Fog.qml              # small clouds, very slow drift
│   ├── Lightning.qml        # rare flash on a random interval
│   └── Rainbow.qml          # seven-band arc after rain
├── assets/
│   ├── drop.svg             # drop sprite (square with a line — scales evenly)
│   ├── flake.svg            # drawn snowflake: 6 spokes with twigs
│   ├── rainbow.svg          # rainbow arc (7 bands, soft edge)
│   └── cities.txt           # world cities for the TUI picker (Name|lat|lon)
├── scripts/
│   ├── run.sh               # launcher with test flags: --rain, --snow, ...
│   ├── screenshot.sh        # thin wrapper over atmospheric shot
│   └── autohide-games.sh    # hide the overlay for games/mpv (Hyprland socket2)
├── hyprland.conf.snippets   # ready-made lines for hyprland.conf
├── Makefile                 # make check / install / dist
├── VERSION                  # current version (1.0.0)
├── CHANGELOG.md             # change history
└── LICENSE                  # MIT
```

## City picker (TUI)

`atmospheric install` asks for a city: **Enter** opens the picker, **q** keeps
the current one (on first run, with no city set, the menu opens right away).
The menu shows a bundled list `assets/cities.txt` (format `Name|latitude|longitude`,
append your own cities as lines) plus a **search for any city in the world**:
press **/**, type e.g. `Tokyo` or `Paris, Texas` — the query goes to Nominatim
(OpenStreetMap, network required) and returns up to 8 matches with the country.
Instead of a name you can type coordinates (`55.75,37.61`) — accepted both by
the search and directly.

- Controls: **arrows** or `W vim` (↑/↓), **Enter** to pick, **/** to search
  (empty query returns to the file list), **q** cancels. The list scrolls in an
  18-line window with the current row highlighted.
- The pick is written to `Config.qml` (`city`, `latitude`, `longitude`) —
  quickshell hot-reloads it, the overlay refetches weather for the new city
  right away, and `atmospheric status` starts showing `city=...`.
- Pick again any time: `atmospheric city`.
- Without a TTY a numbered list is printed: a number picks the city, any other
  input goes to search (then it asks for a number again); with stdin closed the
  choice is skipped with a hint.
- No network or no curl — the bundled list still works; install never breaks.
- Until a city is chosen, default coordinates are used (New York).

## Running

**Install** — see [Quick start](#quick-start) above: clone, `./install.sh` and
the city picker in the terminal. The script (works for any graphics stack —
Wayland and X11):

1. puts the `atmospheric` command into PATH (`~/.local/bin`, or
   `/usr/local/bin` if `~/.local/bin` is not in PATH);
2. checks dependencies;
3. builds the radar daemon (if `cargo` is available);
4. writes autostart into the right place for your session (with a backup);
5. asks for a city on first run (TUI).

Options: `--system` — install to `/usr/local/bin` via sudo; `--no-autostart` —
leave autostart alone; `--autostart` — enable it explicitly.

**Where autostart goes:**

| Session | File |
|---|---|
| Hyprland | `~/.config/hypr/hyprland.conf` → `exec-once = quickshell -p …` |
| Sway | `~/.config/sway/config` → `exec quickshell -p …` |
| niri | `~/.config/niri/config.kdl` → `spawn-at-startup "quickshell" "-p" "…"` |
| river | `~/.config/river/init` → `quickshell -p … &` |
| Wayfire | `~/.config/wayfire.ini` → `[autostart] atmospheric = quickshell -p …` |
| labwc | `~/.config/labwc/autostart` |
| i3 | `~/.config/i3/config` → `exec --no-startup-id …` |
| bspwm | `~/.config/bspwm/bspwmrc` |
| Openbox | `~/.config/openbox/autostart` |
| KDE, GNOME (Xorg), XFCE, Cinnamon, MATE, LXQt, Budgie and other DEs | `~/.config/autostart/atmospheric.desktop` (XDG) |

Check detection and toggle autostart:

```bash
atmospheric autostart status   # session + file + configured?
atmospheric autostart off      # remove (with a backup)
atmospheric autostart on       # put it back
```

**Supported:**

- **Wayland with `wlr-layer-shell`:** Hyprland, Sway, niri, river, Wayfire,
  labwc, KDE Plasma 6 — the overlay is its own layer (`WlrLayer.Top`/`Overlay`).
- **X11:** any WM/DE (quickshell built with the X11 backend) — i3, bspwm,
  Openbox, XFCE, KDE/GNOME on Xorg. Fullscreen window, `aboveWindows` + an
  empty input mask. Bare WMs need a compositor (picom) for transparency; DEs
  already have one.
- **GNOME Wayland is NOT supported:** Mutter has no `wlr-layer-shell`, so the
  overlay cannot layer over windows. The installer detects this and skips
  autostart that could never work. Options: GNOME on X11 (Xorg) or another
  compositor.

Then:

```bash
atmospheric            # start the overlay (or enable it if already running)
atmospheric rain       # see rain right away
atmospheric snow       # snow
atmospheric auto       # back to real weather
atmospheric status     # session, what's shown, test mode
atmospheric stop       # stop
atmospheric uninstall  # remove the command from PATH and autostart
atmospheric --help     # all commands
atmospheric version    # version
```

**Manually, without installing the command:**

```bash
quickshell -p /path/to/atmospheric
```

The config can live anywhere (`-p` = path), or symlink it:

```bash
ln -s /path/to/atmospheric ~/.config/quickshell/atmospheric
quickshell -c atmospheric
```

Quickshell re-reads QML on every file save — edits show up immediately.

A package with the SVG renderer (`qtsvg`) is required — QtQuick needs it for
`drop.svg`. `QtQuick.Particles` ships with qtdeclarative alongside Qt.

## Requirements

| What | Why | Tested with |
|---|---|---|
| Quickshell ≥ 0.3 | window, IPC, layers | 0.3.2 |
| Qt 6.6+ and `qtsvg` | QML engine, SVG drops and flakes | 6.12 |
| Wayland compositor with `wlr-layer-shell`, or X11 | window above others | Hyprland, XWayland |
| `cargo` + Rust (optional) | radar daemon build; forecast and effects work without it | 1.9x |
| `socat` (optional) | auto-hide in games on Hyprland | — |
| `grim` / `maim` / `scrot` / `import` (optional) | screenshots without the overlay | grim 1.4 |

The installer checks dependencies and suggests a package for your distro.

## Known limitations

- **GNOME Wayland is not supported:** Mutter lacks `wlr-layer-shell`.
  GNOME on Xorg works, as does any layer-shell compositor.
- **X11 without a compositor:** no transparency — install `picom` (DEs have one).
- **Screenshots:** a direct `grim`/`hyprshot` capture includes the overlay.
  Use `atmospheric shot` — it hides the rain for the frame and restores it.
- **Game auto-hide** (`scripts/autohide-games.sh`) — Hyprland only (socket2).
- **Quickshell packages** are built differently: X11 needs `-DX11=ON`
  (enabled in the Arch package).

## Weather details

`Weather.qml` **races two providers** — Open-Meteo and met.no (Yr, the Norwegian
meteorological service, no API key). Requests fly in parallel, the first success
wins, the loser is cancelled. Polling runs every `Config.refreshMinutes`
(10 minutes by default, plus 0..2 minutes of randomness — met.no terms ask not
to hit their API on a fixed schedule). On total failure both providers retry
every 60 seconds.

**Why two providers.** From some networks the route to `api.open-meteo.com` is a
black hole (verified live) while met.no answers in ~0.3 s — the overlay keeps
working either way. Yr returns symbolic codes (`lightrain`, …), `yrToWmo`
translates them to the nearest WMO code and the same mapping table applies.
`is_day` is missing in Yr — solar altitude is computed locally (SunCalc formula).

WMO mapping (`stateFor`):

| Codes         | State       | Effect                                |
|---------------|-------------|---------------------------------------|
| 0–1           | `clear`     | window hidden                         |
| 2–3           | `cloudy`    | nothing (cloud effect removed)        |
| 45, 48        | `fog`       | fog                                   |
| 51–55         | `drizzle`   | light drizzle                         |
| 56, 57, 66, 67| `sleet`     | rain with snow (freezing rain)        |
| 61–63, 80     | `rain`      | rain                                  |
| 65, 81–82     | `heavyRain` | downpour                              |
| 71–77, 85–86  | `snow`      | snow                                  |
| 95–99         | `thunder`   | rain + lightning flashes              |
| 96, 99        | `thunder` + hail | + fast white grains             |

**Fog by visibility (second signal).** Open-Meteo returns `visibility` in meters:
below `fogVisibilityM` (1000 m) fog turns on even without codes 45/48 (rain/snow/
thunderstorm outrank it). Below `fogDenseVisibilityM` (300 m) — dense fog.
Yr has no visibility parameter, so the signal is simply unavailable there.

**Modifiers:** `hail` (only with thunder, WMO 96/99) and `blizzard` (snow with
wind ≥ `blizzardWind` 8 m/s) are flags over `thunder`/`snow`, not separate states.

**Rainbow** (`rainbow`) — a bonus over the data: rain ended within the last
`rainbowMinutes` (30 min), sky is clear, the sun is low (0.5–42° — primary-rainbow
physics), daytime. A seven-band arc (`assets/rainbow.svg`) fades in over 3 s.

`intensityFor` gives a 0..1 multiplier (drizzle 0.3, downpour 1.0) scaling
`emitRate` and fall speed; wind speed/direction become drop `tilt` (±25°) and
horizontal snow drift.

**Errors:** any network error goes to `lastError` — the state is never reset to
"clear", the last known weather stays on screen. If nothing ever arrived
(`loaded: false`), the window stays hidden.

**Honest weak spot:** point-API weather can disagree with what's outside the
window — especially drizzle and local showers. Perfect "vibe" match won't
happen, and that's fine.

## Effects and tuning

1. **Rain** — `Emitter` at the top edge, `drop.svg` sprite (a line in a square:
   `ImageParticle` scales the image into the particle's square, so the drop is
   not distorted). Tilt = sprite `rotation` + `AngleDirection.angle`. The color
   is **bluish** (`rainColor: #7fa9e6`), soft opacity (`rainOpacity: 0.30`).
2. **Snow** — drawn SVG flake (`assets/flake.svg`), two depth layers (far: small,
   frequent, fast; near: large, slow), random orientation + slow
   `rotationVelocity`. Wind drift via `acceleration`. `snowOpacity: 0.42`.
3. **Fog** — small clouds from a drawn SVG (`assets/cloud.svg`, soft radial
   puffs). Very slow drift: `fogSpeed: 12` px/s ≈ 2.5 min to cross. Two depth
   layers; `Emitter.burst()` fills the screen on spawn, then rare additions.
   Soft grey-blue `fogColor: #ccd9ea` — readable on white pages and wallpapers.
4. **Thunderstorm** — heavier than downpour (`thunderRate: 350` vs
   `heavyRainRate: 260`) + a `Timer` with a random 5–16 s interval: 55 ms flash
   up, a short dip, a second kick, 450 ms fade. Peak `flashPeakOpacity: 0.20`.
5. **Hail** — the same `Rain` as a second instance over the storm: short, fast,
   **white** grains (`hailColor: #e3eefb`). Enabled by `effectiveHail` (WMO 96/99).
6. **Sleet** — `Rain` (short drops) and `Snow` at once: wet snow falls as both.
7. **Blizzard** — snow modifier at wind ≥ `blizzardWind` (8 m/s): density ×2.2,
   speed ×1.7, wind drift ×2.5, angular variety mostly removed — flakes fly as
   slanted parallel streaks.
8. **Rainbow** — seven bands (`assets/rainbow.svg`, soft `feGaussianBlur` edge)
   sunk behind the bottom edge; fades in over 3 s, quiet at `rainbowOpacity: 0.40`.
9. **Night** — a `#0a1a3a` rectangle at `is_day = 0`. By default only an icy tint
   (`nightTintOpacity: 0.06`); full dimming (`nightDim: true`,
   `nightOpacity: 0.18`) actually lowers brightness — enable it deliberately.

### Performance

- **The window hides when there is no effect.** `visible:` follows
  `weather.active` — clear (and not night) means no window and no scene at all.
- **100–300 particles.** Real count ≈ `rate × lifetime`. Tune the numbers in
  `Config.qml`; `heavyRainRate` is the main cost.
- No separate FPS switch exists in QtQuick: rendering is already vsync-limited.
  If the GPU struggles, lower `emitRate`. `updatesEnabled: false` on the window
  (`QsWindow`) helps for static states.
- `maximumEmitted` on `Emitter` is a hard cap on live particles.

### Config.qml tuning table

| Property | Default | What it does |
|---|---|---|
| `rainRate / heavyRainRate / drizzleRate` | 150 / 260 / 60 | particles per second |
| `thunderRate` | 350 | storm particles per second |
| `snowRate` | 18 | flakes per second |
| `rainColor` | `#7fa9e6` | drop color (bluish) |
| `rainOpacity` | 0.30 | rain visibility (lower = quieter) |
| `rainLength` | 20 | drop length, px |
| `snowColor` | `#e8f1ff` | flake color |
| `snowOpacity` | 0.42 | snow visibility |
| `snowSize` | 11 | base flake size, px |
| `fogDensity` | 2.5 | cloud count multiplier |
| `fogSpeed` | 12 | fog drift speed, px/s |
| `fogOpacity` | 0.45 | fog visibility |
| `fogColor` | `#ccd9ea` | cloud color (grey-blue) |
| `fogVisibilityM / fogDenseVisibilityM` | 1000 / 300 | fog from Open-Meteo visibility, meters |
| `blizzardWind` | 8 | snow + stronger wind = blizzard |
| `sleetRainRate / sleetSnowRate` | 90 / 12 | rain and snow parts of sleet |
| `hailRate / hailColor` | 240 / `#e3eefb` | hail grains: rate and color (white) |
| `rainbowEnabled / rainbowMinutes` | true / 30 | rainbow after rain: on/off and window |
| `rainbowMaxSunAlt / rainbowOpacity` | 42 / 0.40 | sun altitude (°) and arc visibility |
| `flashPeakOpacity` | 0.20 | flash brightness |
| `nightDim / nightOpacity` | false / 0.18 | night screen dimming — **off** by default |
| `nightTintOpacity` | 0.06 | cold night tint, barely touches brightness |
| `dimCloudy / cloudyDimOpacity` | false / 0.10 | overcast dimming — **off** |
| `refreshMinutes` | 10 | weather polling interval (+0..2 min random) |
| `radarMinutes` | 3 | RainViewer frame list polling |
| `radarMaxAgeMinutes` | 25 | radar frame freshness; older — forecast decides |

## Real time: precipitation radar

The forecast updates hourly, so there is a second, faster source — the
**RainViewer radar**: a mosaic refreshed every 10 minutes, an *observation*,
not a forecast.

All heavy lifting lives in a **Rust daemon** (`radar-backend/`): Quickshell
paints `Canvas` only inside a visible window, and `Weather` lives in a `Scope`
where `onPaint` would never fire. The daemon, a separate process:

- every `radarMinutes` (3 min) fetches the frame list (~10 KB); on a new frame
  it loads one district tile (z=10, ~250 m/px), decodes the PNG and reads the
  pixel at our coordinates;
- serves the ready state as a JSON line over a unix socket
  (`/tmp/atmospheric-radar.sock`); `Radar.qml` only parses — no XHR, no Canvas;
- starts itself: a `Process` inside `Radar.qml` launches it with the shell, a
  watchdog (2 s) restarts it if it dies and recreates the socket on failure;
  a second instance exits on its own.

Layer rules over the forecast:

- **opaque pixel → precipitating now**: rain/snow turns on even if the forecast
  says clear (a downpour can start ahead of the forecast);
- **transparent pixel → no precipitation**: forecast rain/snow/thunder bins are
  muted (drizzle is nearly invisible to radar and stays from the forecast);
- rain vs snow decided by forecast temperature (≤ 0.5 °C — snow), intensity by
  pixel grey level (black weak, white strong);
- a frame older than `radarMaxAgeMinutes` (25 min) or RainViewer down —
  `fresh=false` and the forecast decides everything (fail-open layer);
- fog, clouds, wind and temperature always come from the forecast: radar can't
  see them.

Check: `atmospheric status` → `radar=on/4m` (precipitating, frame age),
`radar=off/4m` (clean), `radar=stale` (old frame), `radar=none` (unavailable).
Suffix `!daemon down` means the Rust daemon isn't up; `!fetch-tile` and friends
mean RainViewer is unreachable — details are in the quickshell log prefixed
`[radar]`. One pass without QML: `cd radar-backend && cargo run --release
--bin smoke -- 40.7128 -74.0060`. Radar data © RainViewer.

## Test modes (flags)

To skip waiting for real rain, effects can be forced. A test **does not touch
real data**: both providers keep polling while the chosen state is layered on top.

```bash
atmospheric rain       # rain
atmospheric snow       # snow
atmospheric thunder    # thunderstorm
atmospheric auto       # back to real weather
```

Works on a running overlay (via IPC, instantly) and on a stopped one (starts it
with the test).

```bash
bash scripts/run.sh --rain        # flags: --rain --snow --fog --thunder
                                  # --night --clear --off --help
ATMOSPHERIC_TEST=snow quickshell -p /path/to/atmospheric
```

Flags come first (the rest goes to quickshell); the script `exec`s quickshell
itself. Quickshell takes no `--rain` of its own — hence the environment variable.

On the fly over IPC (`qs` requires `-p <config path>`):

```bash
qs -p /path/to/atmospheric ipc call weather test rain  # turn rain on
qs -p /path/to/atmospheric ipc call weather test off   # real weather again
qs -p /path/to/atmospheric ipc call weather testMode   # current mode
qs -p /path/to/atmospheric ipc call weather status     # state/code/error
qs -p /path/to/atmospheric ipc show                    # all IPC targets
```

Modes: `rain`, `heavy-rain`, `drizzle`, `snow`, `fog`, `fog-dense`, `blizzard`,
`sleet`, `hail`, `thunder`, `rainbow`, `cloudy`, `night`, `clear`, `off`.
An unknown name returns a hint with the list. With `Config.debugSquare: true`
the bottom-left corner shows `TEST[...] state=... code=...` — what really came
from the API vs what the test substituted.

## Behavior over windows

The default layer is **`Top`** — fullscreen video and games cover the overlay.
Set `Config.layer = "overlay"` to keep it above everything (applies on restart/
reload). On X11 there are no layers: the window is always "above normal windows"
(`aboveWindows`), fullscreen apps cover it.

Hotkey via quickshell IPC (Hyprland examples in `hyprland.conf.snippets`):

```bash
qs -p /path/to/atmospheric ipc call weather toggle      # on/off
qs -p /path/to/atmospheric ipc call weather enable      # force on
qs -p /path/to/atmospheric ipc call weather disable     # force off
qs -p /path/to/atmospheric ipc call weather refresh     # refetch manually
```

The command is the same everywhere; in a DE just bind it to a key
(`bindsym` in Sway/i3, "Custom Shortcuts" in KDE/GNOME).

**Game/mpv auto-hide** — `scripts/autohide-games.sh`: listens on Hyprland
socket2, hides the overlay on `openwindow` with a class matching
`mpv|steam_app_*|gamescope`, re-enables it when the last such window closes.
Hyprland only (socket2); on other sessions simply don't run it.

**Sleep and network.** After wake-up the next main-timer tick fires (≤10 min);
faster: `qs -p /path/to/atmospheric ipc call weather refresh`. Offline, the state
freezes on the last known weather and retries quietly once a minute.

**Screenshots.** The layer shows up in grim captures — a Wayland property, not a
bug. Use `atmospheric shot`: it hides the overlay, waits for the layer to
actually vanish (on Hyprland via `hyprctl layers`, plus a pause: per-pixel
measurement shows the frame only clears by ~0.6 s), takes the shot and restores
the overlay via `trap` — even on a cancelled selection or an error.

```bash
atmospheric shot                      # full screen → ~/Pictures/Screenshot_*.png
atmospheric shot --region             # pick a region (slurp; X11 — maim -s)
atmospheric shot --clipboard          # to clipboard (wl-copy / xclip)
atmospheric shot --out ~/shot.png     # to a file
atmospheric shot --monitor DP-1       # a specific output (grim -o)
atmospheric shot --qs-region          # Quickshell's own selector (qs -c …)
```

Shots are serialized: if one key has two binds (region + full screen), the
second waits for the first and never re-enables the overlay mid-selection.

## Diagnostics

| Symptom | Diagnosis | Fix |
|---|---|---|
| `err=network error`, `code=-1` | both APIs unreachable from your network | Compare: `curl -m5 'https://api.open-meteo.com/v1/forecast?latitude=40.71&longitude=-74.01&current=weather_code&timezone=auto'` and `curl -m5 'https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=40.71&lon=-74.01'`. If the first hangs, the built-in second provider already covers it |
| `qs ... Not ready to accept queries yet` | a live process hung after a QML hot-reload | `atmospheric restart` |
| Log shows unsupported image format for `*.svg` and/or an incompatible Qt library | Qt was updated; the live process has old libraries in memory, new plugins on disk | `atmospheric restart` (a fresh start decodes SVG cleanly) |
| Drops/flakes invisible although `state=rain` | sprites not decoding | see the row above |
| Screen visibly dims in the evening | night dimming `nightDim` is on | Default is `nightDim: false` — only the `nightTintOpacity` tint remains; remove that too: `nightTintOpacity: 0` |
| Rain stopped outside but visuals continue | Yr is an hourly **forecast**: `next_1_hours` shows rain until the hour boundary or the next revision. "Right now" comes from the RainViewer radar | `atmospheric status`: `radar=on/4m` — precipitating (frame age), `radar=off/4m` — clean spot; `radar=stale` / `radar=none` — radar silent, the forecast decides (`!daemon down` — Rust daemon not up, `!fetch-*` — RainViewer unreachable; details in the qs log, prefix `[radar]`) |

Logs: `/tmp/atmospheric.log` (when started via `atmospheric`) and
`/run/user/1000/quickshell/by-id/*/log.log` (always, human-readable).
Quick checks: `atmospheric status`, `hyprctl layers | grep weather`.

## Development and release

```bash
make            # checks: bash -n + qmllint + cargo check
make run        # start the overlay
make dist       # dist/atmospheric-<version>.tar.gz (without target/ and local files)
make clean      # remove dist/ and target/
```

The version lives in `VERSION` and is mirrored in `radar-backend/Cargo.toml`;
changes are in `CHANGELOG.md`. When editing `Config.qml` keep in mind that
quickshell reloads the config on every save, while `sed -i` replaces the inode
and does not trigger a hot-reload — save the file normally.

## License

MIT — see `LICENSE`.

Data and services:

- forecast — [Open-Meteo](https://open-meteo.com/) (CC BY 4.0);
- second provider — [met.no](https://www.met.no/) (© MET Norway);
- radar — [RainViewer](https://www.rainviewer.com/) (data © RainViewer).

The overlay shows no text data, so in-UI attribution is not required, but do
credit the sources when publishing screenshots with the radar.
