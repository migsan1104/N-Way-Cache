#!/usr/bin/env bash
# run_two_corner.sh <pnr_run_stamp> [corner:macro_derate ...]
#
# Tempus on an exported P&R package at several std-cell corners, one after
# the other, each in its own results dir (tempus_<corner>/ via
# SIGNOFF_TEMPUS_TAG in sta.tcl). Needs only outputs/ (netlist, SPEF,
# as-implemented SDC) so it can run while KLayout/LVS are still going.
# Written 2026-09-04 for iter16b: the winner chain runs Tempus once, at
# ASIC_SIGNOFF_LIB, and only after LVS; the corner audit (DRC.md 09-03)
# wants both the campaign corner and the corner the DB was built at.
#
# Default corners: ss_n40C_1v76 x1.5 (campaign corner, MACROS.md run 2) and
# ss_100C_1v60 x1.5 (iter16b's own P&R corner - comparable with Innovus).
# Add ss_100C_1v60:2.0 for the MACROS.md 08-20 pairing if wanted.
#
# If outputs/ is not complete yet, waits for the export stage to finish
# (polls logs/chain_export.log for "stage 06 (export) complete").
set -uo pipefail
STAMP="${1:?usage: run_two_corner.sh <run_stamp> [corner:derate ...]}"; shift
CORNERS=("$@"); [ ${#CORNERS[@]} -gt 0 ] || CORNERS=(ss_n40C_1v76:1.5 ss_100C_1v60:1.5)
REPO=/ecel/UFAD/miguel.sanchez1/Cache
RUN=$REPO/asic/PnR/innovus/runs/$STAMP
PDK=/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref
[ -d "$RUN" ] || { echo "no run dir $RUN"; exit 1; }
source /apps/settings
source $REPO/asic/PnR/innovus/env.sh
export ASIC_PNR_RUN_STAMP=$STAMP
export ASIC_QRC_TECH="${ASIC_QRC_TECH:-$REPO/asic/signoff/quantus/techfiles/sky130A_nom.tch}"
export ASIC_MACRO_DERATE_EARLY="${ASIC_MACRO_DERATE_EARLY:-0.67}"
export SIGNOFF_PNR_STAMP=$STAMP
source $REPO/asic/signoff/env.sh

# Wait for the export to land. 06_final.enc is the last thing 06_export.tcl
# writes (after the GDS), so its presence + the SPEF = package complete.
# (pnr_note output goes to stdout, not the innovus -log file - do not grep
# chain_export.log for the "stage 06 complete" marker; found 2026-09-04.)
until [ -n "$(ls "$RUN"/outputs/*_pnr.spef 2>/dev/null)" ] && [ -f "$RUN/checkpoints/06_final.enc" ]; do
  echo "$(date +%H:%M:%S) waiting for export of $STAMP ..."; sleep 120
done
NET=$(ls "$RUN"/outputs/*_pnr.v | head -1); SPEF=$(ls "$RUN"/outputs/*_pnr.spef | head -1)
echo "package: $NET / $SPEF"

for spec in "${CORNERS[@]}"; do
  corner=${spec%%:*}; derate=${spec#*:}; [ "$derate" = "$spec" ] && derate=1.5
  lib=$PDK/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__${corner}.lib
  [ -r "$lib" ] || { echo "SKIP $corner: lib not readable $lib"; continue; }
  tag="${corner}_d${derate}${SIGNOFF_PERIOD:+_p$SIGNOFF_PERIOD}"
  export ASIC_SIGNOFF_LIB=$lib ASIC_SRAM_MACRO_DERATE=$derate SIGNOFF_TEMPUS_TAG=$tag
  out=$SIGNOFF_RESULTS/tempus_$tag; mkdir -p "$out"
  echo "== TEMPUS corner=$corner macro_derate=x$derate -> $out  ($(date))"
  ( cd $REPO/asic/signoff/tempus && tempus -no_gui -files sta.tcl -log "$out/tempus" )
  echo "TEMPUS $tag exit=$?"
  grep -aE "WNS|TNS|Setup|Hold" "$out/summary.rpt" 2>/dev/null | head -12
done
echo TWO_CORNER_DONE
