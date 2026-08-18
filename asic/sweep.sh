#!/usr/bin/env bash
set -uo pipefail

# Run logical synthesis across several associativities and print the PPA tables.
#
# Usage:
#   ./sweep.sh                        # genus + dc, ASSOC 1 2 4 8 16, sequential
#   ./sweep.sh -t dc                  # one tool
#   ./sweep.sh -a "4 8"               # a subset of associativities
#   ./sweep.sh -j 5                   # run up to 5 configurations concurrently
#   ./sweep.sh -t genus -a 4 -p 2.5   # one config at a 2.500 ns target
#
# Each configuration writes into its own PPA/<tool>/assoc_<N>/work directory, so
# concurrent runs cannot corrupt one another. The practical limit on -j is how
# many tool licenses are available, not the flow.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

TOOLS="genus dc"
ASSOCS="1 2 4 8 16"
JOBS=1
PERIOD=""

usage() {
    awk '/^#/ && NR>1 {sub(/^# ?/, ""); print; seen=1; next} seen {exit}' "${BASH_SOURCE[0]}"
    exit "${1:-0}"
}

while getopts ":t:a:j:p:h" opt; do
    case "$opt" in
        t) TOOLS="$OPTARG" ;;
        a) ASSOCS="$OPTARG" ;;
        j) JOBS="$OPTARG" ;;
        p) PERIOD="$OPTARG" ;;
        h) usage 0 ;;
        \?) echo "ERROR: unknown option -$OPTARG" >&2; usage 1 ;;
        :)  echo "ERROR: -$OPTARG requires an argument" >&2; usage 1 ;;
    esac
done

for t in $TOOLS; do
    case "$t" in
        genus|dc) ;;
        *) echo "ERROR: unknown tool '$t' (expected genus or dc)" >&2; exit 1 ;;
    esac
done

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || (( JOBS < 1 )); then
    echo "ERROR: -j must be a positive integer, got '$JOBS'" >&2
    exit 1
fi

STAMP=$(date +%Y%m%d_%H%M%S)
SWEEP_LOG_DIR="$SCRIPT_DIR/PPA/sweep_logs"
mkdir -p "$SWEEP_LOG_DIR"
SUMMARY="$SWEEP_LOG_DIR/sweep_${STAMP}.txt"

echo "ASIC synthesis sweep"
echo "  tools          : $TOOLS"
echo "  associativities: $ASSOCS"
echo "  concurrency    : $JOBS"
echo "  clock period   : ${PERIOD:-default (2.000 ns)}"
echo "  summary        : $SUMMARY"
echo

run_one() {
    local tool="$1" assoc="$2"
    local log="$SWEEP_LOG_DIR/${tool}_assoc${assoc}_${STAMP}.log"
    local started
    started=$(date +%s)
    if "$SCRIPT_DIR/run_${tool}.sh" "$assoc" ${PERIOD:+"$PERIOD"} >"$log" 2>&1; then
        echo "$tool assoc=$assoc PASS ($(( ($(date +%s) - started) / 60 )) min)" | tee -a "$SUMMARY"
    else
        echo "$tool assoc=$assoc FAIL (see $log)" | tee -a "$SUMMARY"
    fi
}

pids=()
for tool in $TOOLS; do
    for assoc in $ASSOCS; do
        run_one "$tool" "$assoc" &
        pids+=($!)
        # Throttle to JOBS concurrent runs.
        while (( $(jobs -rp | wc -l) >= JOBS )); do
            wait -n 2>/dev/null || sleep 5
        done
    done
done
wait

echo
echo "=== sweep complete ==="
cat "$SUMMARY"
echo
"$SCRIPT_DIR/collect_ppa.py" 2>/dev/null || /apps/anaconda/bin/python "$SCRIPT_DIR/collect_ppa.py"
