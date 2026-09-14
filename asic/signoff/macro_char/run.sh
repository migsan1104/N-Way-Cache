#!/usr/bin/env bash
# ./run.sh <period_ns> <load_fF> [extra gen_deck args]  -> runs ngspice-41 in <dir>, log <dir>/ngspice.log
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
P=${1:?period}; L=${2:?load}; shift 2
D="$HERE/run_p${P/./p}_l${L/./p}"
python3 "$HERE/gen_deck.py" --period "$P" --load "$L" --out "$D" "$@" || exit 1
cd "$D" && echo "start $(date +%H:%M:%S)" > ngspice.log && \
  "$HOME/ngspice41env/bin/ngspice" -b deck.sp >> ngspice.log 2>&1; rc=$?
echo "MACRO_CHAR_DONE rc=$rc $(date +%H:%M:%S)" >> "$D/ngspice.log"
