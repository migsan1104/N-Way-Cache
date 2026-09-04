#!/usr/bin/env bash
# antenna_then_chain.sh <stamp> - overnight 2026-09-04: diode fix in a fresh
# Innovus session (antenna_fix2.tcl), then winner_chain.sh from the fixed
# checkpoint ONLY if the fix left verify_drc = 0 and antenna = 0.
set -uo pipefail
STAMP="${1:?usage: antenna_then_chain.sh <run_stamp>}"
REPO=/ecel/UFAD/miguel.sanchez1/Cache
RUN=$REPO/asic/PnR/innovus/runs/$STAMP
SCR=$REPO/asic/PnR/innovus/scripts
source /apps/settings
source $REPO/asic/PnR/innovus/env.sh
export ASIC_PNR_RUN_STAMP="$STAMP"
export ASIC_QRC_TECH="${ASIC_QRC_TECH:-$REPO/asic/signoff/quantus/techfiles/sky130A_nom.tch}"
export ASIC_SRAM_MACRO_DERATE="${ASIC_SRAM_MACRO_DERATE:-1.5}"
export ASIC_MACRO_DERATE_EARLY="${ASIC_MACRO_DERATE_EARLY:-0.67}"
echo "== ANTENNA FIX2 (innovus) =="
( cd "$RUN" && innovus -no_gui -files $SCR/antenna_fix2.tcl -log logs/antenna_fix2 )
rc=$?
grep -a 'ANTENNA FIX2' "$RUN/logs/antenna_fix2.log" | tail -2
[ $rc -eq 0 ] || { echo "ANTENNA FIX2 not clean (rc=$rc) - chain NOT launched"; exit 2; }
echo "== CHAIN from 05_antenna_fixed.enc =="
ASIC_CHAIN_SRC=05_antenna_fixed.enc exec $SCR/winner_chain.sh "$STAMP"
