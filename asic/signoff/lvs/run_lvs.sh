#!/usr/bin/env bash
set -euo pipefail
# LVS: GDS (magic extract -> spice) vs the P&R netlist, with netgen and the
# PDK's sky130A_setup.tcl.
#
#   bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
#             <repo>/asic/signoff/lvs/run_lvs.sh [gds] [netlist.v]'
#
# The P&R netlist must be the *_pnr.v (with fill/decap - they are in the GDS)
# and the SRAM macros are compared as black boxes (their GDS is the vendor
# cell, their spice is not in the std-cell library). Results in
# $SIGNOFF_RESULTS/lvs/: lvs.out, comp.out.
# DRAFT 2026-08-28 - not yet shaken down (waits on run 1's stage 09 GDS).
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDS="${1:-$(ls "$SIGNOFF_PNR_DIR"/outputs/*.gds 2>/dev/null | head -1)}"
NET="${2:-$(ls "$SIGNOFF_PNR_DIR"/outputs/*_pnr.v 2>/dev/null | grep -v _sim | head -1)}"
[ -r "${GDS:-}" ] && [ -r "${NET:-}" ] || { echo "ERROR: need GDS and *_pnr.v (run stage 09)" >&2; exit 1; }
command -v netgen >/dev/null || { echo "ERROR: netgen not installed - see lvs/lvs.md" >&2; exit 1; }
OUT="$SIGNOFF_RESULTS/lvs"; mkdir -p "$OUT"
TOP=$(basename "$GDS" .gds)
STD_SPICE=$STDCELL_ROOT/spice/sky130_fd_sc_hd.spice
MACRO_SPICE=$PDK_ROOT_SKY130/libs.ref/sky130_sram_macros/spice/sky130_sram_1kbyte_1rw1r_32x256_8.spice

cat > "$OUT/extract.tcl" <<EOF
gds read $GDS
load $TOP
select top cell
extract no all
extract do local
extract unique
extract
ext2spice lvs
ext2spice -o $OUT/$TOP.gds.spice
quit -noprompt
EOF
echo "magic extract: $GDS"
$MAGIC_RUN -dnull -noconsole -rcfile "$SKY130_MAGICRC" "$OUT/extract.tcl" > "$OUT/magic_extract.log" 2>&1 || { tail -20 "$OUT/magic_extract.log"; exit 1; }

# Schematic side: P&R verilog + std-cell spice (+ macro spice if present)
SCH="$OUT/schematic.spice"
{ cat "$STD_SPICE"; [ -r "$MACRO_SPICE" ] && cat "$MACRO_SPICE"; } > "$SCH"
echo "netgen LVS: layout $OUT/$TOP.gds.spice vs $NET"
netgen -batch lvs "$OUT/$TOP.gds.spice $TOP" "$NET $TOP" "$SKY130_NETGEN_SETUP" "$OUT/comp.out" -json > "$OUT/lvs.out" 2>&1 || true
grep -E 'Circuits match|do not match|Netlists|uniquely|Final result' "$OUT/lvs.out" "$OUT/comp.out" | tail -6
