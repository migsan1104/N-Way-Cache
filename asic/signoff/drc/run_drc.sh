#!/usr/bin/env bash
set -euo pipefail
# Magic DRC on a P&R run's streamed GDS with the PDK's sky130A deck.
#
#   bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
#             <repo>/asic/signoff/drc/run_drc.sh [gds]'
#
# gds defaults to $SIGNOFF_PNR_DIR/outputs/<RUN_TAG>.gds. Results in
# $SIGNOFF_RESULTS/drc/: drc.rpt (every violation), drc_count.txt (by rule).
# DRAFT 2026-08-28 - not yet shaken down (waits on run 1's stage 09 GDS).
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDS="${1:-$(ls "$SIGNOFF_PNR_DIR"/outputs/*.gds 2>/dev/null | head -1)}"
[ -r "${GDS:-}" ] || { echo "ERROR: no GDS (run stage 09, or pass a path)" >&2; exit 1; }
OUT="$SIGNOFF_RESULTS/drc"; mkdir -p "$OUT"
[ -n "${MAGIC_RUN:-}" ] || { echo "ERROR: source asic/signoff/env.sh (MAGIC_RUN)" >&2; exit 1; }
TOP=$(basename "$GDS" .gds)

cat > "$OUT/drc.tcl" <<EOF
gds read $GDS
load $TOP
select top cell
drc euclidean on
drc style drc(full)
drc check
drc catchup
puts "DRC_BY_RULE_BEGIN"
drc list count
puts "DRC_BY_RULE_END"
drc list count total
puts "DRC_WHY_BEGIN"
drc why
puts "DRC_WHY_END"
quit -noprompt
EOF
echo "magic DRC: $GDS -> $OUT"
$MAGIC_RUN -dnull -noconsole -rcfile "$SKY130_MAGICRC" "$OUT/drc.tcl" > "$OUT/magic.log" 2>&1
sed -n '/DRC_BY_RULE_BEGIN/,/DRC_BY_RULE_END/p' "$OUT/magic.log" | grep -v 'DRC_BY_RULE' > "$OUT/drc_count.txt"
sed -n '/DRC_WHY_BEGIN/,/DRC_WHY_END/p'         "$OUT/magic.log" | grep -v 'DRC_WHY' > "$OUT/drc.rpt"
grep 'Total DRC errors found' "$OUT/magic.log" | tail -1
sort -t: -k2 -rn "$OUT/drc_count.txt" 2>/dev/null | head -15
