#!/usr/bin/env bash

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

# Use the installed Questa release when it has not already been configured.
QUESTA_HOME=${QUESTA_HOME:-/apps/reconfig/tools/siemens/questasim/2023.3}
export PATH="$QUESTA_HOME/linux_x86_64:$PATH"

TRANSCRIPT="$SCRIPT_DIR/transcript"
RUN_LOG="$SCRIPT_DIR/run.log"
CONFIG="$SCRIPT_DIR/Cache_verification.yml"

{
    echo "Running: openflex $CONFIG"
    echo "Working directory: $SCRIPT_DIR"
    echo "Started: $(date)"
    echo
} >"$TRANSCRIPT"

cat "$TRANSCRIPT"

openflex "$CONFIG" 2>&1 | tee -a "$TRANSCRIPT"
status=${PIPESTATUS[0]}

cp "$TRANSCRIPT" "$RUN_LOG"

if (( status != 0 )); then
    echo "Verification FAILED (OpenFLEX exited with status $status; see $TRANSCRIPT)" | tee -a "$TRANSCRIPT"
elif grep -qiE '(^|[^[:alpha:]])(error|fatal|failure):' "$TRANSCRIPT"; then
    echo "Verification FAILED (see $TRANSCRIPT)" | tee -a "$TRANSCRIPT"
    status=1
elif ! grep -q 'Congrats all associativity tests passed' "$TRANSCRIPT"; then
    echo "Verification FAILED (no passing Cache test summary; see $TRANSCRIPT)" | tee -a "$TRANSCRIPT"
    status=1
else
    echo "Verification PASSED" | tee -a "$TRANSCRIPT"
fi

cp "$TRANSCRIPT" "$RUN_LOG"

exit "$status"
