#!/usr/bin/env bash
# Прячет погодный оверлей, пока открыто окно из списка классов (игры, mpv),
# и включает обратно, когда все такие окна закрыты.
#
# Слушает socket2 Hyprland (события openwindow/closewindow).
# Зависимости: socat, hyprctl, qs (quickshell).
#
# Запуск: exec-once = bash /path/to/atmospheric/scripts/autohide-games.sh
#
# Ограничение: если запустить скрипт, когда игра уже открыта, он об этом
# не узнает; скрипт должен стартовать до игр (обычно exec-once — как раз так).
set -u

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Классы окон, при которых оверлей гасится. Правьте под себя.
CLASSES_REGEX='^(mpv|steam_app_[0-9]+|gamescope)$'

SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${SIG}/.socket2.sock"

if [[ -z "$SIG" || ! -S "$SOCK" ]]; then
    echo "autohide-games: socket Hyprland не найден: $SOCK" >&2
    exit 1
fi

declare -A held    # адреса окон, из-за которых оверлей скрыт
openCount=0        # сколько таких окон открыто
hidden=0           # скрыли ли мы оверлей сами

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
            addr="${rest%%,*}"        # адрес окна
            rest="${rest#*,}"         # рабочая область
            rest="${rest#*,}"
            class="${rest%%,*}"       # класс окна
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
