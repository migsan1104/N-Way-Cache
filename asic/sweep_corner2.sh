#!/usr/bin/env bash
set -uo pipefail
# 16 KB five-way Genus sweep at the SIGNOFF recipe (2026-09-11): the settings the
# iter26b P&R netlist was synthesised with, applied to every associativity.
#   cells ss_n40C_1v76, tag banks 16 deep, no cap blanket (library per-pin
#   limits), fanout rule 32, replicas free to merge, 3.500 ns target, FLOP data
#   banks for every ASSOC (the SRAM-macro branch exists only for the 256x32
#   geometry = 16 KB ASSOC=4; that row is runs/20260908_e37_nocap_fo32_*_sram).
# Usage:  bash -lc 'source /apps/settings && ./sweep_corner2.sh [-j N] [-a "1 2 4 8 16"]'
# Logs:   PPA/sweep_logs/corner2_<stamp>.log (+ per-assoc); marker SWEEP_CORNER2_DONE.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PDK=/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref
JOBS=5; ASSOCS="1 2 4 8 16"
while getopts ":j:a:" o; do case $o in j) JOBS=$OPTARG;; a) ASSOCS=$OPTARG;; esac; done
command -v genus >/dev/null || { echo "genus not on PATH (source /apps/settings)"; exit 1; }
STAMP=$(date +%Y%m%d_%H%M%S)
export ASIC_SIGNOFF_LIB=$PDK/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_n40C_1v76.lib
export ASIC_SRAM_MACRO=0 ASIC_SRAM_MACRO_DERATE=1.5
export ASIC_HDL_DEFINES="TAG_BANK_DEPTH=16" ASIC_KEEP_REPLICAS=0
export ASIC_MAX_CAP=none ASIC_MAX_FANOUT=32 ASIC_CACHE_BYTES=16384
export ASIC_RUN_STAMP="${STAMP}_e37_nocap_fo32_ss1v76_tb16_flops"
LOGD=$SCRIPT_DIR/PPA/sweep_logs; mkdir -p "$LOGD"; SUM=$LOGD/corner2_$STAMP.log
echo "corner-2 sweep $STAMP: assoc [$ASSOCS] jobs $JOBS stamp $ASIC_RUN_STAMP" | tee -a "$SUM"
run_one() { local a=$1 t0=$(date +%s)
  if "$SCRIPT_DIR/run_genus.sh" "$a" 3.500 > "$LOGD/corner2_${STAMP}_assoc$a.log" 2>&1
  then echo "assoc=$a PASS ($(( ($(date +%s)-t0)/60 )) min) $(date +%H:%M)" | tee -a "$SUM"
  else echo "assoc=$a FAIL ($(( ($(date +%s)-t0)/60 )) min) see corner2_${STAMP}_assoc$a.log" | tee -a "$SUM"; fi; }
for a in $ASSOCS; do run_one "$a" & sleep 20
  while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n 2>/dev/null || sleep 5; done; done
wait
"$SCRIPT_DIR/collect_ppa.py" --tool genus 2>&1 | tee -a "$SUM" || /apps/anaconda/bin/python "$SCRIPT_DIR/collect_ppa.py" --tool genus | tee -a "$SUM"
echo "SWEEP_CORNER2_DONE $(date +%H:%M)" | tee -a "$SUM"
