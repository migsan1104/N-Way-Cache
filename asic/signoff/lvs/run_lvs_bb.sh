#!/usr/bin/env bash
set -euo pipefail
# LVS with the SRAM macros BLACK-BOXED on both sides (2026-09-02, lvs.md):
# the flat run flattened 16 x ~75k macro devices into the compare because the
# schematic (P&R verilog) has no macro definition - netgen ground for 15+ h.
# Trick: "lef read" the rebadged macro LEF FIRST, then "gds noduplicates
# true" so gds read keeps the abstract (ports, no internals). Extract then
# emits an empty macro subckt; netgen matches blackbox-to-blackbox by ports.
# Macro internals are the vendor's problem (their GDS is golden).
#
#   bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
#             <repo>/asic/signoff/lvs/run_lvs_bb.sh [gds] [netlist.v]'
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDS="${1:-$(ls "$SIGNOFF_PNR_DIR"/outputs/*.gds 2>/dev/null | head -1)}"
# Prefer the LVS netlist (PG pins + physical instances, 06_export netlist-lvs);
# the plain _pnr.v has no power pins and cannot match (2026-09-05, lvs.md).
NET="${2:-$(ls "$SIGNOFF_PNR_DIR"/outputs/*_pnr_lvs.v "$SIGNOFF_PNR_DIR"/outputs/*_pnr.v 2>/dev/null | grep -v _sim | head -1)}"
[ -r "${GDS:-}" ] && [ -r "${NET:-}" ] || { echo "ERROR: need GDS and *_pnr.v" >&2; exit 1; }
command -v netgen >/dev/null || { echo "ERROR: netgen not installed - see lvs/lvs.md" >&2; exit 1; }
OUT="$SIGNOFF_RESULTS/lvs_bb"; mkdir -p "$OUT"
MACRO_LEF=$REPO_ROOT/asic/PnR/innovus/lef/sram_1rw1r_32_256_8_sky130.lef
[ -r "$MACRO_LEF" ] || { echo "ERROR: rebadged macro LEF not found" >&2; exit 1; }
TOP=$(grep -m1 -oE '^module +[A-Za-z_0-9]+' "$NET" | awk '{print $2}')
[ -n "$TOP" ] || { echo "ERROR: no module name in $NET" >&2; exit 1; }
echo "top cell: $TOP (macros black-boxed)"

cat > "$OUT/extract.tcl" <<EOT
lef read $MACRO_LEF
gds noduplicates true
gds read $GDS
load $TOP
select top cell
if {[box values] eq "0 0 0 0"} { puts "TOP_CELL_ERROR: $TOP is empty"; quit -noprompt }
extract no all
extract do local
extract unique
extract
ext2spice lvs
ext2spice -o $OUT/$TOP.gds.spice
quit -noprompt
EOT
echo "magic extract (bb): $GDS"
$MAGIC_RUN -dnull -noconsole -rcfile "$SKY130_MAGICRC" "$OUT/extract.tcl" > "$OUT/magic_extract.log" 2>&1 || { tail -20 "$OUT/magic_extract.log"; exit 1; }
grep -qE "couldn't be read|TOP_CELL_ERROR" "$OUT/magic_extract.log" && { echo "ERROR: missing/empty cell" >&2; exit 1; }
[ -s "$OUT/$TOP.gds.spice" ] || { echo "ERROR: no spice produced" >&2; exit 1; }
# Sanity: the macro subckt must now be (near-)empty in the layout spice.
MD=$(awk '/^\.subckt sram_1rw1r_32_256_8_sky130/,/^\.ends/' "$OUT/$TOP.gds.spice" | grep -cE '^[MXCR]' || true)
echo "macro subckt device count in layout spice: $MD (expect ~0)"
echo "netgen LVS (bb): layout vs $NET"
netgen -batch lvs "$OUT/$TOP.gds.spice $TOP" "$NET $TOP" "$SKY130_NETGEN_SETUP" "$OUT/comp.out" -json > "$OUT/lvs.out" 2>&1 || true
grep -E 'Circuits match|do not match|uniquely|Final result' "$OUT/lvs.out" "$OUT/comp.out" 2>/dev/null | tail -6
