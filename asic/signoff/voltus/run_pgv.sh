#!/usr/bin/env bash
# run_pgv.sh - Voltus PGV generation, techonly then stdcells (voltus.md step 1).
# Logs: pgv/logs/techonly.log, pgv/logs/stdcells.log. First run 2026-09-04.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=/ecel/UFAD/miguel.sanchez1/Cache
source /apps/settings
source $REPO/asic/PnR/innovus/env.sh
source $REPO/asic/signoff/env.sh
mkdir -p $HERE/pgv/logs
cd $HERE/pgv
for step in techonly stdcells; do
  echo "== PGV $step start $(date)"
  voltus -no_gui -files $HERE/pgv_$step.tcl -log logs/$step
  rc=$?
  echo "== PGV $step exit=$rc $(date)"
  grep -aE "VOLTUS_LGEN-3265|Total number of cells|view created|\*\*ERROR" logs/$step.log | tail -6
  [ $rc -eq 0 ] && [ -e $step/${step}.cl -o -d $step ] || { echo "PGV $step FAILED - stopping"; exit 1; }
done
echo PGV_ALL_DONE
