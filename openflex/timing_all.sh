#!/usr/bin/env bash
set -o pipefail

# Work regardless of the directory from which this script is launched.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

if [[ -f /apps/reconfig/enable_pro ]]; then
    # shellcheck disable=SC1091
    source /apps/reconfig/enable_pro
elif [[ -f /apps/reconfig/enable_std ]]; then
    # shellcheck disable=SC1091
    source /apps/reconfig/enable_std
fi

CONFIG="$SCRIPT_DIR/Cache_timing_all.yml"
TABLE="$SCRIPT_DIR/Cache_timing_all.csv"
TRANSCRIPT="$SCRIPT_DIR/timing_all_transcript"
RUN_LOG="$SCRIPT_DIR/timing_all.log"

# Start each sweep from a clean table/log so stale rows cannot survive.
: >"$TABLE"
{
    echo "Running: openflex $CONFIG -c $TABLE"
    echo "Working directory: $SCRIPT_DIR"
    echo "Started: $(date)"
    echo
} >"$TRANSCRIPT"

cat "$TRANSCRIPT"

openflex "$CONFIG" -c "$TABLE" 2>&1 | tee -a "$TRANSCRIPT"
status=${PIPESTATUS[0]}

cp "$TRANSCRIPT" "$RUN_LOG"

if (( status != 0 )); then
    echo "Timing sweep FAILED (OpenFLEX exited with status $status; see $TRANSCRIPT)" | tee -a "$TRANSCRIPT"
    cp "$TRANSCRIPT" "$RUN_LOG"
    exit "$status"
fi

echo "Timing sweep complete. Results table: $TABLE" | tee -a "$TRANSCRIPT"
cp "$TRANSCRIPT" "$RUN_LOG"
