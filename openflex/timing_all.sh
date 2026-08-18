#!/usr/bin/env bash
set -o pipefail

# Run the FPGA PPA sweep across associativities, all at once.
#
# Each associativity is a separate ./timing.sh run, so each produces its own
# self-contained PPA/assoc_<N>/ report set - simpler to read than one merged
# sweep, and the runs are independent so they can execute concurrently. Wall
# time is therefore one run (~25-35 min) rather than the sum of five (~3 h).
#
# This is safe only because timing.sh now builds in a per-associativity
# directory; see the comment there. Do not reintroduce a shared build dir.
#
# Usage:
#   ./timing_all.sh              # all five, all in parallel
#   ./timing_all.sh -j 2         # at most two at a time
#   ./timing_all.sh 4 8          # only these associativities

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

JOBS=5
while getopts ":j:" opt; do
    case "$opt" in
        j) JOBS="$OPTARG" ;;
        *) echo "usage: $0 [-j N] [assoc ...]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

ASSOCS=("$@")
if [[ ${#ASSOCS[@]} -eq 0 ]]; then
    ASSOCS=(1 2 4 8 16)
fi

for a in "${ASSOCS[@]}"; do
    case "$a" in
        1|2|4|8|16) ;;
        *) echo "ERROR: invalid associativity '$a'" >&2; exit 1 ;;
    esac
done

SUMMARY="$SCRIPT_DIR/timing_all_transcript"
RUN_LOG="$SCRIPT_DIR/timing_all.log"
TABLE="$SCRIPT_DIR/Cache_timing_all.csv"

{
    echo "FPGA PPA sweep"
    echo "Associativities : ${ASSOCS[*]}"
    echo "Max concurrent  : $JOBS"
    echo "Started         : $(date)"
    echo
} | tee "$SUMMARY"

declare -A PID_OF
declare -A START_OF
running=0

start_one() {
    local a=$1
    START_OF[$a]=$(date +%s)
    ./timing.sh "$a" > "$SCRIPT_DIR/timing_assoc${a}_stdout.log" 2>&1 &
    PID_OF[$a]=$!
    echo "  launched ASSOC=$a (pid ${PID_OF[$a]})" | tee -a "$SUMMARY"
}

# Launch, respecting the concurrency cap.
pending=("${ASSOCS[@]}")
declare -A STATUS_OF
while [[ ${#pending[@]} -gt 0 || $running -gt 0 ]]; do
    while [[ ${#pending[@]} -gt 0 && $running -lt $JOBS ]]; do
        a=${pending[0]}; pending=("${pending[@]:1}")
        start_one "$a"
        running=$((running + 1))
    done

    wait -n 2>/dev/null || true
    running=0
    for a in "${ASSOCS[@]}"; do
        pid=${PID_OF[$a]:-}
        [[ -z "$pid" ]] && continue
        [[ -n "${STATUS_OF[$a]:-}" ]] && continue
        if kill -0 "$pid" 2>/dev/null; then
            running=$((running + 1))
        else
            wait "$pid"; rc=$?
            STATUS_OF[$a]=$rc
            elapsed=$(( $(date +%s) - START_OF[$a] ))
            if (( rc == 0 )); then
                echo "  ASSOC=$a PASS ($((elapsed / 60)) min)" | tee -a "$SUMMARY"
            else
                echo "  ASSOC=$a FAIL rc=$rc ($((elapsed / 60)) min)" | tee -a "$SUMMARY"
            fi
        fi
    done
done

# Rebuild the merged table from the per-associativity CSVs, so the combined view
# still exists for anything that reads it.
: > "$TABLE"
for a in "${ASSOCS[@]}"; do
    csv="$SCRIPT_DIR/PPA/assoc_$a/cache${a}.csv"
    [[ -s "$csv" ]] && cat "$csv" >> "$TABLE"
done

fail=0
{
    echo
    echo "Sweep complete: $(date)"
    for a in "${ASSOCS[@]}"; do
        rc=${STATUS_OF[$a]:-1}
        (( rc != 0 )) && fail=1
        printf "  ASSOC=%-3s %s\n" "$a" "$( ((rc==0)) && echo PASS || echo "FAIL(rc=$rc)")"
    done
    echo "Merged table : $TABLE"
    echo "Per-run data : PPA/assoc_<N>/"
} | tee -a "$SUMMARY"

cp "$SUMMARY" "$RUN_LOG"
exit "$fail"
