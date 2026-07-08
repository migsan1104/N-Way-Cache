#!/usr/bin/env bash
set -o pipefail

# Work regardless of the directory from which this script is launched.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

QUIET=0
if [[ "${1:-}" == "--quiet" ]]; then
    QUIET=1
    shift
fi

CPU_REQ_PROB="${1:-1.0}"
CPU_RESP_PROB="${2:-1.0}"

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
CONFIG_TEMPLATE="$SCRIPT_DIR/Cache_verification.yml"
CONFIG="$SCRIPT_DIR/.Cache_verification_current.yml"
trap 'rm -f "$CONFIG"' EXIT

sed -E "/^[[:space:]]*CACHE_BYTES:/a\\
  CPU_REQ_VALID_PROBABILITY: [$CPU_REQ_PROB]\\
  CPU_RESP_READY_PROBABILITY: [$CPU_RESP_PROB]\\
  TOGGLE_ASSOC_DEBUG_1: [0]\\
  TOGGLE_ASSOC_DEBUG_2: [0]\\
  TOGGLE_ASSOC_DEBUG_4: [0]\\
  TOGGLE_ASSOC_DEBUG_8: [0]\\
  TOGGLE_ASSOC_DEBUG_16: [0]" "$CONFIG_TEMPLATE" > "$CONFIG"

{
    echo "Running: openflex $CONFIG"
    echo "Working directory: $SCRIPT_DIR"
    echo "CPU_REQ_VALID_PROBABILITY=$CPU_REQ_PROB"
    echo "CPU_RESP_READY_PROBABILITY=$CPU_RESP_PROB"
    echo "Started: $(date)"
    echo
} >"$TRANSCRIPT"

if (( QUIET == 0 )); then
    cat "$TRANSCRIPT"
fi

if (( QUIET == 0 )); then
    openflex "$CONFIG" 2>&1 | tee -a "$TRANSCRIPT"
    status=${PIPESTATUS[0]}
else
    openflex "$CONFIG" >> "$TRANSCRIPT" 2>&1
    status=$?
fi

cp "$TRANSCRIPT" "$RUN_LOG"

if (( status != 0 )); then
    message="Verification FAILED (OpenFLEX exited with status $status; see $TRANSCRIPT)"
    echo "$message" >> "$TRANSCRIPT"
    (( QUIET == 0 )) && echo "$message"
elif grep -qiE '(^|[^[:alpha:]])(error|fatal|failure):' "$TRANSCRIPT"; then
    message="Verification FAILED (see $TRANSCRIPT)"
    echo "$message" >> "$TRANSCRIPT"
    (( QUIET == 0 )) && echo "$message"
    status=1
elif ! grep -q 'Congrats all associativity tests passed' "$TRANSCRIPT"; then
    message="Verification FAILED (no passing Cache test summary; see $TRANSCRIPT)"
    echo "$message" >> "$TRANSCRIPT"
    (( QUIET == 0 )) && echo "$message"
    status=1
else
    message="Verification PASSED"
    echo "$message" >> "$TRANSCRIPT"
    (( QUIET == 0 )) && echo "$message"
fi

cp "$TRANSCRIPT" "$RUN_LOG"

exit "$status"
