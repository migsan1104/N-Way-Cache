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
# top = the one module that is neither a std-cell stub nor the SRAM macro (the
# -includePhysicalInst netlist lists 226 leaf stubs first; picking the first
# module extracted a lone diode_2 on 2026-09-05)
TOP=$(grep -oE '^module +[A-Za-z_0-9]+' "$NET" | awk '{print $2}' | grep -vE '^(sky130_|sram_)' | tail -1)
[ -n "$TOP" ] || { echo "ERROR: no module name in $NET" >&2; exit 1; }
echo "top cell: $TOP (macros black-boxed)"

# Top-level pin labels: the streamOut GDS carries no pin text (2026-09-05),
# so netgen failed "Top level cell failed pin matching" with an empty port
# list. Rebuild them from the DEF PINS section (def_pins_to_magic.py).
DEF=$(ls "$(dirname "$GDS")"/*_pnr.def 2>/dev/null | head -1)
[ -r "${DEF:-}" ] || { echo "ERROR: no *_pnr.def next to $GDS (needed for pin labels)" >&2; exit 1; }
python3 "$HERE/def_pins_to_magic.py" "$DEF" > "$OUT/pins.tcl" || { echo "ERROR: def_pins_to_magic failed" >&2; exit 1; }
echo "pin labels from DEF: $(grep -c '^label' "$OUT/pins.tcl")"
# Macro black-boxing (2026-09-06, lvs.md run 3): `lef read` + `gds
# noduplicates true` did NOT keep the LEF abstract - the extracted macro had
# 918 ports and the OpenRAM internals, whose extraction shorts vdd/gnd/signals
# and merged VPWR+VGND+17 top pins into one node. Rewrite the GDS first so the
# macro cell holds only LEF pin rects + port labels (blackbox_macros_gds.py,
# KLayout, ~3 min); ASIC_LVS_BB_GDS=0 falls back to the old lef-read path.
READ_GDS=$GDS; LEF_READ="lef read $MACRO_LEF"; BB_ABSTRACT="# (lef-read path: cell is already an abstract view)"
if [ "${ASIC_LVS_BB_GDS:-1}" = "1" ]; then
  READ_GDS="$OUT/$(basename "${GDS%.gds}")_bb.gds"
  klayout -b -r "$HERE/blackbox_macros_gds.py" -rd IN="$GDS" -rd LEF="$MACRO_LEF" -rd OUT="$READ_GDS" > "$OUT/blackbox_gds.log" 2>&1 \
    || { tail -5 "$OUT/blackbox_gds.log"; echo "ERROR: blackbox_macros_gds failed" >&2; exit 1; }
  grep -E '^LEF|^macro' "$OUT/blackbox_gds.log"
  LEF_READ="# macro abstract already in the GDS (blackbox_macros_gds.py)"
  # magic flattens a device-less cell into its parent (run 4, 2026-09-06: the
  # 16 macro instances vanished from the spice). Flag the cell as an abstract
  # view and `ext2spice blackbox on` writes it as an empty .subckt + X calls
  # (verified on a scratch cell, magic 8.3.509).
  MACRO_NAME=$(grep -m1 -oE '^MACRO +\S+' "$MACRO_LEF" | awk '{print $2}')
  BB_ABSTRACT="load $MACRO_NAME
property LEFview TRUE"
fi
cat > "$OUT/extract.tcl" <<EOT
$LEF_READ
gds noduplicates true
gds read $READ_GDS
$BB_ABSTRACT
load $TOP
select top cell
if {[box values] eq "0 0 0 0"} { puts "TOP_CELL_ERROR: $TOP is empty"; quit -noprompt }
source $OUT/pins.tcl
extract no all
extract do local
extract unique
extract
ext2spice lvs
ext2spice blackbox on
ext2spice -o $OUT/$TOP.gds.spice
quit -noprompt
EOT
if [ "${ASIC_LVS_NETGEN_ONLY:-0}" = "1" ] && [ -s "$OUT/$TOP.gds.spice" ]; then
  echo "magic extract skipped (ASIC_LVS_NETGEN_ONLY=1, reusing $OUT/$TOP.gds.spice)"
else
echo "magic extract (bb): $READ_GDS"
$MAGIC_RUN -dnull -noconsole -rcfile "$SKY130_MAGICRC" "$OUT/extract.tcl" > "$OUT/magic_extract.log" 2>&1 || { tail -20 "$OUT/magic_extract.log"; exit 1; }
grep -qE "couldn't be read|TOP_CELL_ERROR" "$OUT/magic_extract.log" && { echo "ERROR: missing/empty cell" >&2; exit 1; }
[ -s "$OUT/$TOP.gds.spice" ] || { echo "ERROR: no spice produced" >&2; exit 1; }
fi
# probe_p_8: met5 probe pad extracted as a res_generic_m5 device -> 7-port
# cell with the routed net on the buffer output node (run 5, 2026-09-06)
python3 "$HERE/fix_probe_pad.py" "$OUT/$TOP.gds.spice"
# Sanity: the macro subckt must now be (near-)empty in the layout spice.
MD=$(awk '/^\.subckt sram_1rw1r_32_256_8_sky130/,/^\.ends/' "$OUT/$TOP.gds.spice" | grep -cE '^[MXCR]' || true)
echo "macro subckt device count in layout spice: $MD (expect ~0)"
echo "netgen LVS (bb): layout vs $NET"
# netgen_setup_bb.tcl = PDK setup + ignore device-less fill/tap cells that the
# -includePhysicalInst netlist lists but magic drops (2026-09-05).
netgen -batch lvs "$OUT/$TOP.gds.spice $TOP" "$NET $TOP" "$HERE/netgen_setup_bb.tcl" "$OUT/comp.out" -json > "$OUT/lvs.out" 2>&1 || true
grep -E 'Circuits match|do not match|uniquely|Final result' "$OUT/lvs.out" "$OUT/comp.out" 2>/dev/null | tail -6
