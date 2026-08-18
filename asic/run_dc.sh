#!/usr/bin/env bash
set -euo pipefail

# Synopsys Design Compiler logical synthesis for one cache configuration.
#
# Usage:
#   ./run_dc.sh                 # defaults to ASSOC=8
#   ./run_dc.sh 4               # ASSOC=4
#   ./run_dc.sh 4 2.500         # ASSOC=4 at a 2.500 ns target
#
# Results land in asic/PPA/dc/assoc_<N>/{reports,netlist,work,logs}.
# dc_shell runs with its working directory inside work/, so command.log,
# default.svf and the alib-* cache stay inside that run's folder instead of
# scattering into the repository root.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
SYNTH_DIR="$SCRIPT_DIR/synthesis"
COMMON_DIR="$SYNTH_DIR/common"
SYNOPSYS_DIR="$SYNTH_DIR/synopsys"

DC_TCL="$SYNOPSYS_DIR/scripts/run_dc.tcl"
PROJECT_CONFIG="$COMMON_DIR/scripts/project_config.tcl"
RTL_FILELIST="$COMMON_DIR/filelists/rtl_files.tcl"
GOLDEN_SDC="$COMMON_DIR/constraints/golden.sdc"

export ASIC_FLOW=dc
export ASIC_ASSOC="${1:-${ASIC_ASSOC:-8}}"
export ASIC_CLOCK_PERIOD_NS="${2:-${ASIC_CLOCK_PERIOD_NS:-3.500}}"
export ASIC_STOP_AFTER_SETUP="${ASIC_STOP_AFTER_SETUP:-0}"
export ASIC_CACHE_BYTES="${ASIC_CACHE_BYTES:-4096}"

case "$ASIC_ASSOC" in
    1|2|4|8|16) ;;
    *)
        echo "ERROR: invalid associativity '$ASIC_ASSOC' (expected 1, 2, 4, 8, or 16)" >&2
        exit 1
        ;;
esac

ASIC_RUN_STAMP="${ASIC_RUN_STAMP:-$(date +%Y%m%d_%H%M%S)}"
export ASIC_RUN_STAMP

RUN_DIR="$SCRIPT_DIR/PPA/dc/assoc_$ASIC_ASSOC"
RUNS_ROOT="$RUN_DIR/runs"
OUT_DIR="$RUNS_ROOT/$ASIC_RUN_STAMP"
LOG_DIR="$OUT_DIR/logs"
REPORT_DIR="$OUT_DIR/reports"
NETLIST_DIR="$OUT_DIR/netlist"
DB_DIR="$OUT_DIR/db"
WORK_DIR="$OUT_DIR/work"

SKY130_LIB_DIR="$SCRIPT_DIR/libraries/sky130_fd_sc_hd"
SKY130_DB_DIR="$SKY130_LIB_DIR/db"
PDK_LIB_DIR="/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib"
# Setup signoff corner: slow process, 1.60 V (1.8 V nominal minus ~10% droop),
# 100 C. Same library the Genus flow uses. Single corner - all mapping and all
# reported numbers come from it.
DEFAULT_DC_TARGET_LIB="$SKY130_DB_DIR/sky130_fd_sc_hd__ss_100C_1v60.db"
SKY130_LIBERTY="${SKY130_LIBERTY:-$PDK_LIB_DIR/sky130_fd_sc_hd__ss_100C_1v60.lib}"
SKY130_DB_BUILD_TCL="$SKY130_LIB_DIR/build_db.tcl"
SKY130_DB_BUILD_LOG="$SKY130_LIB_DIR/build_db.log"

if [[ -n "${DC_SETUP_SCRIPT:-}" ]]; then
    if [[ ! -f "$DC_SETUP_SCRIPT" ]]; then
        echo "ERROR: DC_SETUP_SCRIPT does not exist: $DC_SETUP_SCRIPT" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$DC_SETUP_SCRIPT"
fi

if [[ -n "${DC_MODULE:-}" ]]; then
    if command -v module >/dev/null 2>&1; then
        module load "$DC_MODULE"
    else
        echo "ERROR: DC_MODULE was set but the module command is unavailable." >&2
        exit 1
    fi
fi

DC_TARGET_LIB="${DC_TARGET_LIB:-$DEFAULT_DC_TARGET_LIB}"
export DC_TARGET_LIB

