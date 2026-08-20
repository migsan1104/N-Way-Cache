#!/usr/bin/env bash
set -u

# Full regression, all four checks at once:
#   Questa 0.8, Questa 1.0, Xcelium 0.8, Xcelium 1.0
#
# The four jobs cannot share this checkout (openflex/verify.sh writes a fixed
# temp-config path and xcelium/run.sh starts by wiping its build dir), so each
# job runs in its own throwaway copy of the tree. ~15 MB per copy.
#
# Output: one PASS/FAIL line per job, then each job's FINAL REPORT PER
# ASSOCIATIVITY block exactly as the testbench printed it. No signal logs.
#
# Usage:
#   ./verify_all.sh                # the standard four checks
#   ./verify_all.sh --keep         # keep the work area for inspection

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

WORK=$(mktemp -d /tmp/cache_verify_all.XXXXXX)
[[ $KEEP -eq 0 ]] && trap 'rm -rf "$WORK"' EXIT

JOBS=(questa08 questa10 xcel08 xcel10)

for job in "${JOBS[@]}"; do
    J="$WORK/$job"
    mkdir -p "$J/openflex" "$J/xcelium/logs"
    cp -a "$SCRIPT_DIR/src" "$SCRIPT_DIR/extra_rtl" "$SCRIPT_DIR/Verification" "$J/"
    cp -a "$SCRIPT_DIR/openflex/verify.sh" "$SCRIPT_DIR/openflex/Cache_verification.yml" \
          "$SCRIPT_DIR/openflex/rtl" "$J/openflex/"
    cp -a "$SCRIPT_DIR/xcelium/run.sh" "$SCRIPT_DIR/xcelium/clean.sh" \
          "$SCRIPT_DIR/xcelium/filelist.f" "$J/xcelium/"
done

echo "Running 4 verification jobs in parallel (work area: $WORK)"

( cd "$WORK/questa08/openflex" && ./verify.sh 0.8 ) > "$WORK/questa08.out" 2>&1 &
P1=$!
( cd "$WORK/questa10/openflex" && ./verify.sh 1.0 ) > "$WORK/questa10.out" 2>&1 &
P2=$!
( source /apps/settings >/dev/null 2>&1 && cd "$WORK/xcel08/xcelium" && ./run.sh 0.8 ) > "$WORK/xcel08.out" 2>&1 &
P3=$!
( source /apps/settings >/dev/null 2>&1 && cd "$WORK/xcel10/xcelium" && ./run.sh 1.0 ) > "$WORK/xcel10.out" 2>&1 &
P4=$!

declare -A RC
wait $P1; RC[questa08]=$?
wait $P2; RC[questa10]=$?
wait $P3; RC[xcel08]=$?
wait $P4; RC[xcel10]=$?

label() {
    case "$1" in
        questa08) echo "Questa  0.8" ;;
        questa10) echo "Questa  1.0" ;;
        xcel08)   echo "Xcelium 0.8" ;;
        xcel10)   echo "Xcelium 1.0" ;;
    esac
}

log_of() {
    case "$1" in
        questa*) echo "$WORK/$1/openflex/transcript" ;;
        xcel*)   echo "$WORK/$1/xcelium/logs/xrun.log" ;;
    esac
}

echo
echo "==== REGRESSION RESULTS ===="
fail=0
for job in "${JOBS[@]}"; do
    if [[ ${RC[$job]} -eq 0 ]] && grep -q "Congrats all associativity tests passed" "$(log_of "$job")" 2>/dev/null; then
        echo "$(label "$job")  PASS"
    else
        echo "$(label "$job")  FAIL (rc=${RC[$job]})"
        fail=1
    fi
done

# The testbench's own end-of-run report, per job. Strip Questa's "# " prefix so
# the two simulators read the same.
for job in "${JOBS[@]}"; do
    echo
    echo "---- $(label "$job") ----"
    sed -n '/FINAL REPORT PER ASSOCIATIVITY/,/Congrats all associativity tests passed/p' \
        "$(log_of "$job")" 2>/dev/null | sed 's/^# //' \
        || echo "(no report found)"
done

[[ $KEEP -eq 1 ]] && { echo; echo "Work area kept: $WORK"; }
exit "$fail"
