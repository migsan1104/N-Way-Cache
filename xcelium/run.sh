#!/usr/bin/env bash
set -euo pipefail

QUIET=0
if [[ "${1:-}" == "--quiet" ]]; then
    QUIET=1
    shift
fi

CPU_REQ_PROB="${1:-1.0}"
CPU_RESP_PROB="${2:-1.0}"

if ! command -v xrun >/dev/null 2>&1; then
    echo "ERROR: xrun was not found."
    echo "Run 'source /apps/settings' before launching this script."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

./clean.sh
mkdir -p logs waves

if (( QUIET == 0 )); then
    echo "Running Xcelium batch simulation for Test_Complete..."
    echo "CPU_REQ_VALID_PROBABILITY=${CPU_REQ_PROB}"
    echo "CPU_RESP_READY_PROBABILITY=${CPU_RESP_PROB}"
    echo "Log: logs/xrun.log"
fi

XRUN_CMD=(
    xrun
    -64bit \
    -sv \
    -timescale 1ns/1ps \
    -f filelist.f \
    -top Test_Complete \
    -defparam "Test_Complete.CPU_REQ_VALID_PROBABILITY=${CPU_REQ_PROB}" \
    -defparam "Test_Complete.CPU_RESP_READY_PROBABILITY=${CPU_RESP_PROB}" \
    -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_1=0" \
    -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_2=0" \
    -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_4=0" \
    -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_8=0" \
    -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_16=0" \
    -access +rwc \
    -l logs/xrun.log
)

set +e
if (( QUIET == 0 )); then
    "${XRUN_CMD[@]}"
    status=$?
else
    "${XRUN_CMD[@]}" > logs/xrun.stdout 2>&1
    status=$?
fi
set -e

if grep -q "Congrats all associativity tests passed" logs/xrun.log; then
    if (( QUIET == 0 )); then
        echo "Xcelium simulation PASSED"
    fi
else
    if (( QUIET == 0 )); then
        echo "Xcelium simulation FAILED"
        echo "See logs/xrun.log"
    fi
    if [[ $status -eq 0 ]]; then
        exit 1
    else
        exit "${status}"
    fi
fi
