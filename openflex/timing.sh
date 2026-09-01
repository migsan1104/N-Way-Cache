#!/usr/bin/env bash
set -o pipefail

# Per-associativity timing/PPA flow.
# Usage:
#   ./timing.sh      # defaults to ASSOC=8
#   ./timing.sh 4

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

# OpenFLEX is installed in the user's local bin on this system. Add it here so
# the script also works from terminals that do not preload ~/.local/bin.
export PATH="$HOME/.local/bin:$PATH"

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

# EDA environment. 2026-08-25: IT replaced /apps/reconfig/enable_pro and
# enable_std with a single /apps/reconfig/enable (Questa 2026.2, Vivado
# 2025.2) and moved the old files to /apps/reconfig/archive/. Every
# measurement in this repo was taken with the OLD toolchain (Questa 2023.3,
# Vivado 2021.2), so prefer it - the archived copies still check out
# licenses - and fall back to the new file only if they vanish.
ENABLE_CANDIDATES=(
    /apps/reconfig/enable_pro
    /apps/reconfig/archive/enable_pro
    /apps/reconfig/enable_std
    /apps/reconfig/archive/enable_std
    /apps/reconfig/enable
)
for _enable in "${ENABLE_CANDIDATES[@]}"; do
    if [[ -f "$_enable" ]]; then
        # shellcheck disable=SC1090
        source "$_enable"
        break
    fi
done

PPA_DIR="$SCRIPT_DIR/PPA/assoc_$ASSOC"
POWER_DIR="$PPA_DIR/power"
OUTPUTS_DIR="$PPA_DIR/outputs"
CSV_PATH="$PPA_DIR/cache${ASSOC}.csv"

CONFIG_TEMPLATE="$SCRIPT_DIR/Cache_timing_all.yml"
RUN_CONFIG="$SCRIPT_DIR/.Cache_timing_assoc${ASSOC}.yml"
TRANSCRIPT="$SCRIPT_DIR/timing_assoc${ASSOC}_transcript"
RUN_LOG="$SCRIPT_DIR/timing_assoc${ASSOC}.log"

# Each associativity builds in its OWN directory so several runs can execute at
# the same time.
#
# OpenFLEX creates its build directory with a bare relative path
# (config.py: pathlib.Path("build_vivado").mkdir), so it lands in whatever
# directory the process happens to be started from. Every run used to start from
# openflex/, which meant they all shared one build_vivado - and since this
# script copies whatever it finds in build_vivado/outputs into
# PPA/assoc_<N>/outputs, two concurrent runs would not just collide, they would
# quietly file one run's results under the other's associativity.
#
# Starting each run in its own directory isolates the build. The catch is that
# config.py also resolves the `files:` list with os.path.abspath against the
# process working directory, so the generated config must carry ABSOLUTE RTL
# paths - relative ones would resolve against the new directory and vanish.
BUILD_DIR="$SCRIPT_DIR/.build_assoc${ASSOC}"
BUILD_OUTPUTS="$BUILD_DIR/build_vivado/outputs"

mkdir -p "$POWER_DIR" "$OUTPUTS_DIR" "$BUILD_DIR"

# Rewrite the ASSOC line, and make every relative .sv path absolute so the
# config still resolves from inside $BUILD_DIR.
sed -E \
    -e "s/^([[:space:]]*ASSOC:).*/\1 [$ASSOC]/" \
    -e "s|^([[:space:]]*-[[:space:]]+)([^/[:space:]][^[:space:]]*\.sv)[[:space:]]*$|\1$SCRIPT_DIR/\2|" \
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

( cd "$BUILD_DIR" && openflex "$RUN_CONFIG" -c "$CSV_PATH" ) 2>&1 | tee -a "$TRANSCRIPT"
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
