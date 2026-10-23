#!/usr/bin/env bash
# Hides the weather overlay while a window from the class list is open
# (games, mpv), and shows it again when all such windows are closed.
#
# Listens on the Hyprland socket2 (openwindow/closewindow events).
# Dependencies: socat, hyprctl, qs (quickshell).
#
# Run: exec-once = bash /path/to/atmospheric/scripts/autohide-games.sh
#
# Caveat: if the script starts while a game is already open, it won't
# know about it; the script must start before games (usually exec-once — exactly so).
set -u

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Window classes that hide the overlay. Edit to taste.
CLASSES_REGEX='^(mpv|steam_app_[0-9]+|gamescope)$'

SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${SIG}/.socket2.sock"

if [[ -z "$SIG" || ! -S "$SOCK" ]]; then
    echo "autohide-games: Hyprland socket not found: $SOCK" >&2
    exit 1
fi

declare -A held    # window addresses that currently hold the overlay hidden
openCount=0        # how many such windows are open
hidden=0           # whether we hid the overlay ourselves

hide() {
    if [[ $hidden -eq 1 ]]; then
        return 0
    fi
    qs -p "$DIR" ipc call weather disable >/dev/null 2>&1 || true
    hidden=1
}

show() {
    if [[ $hidden -eq 0 ]]; then
        return 0
    fi
    qs -p "$DIR" ipc call weather enable >/dev/null 2>&1 || true
    hidden=0
}

while IFS= read -r line; do
    case "$line" in
        openwindow\>\>*)
            rest="${line#openwindow>>}"
            addr="${rest%%,*}"        # window address
            rest="${rest#*,}"         # workspace
            rest="${rest#*,}"
            class="${rest%%,*}"       # window class
            if [[ "$class" =~ $CLASSES_REGEX && -z "${held[$addr]:-}" ]]; then
                held["$addr"]=1
                openCount=$((openCount + 1))
                hide
            fi
            ;;
        closewindow\>\>*)
            addr="${line#closewindow>>}"
            if [[ -n "${held[$addr]:-}" ]]; then
                unset "held[$addr]"
                openCount=$((openCount - 1))
                if [[ $openCount -le 0 ]]; then
                    openCount=0
                    show
                fi
            fi
            ;;
    esac
done < <(socat -U - "UNIX-CONNECT:$SOCK")
