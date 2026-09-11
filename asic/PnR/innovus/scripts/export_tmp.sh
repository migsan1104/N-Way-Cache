#!/usr/bin/env bash
# export_tmp.sh <base_stamp> <src.enc> <suffix>  (2026-09-10): export <src.enc> of runs/<base> into runs/<base>_<suffix>/outputs
# via symlinked checkpoints, so Voltus/Tempus can read it while the base run's outputs/ is owned by a signoff chain.
set -uo pipefail
BASE=${1:?base}; SRC=${2:?src.enc}; SUF=${3:?suffix}; INV=/ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus; SCR=/ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts
NEW=${BASE}_${SUF}; R=$INV/runs/$NEW
mkdir -p $R/checkpoints $R/logs $R/outputs $R/reports
ln -sfn $INV/runs/$BASE/checkpoints/$SRC $R/checkpoints/$SRC; ln -sfn $INV/runs/$BASE/checkpoints/$SRC.dat $R/checkpoints/$SRC.dat
source /apps/settings; source $INV/env.sh
eval "$(grep -E '^export ASIC_' $INV/runs/$BASE/launch.sh | grep -v ASIC_PNR_RUN_STAMP)"
export ASIC_PNR_RUN_STAMP=$NEW ASIC_ANTENNA_SRC=$SRC ASIC_QRC_TECH=${ASIC_QRC_TECH:-/ecel/UFAD/miguel.sanchez1/Cache/asic/signoff/quantus/techfiles/sky130A_nom.tch}
echo "== EXPORT_TMP $NEW <- $SRC $(date)"
( cd $R && innovus -no_gui -files <(echo "source $SCR/innovus_config.tcl
pnr_restore_stage $SRC
source $SCR/06_export.tcl
exit") -log logs/export_tmp )
ls $R/outputs/*_pnr.v >/dev/null 2>&1 && echo "EXPORT_TMP_DONE=$NEW $(date)" || echo "EXPORT_TMP_FAILED=$NEW $(date)"
