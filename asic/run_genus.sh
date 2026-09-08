#!/usr/bin/env bash
set -euo pipefail

# Cadence Genus physically-aware synthesis for one cache configuration.
#
# Usage:
#   ./run_genus.sh              # ASSOC=8
#   ./run_genus.sh 4            # ASSOC=4
#   ./run_genus.sh 4 3.500      # ASSOC=4, 3.500 ns reported target
#
# The clock the tool actually optimizes against comes from
# synthesis/common/constraints/golden.sdc. The second argument only labels the
# run; if you change the period, change golden.sdc.
#
# Environment overrides:
#   ASIC_SIGNOFF_LIB       setup-timing liberty (default: ss_n40C_1v28)
#   ASIC_POWER_LIB         power-sanity liberty (default: tt_025C_1v80)
#   ASIC_TECH_LEF          technology LEF
#   ASIC_CELL_LEF          standard cell LEF
#   ASIC_STOP_AFTER_SETUP  1 = run setup + checks only, skip synthesis
#   ASIC_TAG_ONEHOT        1 = elaborate with TAG_READ_ONEHOT=1 (Entry 21
#                          one-hot metadata read, ASIC-only RTL form)
#
# Results land in asic/PPA/genus/assoc_<N>/runs/<stamp>/ with a `latest`
# symlink pointing at the most recent run.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
SYNTH_DIR="$SCRIPT_DIR/synthesis"
CADENCE_DIR="$SYNTH_DIR/cadence"
COMMON_DIR="$SYNTH_DIR/common"

GENUS_TCL="$CADENCE_DIR/scripts/run_genus.tcl"
PROJECT_CONFIG="$COMMON_DIR/scripts/project_config.tcl"
RTL_FILELIST="$COMMON_DIR/filelists/rtl_files.tcl"
GOLDEN_SDC="$COMMON_DIR/constraints/golden.sdc"

export ASIC_FLOW=genus
export ASIC_ASSOC="${1:-${ASIC_ASSOC:-8}}"
export ASIC_CLOCK_PERIOD_NS="${2:-${ASIC_CLOCK_PERIOD_NS:-3.500}}"
export ASIC_CACHE_BYTES="${ASIC_CACHE_BYTES:-16384}"
export ASIC_STOP_AFTER_SETUP="${ASIC_STOP_AFTER_SETUP:-0}"

case "$ASIC_ASSOC" in
    1|2|4|8|16) ;;
    *)
        echo "ERROR: invalid associativity '$ASIC_ASSOC' (expected 1, 2, 4, 8, or 16)" >&2
        exit 1
        ;;
esac

for f in "$GENUS_TCL:Genus Tcl script" \
         "$PROJECT_CONFIG:shared project configuration" \
         "$RTL_FILELIST:RTL filelist" \
         "$GOLDEN_SDC:golden SDC"; do
    path="${f%%:*}"; label="${f#*:}"
    if [[ ! -f "$path" ]]; then
        echo "ERROR: $label does not exist: $path" >&2
        exit 1
    fi
done

if [[ -n "${GENUS_SETUP_SCRIPT:-}" ]]; then
    if [[ ! -f "$GENUS_SETUP_SCRIPT" ]]; then
        echo "ERROR: GENUS_SETUP_SCRIPT does not exist: $GENUS_SETUP_SCRIPT" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$GENUS_SETUP_SCRIPT"
fi

if [[ -n "${GENUS_MODULE:-}" ]]; then
    if command -v module >/dev/null 2>&1; then
        module load "$GENUS_MODULE"
    else
        echo "ERROR: GENUS_MODULE was set but the module command is unavailable." >&2
        exit 1
    fi
fi

if command -v genus >/dev/null 2>&1; then
    GENUS_EXE=$(command -v genus)
elif command -v genus_shell >/dev/null 2>&1; then
    GENUS_EXE=$(command -v genus_shell)
else
    echo "ERROR: neither genus nor genus_shell was found in PATH." >&2
    echo "Run 'source /apps/settings' before launching." >&2
    exit 1
fi

# One stamped directory per run, so no two runs can ever be blended together.
ASIC_RUN_STAMP="${ASIC_RUN_STAMP:-$(date +%Y%m%d_%H%M%S)}"
export ASIC_RUN_STAMP

RUN_DIR="$SCRIPT_DIR/PPA/genus/assoc_$ASIC_ASSOC"
RUNS_ROOT="$RUN_DIR/runs"
OUT_DIR="$RUNS_ROOT/$ASIC_RUN_STAMP"
LOG_DIR="$OUT_DIR/logs"
WORK_DIR="$OUT_DIR/work"

mkdir -p "$OUT_DIR/reports" "$OUT_DIR/netlist" "$OUT_DIR/db" "$LOG_DIR" "$WORK_DIR"

LOG_PREFIX="$LOG_DIR/genus_${ASIC_RUN_STAMP}"
LOG_FILE="${LOG_PREFIX}.log"

echo "Running Cadence Genus physically-aware synthesis"
echo "Repository root : $REPO_ROOT"
echo "Genus executable: $GENUS_EXE"
echo "CACHE_BYTES     : $ASIC_CACHE_BYTES"
echo "ASSOC           : $ASIC_ASSOC"
echo "Clock target    : $ASIC_CLOCK_PERIOD_NS ns (authoritative value in golden.sdc)"
echo "Constraints     : $GOLDEN_SDC"
echo "Max cap knob    : ${ASIC_MAX_CAP:-0.100 (default)}  (ASIC_MAX_CAP; none = library per-pin limits)"
echo "Run stamp       : $ASIC_RUN_STAMP"
echo "Output directory: $OUT_DIR"
echo "Log file        : $LOG_FILE"
if [[ "$ASIC_STOP_AFTER_SETUP" == "1" ]]; then
    echo "Mode            : SETUP CHECK ONLY (synthesis skipped)"
fi
echo

# Point runs/latest at this run before it starts, so a run in progress is
# findable, and so a crashed run does not leave the symlink pointing at an
# older run that could be mistaken for the current one.
ln -sfn "$ASIC_RUN_STAMP" "$RUNS_ROOT/latest"

# Run from inside work/ so the tool's own droppings stay with this run.
cd "$WORK_DIR"

set +e
"$GENUS_EXE" -batch -no_gui -abort_on_error -files "$GENUS_TCL" -log "$LOG_PREFIX"
status=$?
set -e

echo
echo "Genus exit status: $status"
echo "Reports          : $OUT_DIR/reports"
echo "Netlist          : $OUT_DIR/netlist"
echo "Database         : $OUT_DIR/db"
echo "Log              : $LOG_FILE"
echo "Latest symlink   : $RUNS_ROOT/latest -> $ASIC_RUN_STAMP"

if [[ -f "$OUT_DIR/reports/summary.rpt" ]]; then
    echo
    cat "$OUT_DIR/reports/summary.rpt"
fi

exit "$status"
