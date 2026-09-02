#!/usr/bin/env bash
set -euo pipefail
# Magic DRC on a P&R run's streamed GDS with the PDK's sky130A deck.
#
#   bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
#             <repo>/asic/signoff/drc/run_drc.sh [gds]'
#
# gds defaults to $SIGNOFF_PNR_DIR/outputs/<RUN_TAG>.gds. Results in
# $SIGNOFF_RESULTS/drc/: drc.rpt (every violation), drc_count.txt (by rule).
#
# MACRO EXCLUSION (2026-09-01, drc.md): the OpenRAM SRAM macros are emptied
# after gds read. Their bitcell arrays use foundry-waived SRAM rules that
# drc(full) flags by design - the 2026-09-01 full-chip run drowned in 18.2M
# error tiles of macro-internal FEOL noise. The vendor macro GDS is treated
# as golden; what this checks is std cells + routing. Known blind spot:
# spacing between top-level routing and macro-internal metal is not checked
# (macro obstructions vanish with the cell contents).
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDS="${1:-$(ls "$SIGNOFF_PNR_DIR"/outputs/*.gds 2>/dev/null | head -1)}"
[ -r "${GDS:-}" ] || { echo "ERROR: no GDS (run stage 09, or pass a path)" >&2; exit 1; }
OUT="$SIGNOFF_RESULTS/drc"; mkdir -p "$OUT"
[ -n "${MAGIC_RUN:-}" ] || { echo "ERROR: source asic/signoff/env.sh (MAGIC_RUN)" >&2; exit 1; }
# The GDS top cell is the INNOVUS DESIGN NAME, not the file basename - loading
# a nonexistent name makes magic silently create an EMPTY cell and DRC passes
# vacuously (found 2026-09-01: two hours of "0 errors" on nothing). Discover
# the top cell from the GDS itself and refuse to run on ambiguity.
cat > "$OUT/drc.tcl" <<EOF
gds read $GDS
set _tops {}
foreach c [cellname list top] { if {\$c ne "(UNNAMED)"} { lappend _tops \$c } }
if {[llength \$_tops] != 1} { puts "TOP_CELL_ERROR: \$_tops"; quit -noprompt }
puts "DRC_TOP_CELL: [lindex \$_tops 0]"
foreach _m [cellname list allcells] {
    if {[string match {sram_1rw1r_32_256_8_sky130*} \$_m]} {
        load \$_m
        select top cell
        delete
        puts "DRC_MACRO_EMPTIED: \$_m"
    }
}
load [lindex \$_tops 0]
select top cell
drc on
drc euclidean on
drc style drc(${ASIC_DRC_STYLE:-routing})
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
grep -q "couldn't be read" "$OUT/magic.log" && { echo "ERROR: magic could not read a cell - vacuous run" >&2; exit 1; }
grep -q "TOP_CELL_ERROR" "$OUT/magic.log" && { echo "ERROR: top cell ambiguous" >&2; exit 1; }
grep 'DRC_TOP_CELL' "$OUT/magic.log"
grep 'Total DRC errors found' "$OUT/magic.log" | tail -1
sort -t: -k2 -rn "$OUT/drc_count.txt" 2>/dev/null | head -15
