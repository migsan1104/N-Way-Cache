#!/usr/bin/env bash
set -euo pipefail
# Run-2 sign-off corner for Genus (decided 2026-08-28, rationale in MACROS.md
# "Run 2 corner"): cells at ss_n40C_1v76 - the SS standard-cell lib closest to
# the vendored macro's own 1.8 V / SS characterization - with the SAME vendor
# macro lib and a x1.5 late derate that is a pure guardband (in-house OpenRAM
# calibration / vendor lib at the operating load), not a V/T translation.
#
# Run 1 (ss_100C_1v60 + x2.0) stays the default of run_genus.sh; nothing here
# touches the P&R tree, which is pinned to its own netlist in PnR/innovus/env.sh.
#
# Usage:  ./run_genus_corner2.sh [ASSOC] [period]      (same as run_genus.sh)
#         ASIC_STOP_AFTER_SETUP=1 ./run_genus_corner2.sh 4   # checks only
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PDK=/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref

export ASIC_SIGNOFF_LIB="${ASIC_SIGNOFF_LIB:-$PDK/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_n40C_1v76.lib}"
export ASIC_SRAM_MACRO="${ASIC_SRAM_MACRO:-1}"
export ASIC_SRAM_MACRO_DERATE="${ASIC_SRAM_MACRO_DERATE:-1.5}"
export ASIC_HDL_DEFINES="${ASIC_HDL_DEFINES:-TAG_BANK_DEPTH=16}"
export ASIC_KEEP_REPLICAS="${ASIC_KEEP_REPLICAS:-0}"
export ASIC_RUN_STAMP="${ASIC_RUN_STAMP:-$(date +%Y%m%d_%H%M%S)_e35abcde_ss1v76_d1p5_tb16_sram}"

[[ -r "$ASIC_SIGNOFF_LIB" ]] || { echo "ERROR: signoff lib not readable: $ASIC_SIGNOFF_LIB" >&2; exit 1; }
echo "Corner-2 run: cells $(basename "$ASIC_SIGNOFF_LIB"), macro derate x$ASIC_SRAM_MACRO_DERATE, stamp $ASIC_RUN_STAMP"
exec "$SCRIPT_DIR/run_genus.sh" "$@"
