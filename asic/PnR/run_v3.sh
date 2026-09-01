#!/usr/bin/env bash
# NOT set -e yet: /apps/settings returns nonzero internally and set -e makes
# the script die there, silently (found 2026-08-30). -e goes on after sourcing.
set -uo pipefail
# Launch a v3 floorplan candidate through stages 00-03 (init -> floorplan ->
# power -> place_opt_design) and stop for the preCTS comparison
# (FLOORPLAN.md "How the choice is made").
#
#   ./run_v3.sh a|b [extra ASIC_* env]
#
# Corner-2 configuration per FLOORPLAN.md "Flow changes that go with v3":
# ss_n40C_1v76 cells, vendor macro x1.5 late / x0.67 early, netlist from the
# 20260828_151051 corner-2 Genus run. Each candidate gets its own
# ASIC_PNR_RUN_STAMP so nothing touches the preserved run-1 tree.
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CAND=${1:?usage: run_v3.sh a|b}
case $CAND in a|b) ;; *) echo "candidate must be a or b" >&2; exit 1;; esac

# Capture caller overrides BEFORE env.sh, which exports its own run-1
# ASIC_NETLIST unconditionally and would clobber them (bit G7d 2026-08-31:
# the pre-set e36b netlist lost to env.sh's 20260825 default).
_PRESET_NETLIST=${ASIC_NETLIST:-}
_PRESET_FLOORPLAN=${ASIC_FLOORPLAN:-}
source /apps/settings
source "$HERE/innovus/env.sh"     # pins LEF, GDS map, core margin ...
set -e
PDK=/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref
# corner 2 overrides (run-1 pins in env.sh stay for anything not set here)
export ASIC_NETLIST=${_PRESET_NETLIST:-$HERE/../PPA/genus/assoc_4/runs/20260828_151051_e35abcde_ss1v76_d1p5_tb16_sram/netlist/Cache_16384B_assoc4_sram_mapped.v}   # caller pre-set wins over env.sh (G7d+)
export ASIC_SIGNOFF_LIB=$PDK/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_n40C_1v76.lib
export ASIC_SRAM_MACRO_DERATE=1.5
export ASIC_MACRO_DERATE_EARLY=0.67
export ASIC_FLOORPLAN=${_PRESET_FLOORPLAN:-$HERE/floorplans/fp_v3${CAND}.tcl}   # caller pre-set wins (G7+)
export ASIC_CPUS=16
export ASIC_PNR_RUN_STAMP=${ASIC_PNR_RUN_STAMP:-$(date +%Y%m%d_%H%M%S)_v3${CAND}_e35abcde_ss1v76_d1p5}
# Default = the phase-1 race slice (00-03). To continue a finished candidate,
# set ASIC_PNR_RUN_STAMP to its stamp and ASIC_PNR_FROM/TO (e.g. 04 / 06).
export ASIC_PNR_FROM=${ASIC_PNR_FROM:-00} ASIC_PNR_TO=${ASIC_PNR_TO:-03}

echo "v3-$CAND: stamp $ASIC_PNR_RUN_STAMP  floorplan $ASIC_FLOORPLAN"
mkdir -p "$HERE/innovus/runs/$ASIC_PNR_RUN_STAMP/logs"
cd "$HERE/innovus/runs/$ASIC_PNR_RUN_STAMP"
exec innovus -no_gui -files "$HERE/innovus/scripts/run_innovus.tcl" \
     -log "logs/innovus_v3${CAND}"
