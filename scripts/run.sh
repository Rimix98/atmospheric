#!/usr/bin/env bash
# Launcher for the weather overlay with test flags.
#
#   bash scripts/run.sh --rain        # run with forced rain
#   bash scripts/run.sh --snow        # snow
#   bash scripts/run.sh --fog         # fog
#   bash scripts/run.sh --thunder     # thunderstorm
#   bash scripts/run.sh --night       # night
#   bash scripts/run.sh --clear       # "clear" — check that the window hides
#   bash scripts/run.sh               # normal run (real weather)
#
# Flags must come FIRST; everything after them goes to quickshell as-is
# (e.g.: bash scripts/run.sh --rain --qs-extra-flags).
#
# If quickshell is already running — no restart needed, tests switch on the fly:
#   qs -p /path/to/atmospheric ipc call weather test rain
#   qs -p /path/to/atmospheric ipc call weather test off
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: run.sh [FLAG] [-- extra quickshell args]

Test flags (equivalent to ATMOSPHERIC_TEST=<mode>):
  --rain          rain
  --heavy-rain    heavy rain
  --drizzle       drizzle
  --snow          snow
  --fog           fog
  --fog-dense     dense fog (thicker, more visible)
  --blizzard      blizzard (dense slanted snow)
  --sleet         sleet
  --hail          hail (pellets over a thunderstorm)
  --thunder       thunderstorm (rain + flashes)
  --rainbow       rainbow after rain
  --cloudy        cloudy (slight dimming)
  --night         night (dimming + cool tone); combine with real state
  --clear         clear — the overlay should hide
  --off           no test (real weather)
  --test=MODE     arbitrary mode
  -h, --help      this help

Without a restart (if quickshell is already running):
  qs -p /path/to/atmospheric ipc call weather test <mode>     # e.g.: snow, thunder, off
  qs -p /path/to/atmospheric ipc call weather testMode         # current mode
EOF
}

mode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rain|--heavy-rain|--drizzle|--snow|--fog|--fog-dense|--blizzard|--sleet|--hail|--thunder|--rainbow|--cloudy|--night|--clear|--off)
            mode="${1#--}"
            shift
            ;;
        --test=*)
            mode="${1#--test=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            # Unknown — pass to quickshell as-is (it will complain about typos itself)
            break
            ;;
    esac
done

if [[ -n "$mode" && "$mode" != "off" ]]; then
    export ATMOSPHERIC_TEST="$mode"
    echo "Test mode: ATMOSPHERIC_TEST=$mode"
    echo "Turn off: qs -p /path/to/atmospheric ipc call weather test off   (or restart without the flag)"
fi

exec quickshell -p "$DIR" "$@"
