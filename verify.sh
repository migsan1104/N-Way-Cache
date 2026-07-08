#!/usr/bin/env bash
set -u

# Fast PASS/FAIL verification sweep from the Cache root.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

overall_status=0

run_job() {
    local label="$1"
    shift

    "$@" >/dev/null 2>&1
    local status=$?

    if [[ $status -eq 0 ]]; then
        echo "${label}: PASS"
    else
        echo "${label}: FAIL"
        overall_status=1
    fi
}

run_job "Questa 1.0 1.0"  "$SCRIPT_DIR/openflex/verify.sh" --quiet 1.0 1.0
run_job "Questa 0.8 0.8"  "$SCRIPT_DIR/openflex/verify.sh" --quiet 0.8 0.8
run_job "Xcelium 1.0 1.0" bash -lc "source /apps/settings && cd '$SCRIPT_DIR/xcelium' && ./run.sh --quiet 1.0 1.0"
run_job "Xcelium 0.8 0.8" bash -lc "source /apps/settings && cd '$SCRIPT_DIR/xcelium' && ./run.sh --quiet 0.8 0.8"

exit "$overall_status"
