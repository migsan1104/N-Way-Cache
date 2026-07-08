#!/usr/bin/env bash
set -o pipefail

# Per-associativity timing/PPA flow.
# Usage:
#   ./timing.sh      # defaults to ASSOC=8
#   ./timing.sh 4

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

ASSOC="${1:-8}"

case "$ASSOC" in
    1|2|4|8|16)
        ;;
    *)
        echo "ERROR: invalid associativity '$ASSOC'"
        echo "Valid associativities: 1, 2, 4, 8, 16"
        exit 1
        ;;
esac

if [[ -f /apps/reconfig/enable_pro ]]; then
    # shellcheck disable=SC1091
    source /apps/reconfig/enable_pro
elif [[ -f /apps/reconfig/enable_std ]]; then
    # shellcheck disable=SC1091
    source /apps/reconfig/enable_std
fi

PPA_DIR="$SCRIPT_DIR/PPA/assoc_$ASSOC"
POWER_DIR="$PPA_DIR/power"
OUTPUTS_DIR="$PPA_DIR/outputs"
CSV_PATH="$PPA_DIR/cache${ASSOC}.csv"

CONFIG_TEMPLATE="$SCRIPT_DIR/Cache_timing_all.yml"
RUN_CONFIG="$SCRIPT_DIR/.Cache_timing_assoc${ASSOC}.yml"
TRANSCRIPT="$SCRIPT_DIR/timing_assoc${ASSOC}_transcript"
RUN_LOG="$SCRIPT_DIR/timing_assoc${ASSOC}.log"
BUILD_OUTPUTS="$SCRIPT_DIR/build_vivado/outputs"

mkdir -p "$POWER_DIR" "$OUTPUTS_DIR"

sed -E "s/^([[:space:]]*ASSOC:).*/\1 [$ASSOC]/" \
    "$CONFIG_TEMPLATE" > "$RUN_CONFIG"

# Start each run from a clean table/log so stale rows cannot survive.
: > "$CSV_PATH"
{
    echo "Running: openflex $RUN_CONFIG -c $CSV_PATH"
    echo "Working directory: $SCRIPT_DIR"
    echo "Associativity: $ASSOC"
    echo "Started: $(date)"
    echo
} > "$TRANSCRIPT"

cat "$TRANSCRIPT"

openflex "$RUN_CONFIG" -c "$CSV_PATH" 2>&1 | tee -a "$TRANSCRIPT"
status=${PIPESTATUS[0]}

cp "$TRANSCRIPT" "$RUN_LOG"

if (( status != 0 )); then
    echo "Timing run FAILED (OpenFLEX exited with status $status; see $TRANSCRIPT)" | tee -a "$TRANSCRIPT"
    cp "$TRANSCRIPT" "$RUN_LOG"
    exit "$status"
fi

find "$OUTPUTS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
if [[ -d "$BUILD_OUTPUTS" ]]; then
    cp -a "$BUILD_OUTPUTS"/. "$OUTPUTS_DIR"/
else
    echo "WARNING: build outputs directory not found: $BUILD_OUTPUTS" | tee -a "$TRANSCRIPT"
fi

POWER_REPORT_PATH=""
if [[ -f "$BUILD_OUTPUTS/post_route_power.rpt" ]]; then
    timestamp=$(date +%Y-%m-%d_%H%M%S)
    POWER_REPORT_PATH="$POWER_DIR/power_assoc${ASSOC}_${timestamp}.rpt"
    suffix=1
    while [[ -e "$POWER_REPORT_PATH" ]]; do
        POWER_REPORT_PATH="$POWER_DIR/power_assoc${ASSOC}_${timestamp}_${suffix}.rpt"
        suffix=$((suffix + 1))
    done
    cp "$BUILD_OUTPUTS/post_route_power.rpt" "$POWER_REPORT_PATH"
else
    echo "WARNING: final post-route power report not found: $BUILD_OUTPUTS/post_route_power.rpt" | tee -a "$TRANSCRIPT"
fi

{
    echo
    echo "Timing/PPA run complete."
    echo "Associativity used : $ASSOC"
    echo "CSV path           : $CSV_PATH"
    echo "Outputs path       : $OUTPUTS_DIR"
    echo "Power report path  : ${POWER_REPORT_PATH:-not generated}"
} | tee -a "$TRANSCRIPT"

cp "$TRANSCRIPT" "$RUN_LOG"
