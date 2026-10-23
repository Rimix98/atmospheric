#!/usr/bin/env bash
# Screenshot WITHOUT the weather overlay — a thin wrapper over `atmospheric shot`.
# The overlay is turned off before the capture and back on after (see `atmospheric shot --help`).
#
# Usage:
#   bash scripts/screenshot.sh                     # full screen → ~/Pictures/Screenshot_*.png
#   bash scripts/screenshot.sh --region            # select a region (slurp / maim -s)
#   bash scripts/screenshot.sh --clipboard         # put into the clipboard
#   bash scripts/screenshot.sh --out ~/shot.png    # save to a file
#   bash scripts/screenshot.sh --monitor DP-1      # specific output (grim -o)
#   bash scripts/screenshot.sh --qs-region         # Quickshell region selector
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

exec "$DIR/atmospheric" shot "$@"
