#!/usr/bin/env bash
# Лаунчер погодного оверлея с тестовыми флагами.
#
#   bash scripts/run.sh --rain        # запуск с принудительным дождём
#   bash scripts/run.sh --snow        # снег
#   bash scripts/run.sh --fog         # туман
#   bash scripts/run.sh --thunder     # гроза
#   bash scripts/run.sh --night       # ночь
#   bash scripts/run.sh --clear       # «ясно» — проверка, что окно скрывается
#   bash scripts/run.sh               # обычный запуск (реальная погода)
#
# Флаги должны идти ПЕРВЫМИ, всё после них уходит в quickshell как есть
# (например: bash scripts/run.sh --rain --qs-extra-flags).
#
# Если quickshell уже запущен — перезапуск не нужен, тест переключается на лету:
#   qs -p /path/to/atmospheric ipc call weather test rain
#   qs -p /path/to/atmospheric ipc call weather test off
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
Использование: run.sh [ФЛАГ] [-- доп. аргументы quickshell]

Тестовые флаги (эквивалент ATMOSPHERIC_TEST=<mode>):
  --rain          дождь
  --heavy-rain    ливень
  --drizzle       морось
  --snow          снег
  --fog           туман
  --fog-dense     густой туман (плотнее и заметнее)
  --blizzard      метель (плотный косой снег)
  --sleet         дождь со снегом
  --hail          град (крупинки поверх грозы)
  --thunder       гроза (дождь + вспышки)
  --rainbow       радуга после дождя
  --cloudy        облачность (лёгкое затемнение)
  --night         ночь (затемнение + холодный тон); combine с реальным состоянием
  --clear         ясно — оверлей должен скрыться
  --off           без теста (реальная погода)
  --test=MODE     произвольный режим
  -h, --help      эта справка

Без перезапуска (если quickshell уже работает):
  qs -p /path/to/atmospheric ipc call weather test <режим>     # например: snow, thunder, off
  qs -p /path/to/atmospheric ipc call weather testMode         # текущий режим
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
            # Неизвестное — передаём quickshell как есть (он сам ругнётся на опечатку)
            break
            ;;
    esac
done

if [[ -n "$mode" && "$mode" != "off" ]]; then
    export ATMOSPHERIC_TEST="$mode"
    echo "Тестовый режим: ATMOSPHERIC_TEST=$mode"
    echo "Снять: qs -p /path/to/atmospheric ipc call weather test off   (или перезапустить без флага)"
fi

exec quickshell -p "$DIR" "$@"
