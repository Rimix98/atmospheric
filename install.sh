#!/usr/bin/env bash
# ============================================================
# Install atmospheric in one command — from any directory.
#
#   bash /path/to/atmospheric/install.sh
#
# What it does:
#   1) puts the `atmospheric` command in PATH
#      (~/.local/bin, or /usr/local/bin if that is not in PATH);
#   2) sets up autostart for the current environment:
#      Hyprland, Sway, niri, river, Wayfire, labwc, i3, bspwm, Openbox
#      — into the native config; KDE, GNOME (Xorg), XFCE and other DEs —
#      via XDG autostart (~/.config/autostart);
#   3) builds the radar daemon (if cargo is available);
#   4) asks for the city on first run (TUI).
#
# Options:
#   --system          install to /usr/local/bin (via sudo)
#   --no-autostart    do not touch autostart
#   --autostart       same, but explicitly enable autostart
#
# GNOME Wayland is not supported (no wlr-layer-shell) — the script will
# say so and skip writing an autostart that cannot work.
# ============================================================
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

exec "$HERE/atmospheric" install "$@"
