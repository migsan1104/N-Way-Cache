#!/usr/bin/env bash
set -euo pipefail
# Validation step 1+2 (README "Validation"): extract the plate/wire test
# structure natively and through Quantus, compare both to the tech LEF model.
#
#   bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
#             <repo>/asic/signoff/quantus/validate/run_validate.sh [corner]'
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CORNER="${1:-nom}"
TCH="$HERE/../techfiles/sky130A_$CORNER.tch"
[ -r "$TCH" ] || { echo "ERROR: techfile not built: $TCH" >&2; exit 1; }
OUT="$HERE/out_$CORNER"; rm -rf "$OUT"; mkdir -p "$OUT"

python3 "$HERE/gen_teststruct.py"
for mode in native qrc; do
    echo "== extract ($mode)"
    ( cd "$OUT" && VAL_MODE=$mode VAL_QRC="$TCH" VAL_OUT="$OUT" \
      innovus -no_gui -files "$HERE/extract.tcl" -log "$OUT/innovus_$mode" > "$OUT/run_$mode.out" 2>&1 ) \
      || { echo "innovus ($mode) failed - see $OUT/run_$mode.out"; tail -20 "$OUT/run_$mode.out"; exit 1; }
    [ -s "$OUT/teststruct_$mode.spef" ] || { echo "no SPEF from $mode extraction:"; grep -m3 'ERROR' "$OUT/run_$mode.out"; exit 1; }
done
python3 "$HERE/compare.py" "$HERE/expected_lef.csv" "$OUT/teststruct_native.spef" "$OUT/teststruct_qrc.spef" | tee "$OUT/compare.txt"
