#!/usr/bin/env bash
set -u

# Fast PASS/FAIL verification sweep from the Cache root.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

overall_status=0
CPU_REQ_PROB="${1:-0.8}"
CPU_RESP_PROB="${2:-}"
if [[ -z "$CPU_RESP_PROB" ]]; then
    CPU_RESP_PROB="$CPU_REQ_PROB"
fi

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

run_job "Questa ${CPU_REQ_PROB} ${CPU_RESP_PROB}"  "$SCRIPT_DIR/openflex/verify.sh" --quiet "$CPU_REQ_PROB" "$CPU_RESP_PROB"
run_job "Xcelium ${CPU_REQ_PROB} ${CPU_RESP_PROB}" env CACHE_CPU_REQ_PROB="$CPU_REQ_PROB" CACHE_CPU_RESP_PROB="$CPU_RESP_PROB" CACHE_ROOT="$SCRIPT_DIR" bash -lc 'source /apps/settings && cd "$CACHE_ROOT/xcelium" && ./run.sh --quiet "$CACHE_CPU_REQ_PROB" "$CACHE_CPU_RESP_PROB"'

exit "$overall_status"
