#!/usr/bin/env bash
# ============================================================
# Установка atmospheric одной командой — из любого каталога.
#
#   bash /путь/до/atmospheric/install.sh
#
# Что делает:
#   1) кладёт команду `atmospheric` в PATH
#      (~/.local/bin, а если его нет в PATH — /usr/local/bin);
#   2) настраивает автозапуск под текущую среду:
#      Hyprland, Sway, niri, river, Wayfire, labwc, i3, bspwm, Openbox
#      — в родной конфиг; KDE, GNOME (Xorg), XFCE и прочие DE —
#      через XDG autostart (~/.config/autostart);
#   3) собирает радар-демон (если есть cargo);
#   4) при первом запуске спрашивает город (TUI).
#
# Опции:
#   --system          поставить в /usr/local/bin (через sudo)
#   --no-autostart    не трогать автозапуск
#   --autostart       то же, но явно включить автозапуск
#
# GNOME Wayland не поддерживается (нет wlr-layer-shell) — скрипт скажет
# об этом и не будет прописывать заведомо нерабочий автозапуск.
# ============================================================
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

exec "$HERE/atmospheric" install "$@"
