#!/usr/bin/env bash
# run_static_rail.sh <pnr_run_stamp> [ckpt]  - voltus.md step 2 on a routed run.
set -uo pipefail
STAMP="${1:?usage: run_static_rail.sh <run_stamp> [ckpt]}"; CKPT="${2:-06_final.enc}"
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=/ecel/UFAD/miguel.sanchez1/Cache
source /apps/settings
source $REPO/asic/PnR/innovus/env.sh
export SIGNOFF_PNR_STAMP=$STAMP ASIC_PNR_RUN_STAMP=$STAMP VOLTUS_CKPT=$CKPT
export ASIC_SIGNOFF_LIB="${ASIC_SIGNOFF_LIB:-/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_n40C_1v76.lib}"
export ASIC_QRC_TECH="${ASIC_QRC_TECH:-$REPO/asic/signoff/quantus/techfiles/sky130A_nom.tch}"
export ASIC_SRAM_MACRO_DERATE="${ASIC_SRAM_MACRO_DERATE:-1.5}" ASIC_MACRO_DERATE_EARLY="${ASIC_MACRO_DERATE_EARLY:-0.67}"
source $REPO/asic/signoff/env.sh
mkdir -p "$SIGNOFF_RESULTS/voltus"
echo "== VOLTUS static rail: $STAMP / $CKPT  $(date)"
voltus -no_gui -files $HERE/static_rail.tcl -log "$SIGNOFF_RESULTS/voltus/static_rail" < /dev/null
echo "VOLTUS_STATIC_EXIT=$? $(date)"
