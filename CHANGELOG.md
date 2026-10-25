# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- AUR package `atmospheric`: `aur/` holds the `PKGBUILD`, the launcher that
  keeps a writable per-user copy of the overlay in
  `~/.config/quickshell/atmospheric` (the picker writes `Config.qml` in
  place, so the copy is refreshed on package upgrades with the city carried
  over), and the pacman install message. `make aur` builds it locally,
  `make aur-sync` pushes the files into an AUR clone.

## [1.0.1] — 2026-10-25

The release translated into English.

### Changed

- Every user-facing string is English now: the `atmospheric` CLI, quickshell
  logs, `scripts/`, `hyprland.conf.snippets`, `install.sh`, the README and the
  Rust daemon output.
- Default coordinates are New York (40.7128, -74.0060) and the bundled picker
  list is a world city list (`assets/cities.txt`, `Name|latitude|longitude`);
  `assets/cities-ru.txt` is gone — `/` in the picker searches any city in the
  world via Nominatim anyway.
- SVG sprites (`drop`, `flake`, `cloud`) redrawn with English labels.

## [1.0.0] — 2026-10-22

First public release.

### Added

- Transparent weather overlay on Quickshell: rain, downpour, drizzle, snow,
  fog (including dense), thunderstorm with lightning, rainbow after rain,
  sleet, blizzard and hail.
- Weather without API keys: a race between Open-Meteo and met.no (Yr), the
  first successful response wins; day/night computed from solar altitude.
- RainViewer precipitation radar: a Rust daemon (network + PNG decode) talks to
  QML over a unix socket; stale or failed data falls back smoothly to the
  forecast.
- Fog from two signals: WMO code 45/48 and Open-Meteo visibility (< 1000 m),
  dense fog below 300 m.
- Universal graphics: Wayland compositors with `wlr-layer-shell` (Hyprland,
  Sway, niri, river, Wayfire, labwc, KDE Plasma) and X11 (i3, bspwm, Openbox,
  XFCE, KDE/GNOME on Xorg).
- One-command install (`install.sh`): command in PATH, autostart in the native
  compositor config or XDG autostart, radar build, city picker (TUI).
- Test modes that never touch the API: launch flags and IPC
  (`atmospheric rain|snow|fog|thunder|rainbow|…`).
- `atmospheric shot` — screenshots without the overlay: rain is hidden before
  the capture and restored after. Region (`slurp`), full screen, clipboard, a
  specific monitor and the Quickshell region selector (`--qs-region`);
  `scripts/screenshot.sh` became a thin wrapper. Parallel shots are serialized,
  so two binds on one key don't interfere.
- `atmospheric uninstall` — removes autostart and PATH symlinks cleanly.
- Search for any city in the world: the city TUI gained a `/` key — the query
  goes to Nominatim (OpenStreetMap) and returns up to 8 matches with the
  country; coordinates (`55.75,37.61`) are accepted instead of a name and need
  no network. `atmospheric install` also asks for a city (Enter — pick,
  q — keep the current one). Offline — the bundled list `assets/cities.txt`
  (world cities) still works.

### Fixed

- Night mode no longer changes screen brightness by default: only a 6% cold
  tint (`nightDim: false`).
- Rain is drawn bluish, not white; snowflakes use a own drawn SVG.
- Real-time reaction to weather changes: effects fade in/out on state change,
  no restart needed.
- Launch in a separate session (`setsid`): the overlay survives the terminal
  or script it was started from.

### Known limitations

- GNOME Wayland is not supported: Mutter lacks `wlr-layer-shell`.
- On X11 without a compositor (picom) there is no transparency.
- Game auto-hide (`scripts/autohide-games.sh`) is Hyprland-only (socket2).
