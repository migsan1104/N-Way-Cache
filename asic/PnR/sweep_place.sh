#!/usr/bin/env bash
set -uo pipefail
# Placement sweep: measure the TOOL's congestion machinery, which iterations
# 1-11 never touched (they steered congestion with hand-carved blockages
# instead). Methodology and results: asic/PnR/DRC.md, "Methodology: the
# placement sweep".
#
# Each arm runs stages 00-03 only (~2 h) on a FIXED design point -
# e36b' netlist x fp_iter7 - so the ONLY difference between arms is the knob
# set. The control is already measured: the e36b' screen run
# (20260831_e36bpscreen), settled post-place 7,174 hotspot / 12.6% H.
#
# Factorial: cong_effort=high throughout (arm B isolates it vs control),
# then padding and opt-congestion each off/on:
#
#   arm   cong_effort  inst_gap(padding)  extra
#   B     high         -                  -
#   C     high         2                  -
#   D     high         4                  -                 (padding dose-response)
#   E     high         2                  max_density 0.55
#
# NOTE 2026-08-31: the original D/E used setOptMode congestion effort. Innovus
# 21.16 rejects BOTH spellings (-congEffort and -congestionEffort), which the
# catch-wrapper caught and reported in reports/place/cong_knobs.txt - D and E
# had silently become duplicates of B and C. They were killed ~30 min in and
# redefined as above. Lesson: always read cong_knobs.txt before trusting an arm.
#
#   ./sweep_place.sh              # launch all four in parallel tmux sessions
#   ./sweep_place.sh B D          # launch a subset
#
# Compare with:  python3 innovus/scripts/forecast_table.py
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
NETLIST=$HERE/../PPA/genus/assoc_4/runs/20260831_140249_e36bp_ss1v76_d1p5_tb16_sram/netlist/Cache_16384B_assoc4_sram_mapped.v
FP=$HERE/floorplans/fp_iter7.tcl
STAMP_DATE=$(date +%Y%m%d)

arm_env() {   # echoes the env assignments for one arm
    case $1 in
        B) echo "ASIC_PLACE_CONG_EFFORT=high" ;;
        C) echo "ASIC_PLACE_CONG_EFFORT=high ASIC_PLACE_INST_GAP=2" ;;
        D) echo "ASIC_PLACE_CONG_EFFORT=high ASIC_PLACE_INST_GAP=4" ;;
        E) echo "ASIC_PLACE_CONG_EFFORT=high ASIC_PLACE_INST_GAP=2 ASIC_PLACE_MAX_DENSITY=0.55" ;;
        *) echo "" ;;
    esac
}

ARMS=${*:-B C D E}
for A in $ARMS; do
    ENV=$(arm_env "$A")
    [[ -z $ENV ]] && { echo "unknown arm '$A' (use B C D E)" >&2; continue; }
    STAMP=${STAMP_DATE}_sweep${A}_e36bp_fpiter7
    SCRIPT=$(mktemp /tmp/sweep_${A}_XXXX.sh)
    cat > "$SCRIPT" <<EOF
export ASIC_NETLIST=$NETLIST
export ASIC_FLOORPLAN=$FP
export ASIC_PNR_RUN_STAMP=$STAMP
export ASIC_PNR_FROM=00 ASIC_PNR_TO=03
export $ENV
$HERE/run_v3.sh b
echo EXIT=\$? \$(date)
sleep infinity
EOF
    tmux new-session -d -s "sweep$A" "bash $SCRIPT"
    echo "arm $A: stamp $STAMP  env: $ENV"
done
echo
echo "watch:  python3 $HERE/innovus/scripts/forecast_table.py"
