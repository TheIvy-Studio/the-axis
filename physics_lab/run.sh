#!/usr/bin/env bash
# the Axis · physics lab
# Обёртка: находит доступный интерпретатор Lua и запускает общий прогон.
#
#   ./run.sh                прогон всех экспериментов
#   ./run.sh --full         полный вывод
#   ./run.sh --only 04      один эксперимент
#   ./run.sh --svg --csv    записать графики и данные в out/

set -euo pipefail

cd "$(dirname "$0")"

for candidate in luajit lua5.4 lua5.3 lua; do
	if command -v "$candidate" > /dev/null 2>&1; then
		LUA="$candidate"
		break
	fi
done

if [ -z "${LUA:-}" ]; then
	echo "Не найден интерпретатор Lua (нужен luajit или lua 5.1+)" >&2
	exit 2
fi

mkdir -p out

exec "$LUA" run.lua "$@"
