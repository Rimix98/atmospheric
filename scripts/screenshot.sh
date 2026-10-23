#!/usr/bin/env bash
# Скриншот БЕЗ погодного оверлея — тонкая обёртка над `atmospheric shot`.
# Оверлей гасится до захвата и включается обратно после (см. `atmospheric shot --help`).
#
# Использование:
#   bash scripts/screenshot.sh                     # весь экран → ~/Pictures/Screenshot_*.png
#   bash scripts/screenshot.sh --region            # выделить область (slurp / maim -s)
#   bash scripts/screenshot.sh --clipboard         # положить в буфер обмена
#   bash scripts/screenshot.sh --out ~/shot.png    # сохранить в файл
#   bash scripts/screenshot.sh --monitor DP-1      # конкретный выход (grim -o)
#   bash scripts/screenshot.sh --qs-region         # селектор области Quickshell
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

exec "$DIR/atmospheric" shot "$@"
