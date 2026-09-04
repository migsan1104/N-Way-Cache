#!/usr/bin/env bash
# run_si_pass.sh <stamp> [corner:derate ...] - SI-aware Tempus at each corner
# into tempus_<corner>_d<derate>_si/. Separate from run_two_corner.sh only so
# it could be added while that launcher was executing (never edit a running
# .sh). Same env, same sta.tcl; adds SIGNOFF_SI=1. 2026-09-04.
set -uo pipefail
STAMP="${1:?usage: run_si_pass.sh <run_stamp> [corner:derate ...]}"; shift
CORNERS=("$@"); [ ${#CORNERS[@]} -gt 0 ] || CORNERS=(ss_n40C_1v76:1.5 ss_100C_1v60:1.5)
REPO=/ecel/UFAD/miguel.sanchez1/Cache
PDK=/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref
source /apps/settings
source $REPO/asic/PnR/innovus/env.sh
export ASIC_PNR_RUN_STAMP=$STAMP SIGNOFF_PNR_STAMP=$STAMP SIGNOFF_SI=1
export ASIC_QRC_TECH="${ASIC_QRC_TECH:-$REPO/asic/signoff/quantus/techfiles/sky130A_nom.tch}"
export ASIC_MACRO_DERATE_EARLY="${ASIC_MACRO_DERATE_EARLY:-0.67}"
source $REPO/asic/signoff/env.sh
for spec in "${CORNERS[@]}"; do
  corner=${spec%%:*}; derate=${spec#*:}; [ "$derate" = "$spec" ] && derate=1.5
  lib=$PDK/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__${corner}.lib
  tag="${corner}_d${derate}_si"
  export ASIC_SIGNOFF_LIB=$lib ASIC_SRAM_MACRO_DERATE=$derate SIGNOFF_TEMPUS_TAG=$tag
  out=$SIGNOFF_RESULTS/tempus_$tag; mkdir -p "$out"
  echo "== TEMPUS-SI corner=$corner macro_derate=x$derate -> $out  ($(date))"
  ( cd $REPO/asic/signoff/tempus && tempus -no_gui -files sta.tcl -log "$out/tempus" < /dev/null )
  echo "TEMPUS-SI $tag exit=$?"
done
echo SI_PASS_DONE