# Build the Synopsys .db from the installed Liberty file the first time it is needed.
if [[ ! -f "$DC_TARGET_LIB" ]]; then
    if [[ "$DC_TARGET_LIB" != "$DEFAULT_DC_TARGET_LIB" ]]; then
        echo "ERROR: DC_TARGET_LIB does not exist: $DC_TARGET_LIB" >&2
        exit 1
    fi

    echo "SKY130 Synopsys .db library is missing; building it now."
    if [[ ! -f "$SKY130_LIBERTY" ]]; then
        echo "ERROR: SKY130 Liberty file does not exist: $SKY130_LIBERTY" >&2
        exit 1
    fi
    if [[ ! -f "$SKY130_DB_BUILD_TCL" ]]; then
        echo "ERROR: Library Compiler Tcl script does not exist: $SKY130_DB_BUILD_TCL" >&2
        exit 1
    fi
    if ! command -v lc_shell >/dev/null 2>&1; then
        echo "ERROR: lc_shell was not found in PATH." >&2
        echo "Run 'source /apps/settings' before launching." >&2
        exit 1
    fi

    if [[ -z "${LD_PRELOAD:-}" && -f /lib64/libz.so.1 ]]; then
        export LD_PRELOAD=/lib64/libz.so.1
    fi

    mkdir -p "$SKY130_DB_DIR"
    export SKY130_LIBERTY
    export SKY130_DB_OUTPUT="$DEFAULT_DC_TARGET_LIB"

    echo "Liberty file: $SKY130_LIBERTY"
    echo "Output .db  : $SKY130_DB_OUTPUT"
    echo "Log file    : $SKY130_DB_BUILD_LOG"
    echo

    # lc_shell also drops a command log where it runs; keep that with the library.
    set +e
    ( cd "$SKY130_LIB_DIR" && lc_shell -f "$SKY130_DB_BUILD_TCL" ) 2>&1 | tee "$SKY130_DB_BUILD_LOG"
    lc_status=${PIPESTATUS[0]}
    set -e

    if (( lc_status != 0 )); then
        echo "ERROR: lc_shell failed with status $lc_status" >&2
        exit "$lc_status"
    fi
fi

if [[ ! -s "$DC_TARGET_LIB" ]]; then
    echo "ERROR: DC_TARGET_LIB is missing or empty: $DC_TARGET_LIB" >&2
    exit 1
fi

case "$DC_TARGET_LIB" in
    *.db) ;;
    *.lib)
        echo "ERROR: DC_TARGET_LIB points to a Liberty .lib file, but Design Compiler requires a compiled Synopsys .db target library." >&2
        exit 1
        ;;
    *)
        echo "ERROR: DC_TARGET_LIB should point to a Synopsys .db file: $DC_TARGET_LIB" >&2
        exit 1
        ;;
esac

for f in "$DC_TCL:Design Compiler Tcl script" \
         "$PROJECT_CONFIG:shared project configuration" \
         "$RTL_FILELIST:shared RTL filelist" \
         "$GOLDEN_SDC:golden SDC"; do
    path="${f%%:*}"; label="${f#*:}"
    if [[ ! -f "$path" ]]; then
        echo "ERROR: $label does not exist: $path" >&2
        exit 1
    fi
done

if command -v dc_shell >/dev/null 2>&1; then
    DC_EXE=$(command -v dc_shell)
else
    echo "ERROR: dc_shell was not found in PATH." >&2
    echo "Run 'source /apps/settings' before launching." >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$REPORT_DIR" "$NETLIST_DIR" "$DB_DIR" "$WORK_DIR"

LOG_FILE="$LOG_DIR/dc_${ASIC_RUN_STAMP}.log"
LATEST_LOG="$LOG_DIR/latest.log"

# Point runs/latest at this run before it starts.
ln -sfn "$ASIC_RUN_STAMP" "$RUNS_ROOT/latest"

echo "Running Synopsys Design Compiler logical synthesis"
echo "Repository root : $REPO_ROOT"
echo "DC executable   : $DC_EXE"
echo "Target library  : $DC_TARGET_LIB"
echo "Constraints     : $GOLDEN_SDC"
echo "Run stamp       : $ASIC_RUN_STAMP"
echo "CACHE_BYTES     : $ASIC_CACHE_BYTES"
echo "ASSOC           : $ASIC_ASSOC"
echo "Clock period    : $ASIC_CLOCK_PERIOD_NS ns"
echo "Results         : $OUT_DIR"
echo "Log file        : $LOG_FILE"
echo

# Run from inside work/ so the tool's own droppings stay with this run.
cd "$WORK_DIR"

set +e
"$DC_EXE" -64bit -f "$DC_TCL" 2>&1 | tee "$LOG_FILE"
status=${PIPESTATUS[0]}
set -e

if ! ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LOG" 2>/dev/null; then
    cp "$LOG_FILE" "$LATEST_LOG" 2>/dev/null || true
fi

echo
echo "Design Compiler exit status: $status"
echo "Reports                    : $REPORT_DIR"
echo "Netlist                    : $NETLIST_DIR"
echo "Database                   : $DB_DIR"
if [[ -f "$REPORT_DIR/summary.rpt" ]]; then echo; cat "$REPORT_DIR/summary.rpt"; fi
echo "Latest log                 : $LATEST_LOG"

exit "$status"
