#!/usr/bin/env bash
# cts_experiment.sh <base_stamp> <new_stamp> <tmux_tag> [VAR=VAL ...]
# CTS-only experiment (2026-09-07, CTS.md "Is the tree bad"): re-run stage 04
# (ccopt + post-CTS opt) on a FROZEN placement, so clock-tree recipes can be
# compared on one variable each in ~1 h instead of a 5 h P&R. Seeds
# runs/<new>/checkpoints/03_place.enc(.dat) as symlinks to the base run's
# placement, then launch_from_knobs.sh with ASIC_PNR_FROM=04 ASIC_PNR_TO=04
# plus your overrides. Read the result from:
#   runs/<new>/reports/cts/skew.rpt            (no source latency: tripwire)
#   runs/<new>/reports/cts/clocks_after_ccopt.rpt
#   runs/<new>/logs/flow.log  "Skew group summary after post-conditioning"
#   runs/<new>/reports/postcts_opt/*.summary.gz (honest reg2reg WNS)
# Typical recipes:
#   A  ASIC_CTS_BUFFER_CELLS="clkbuf_8 clkbuf_16" ASIC_CTS_INVERTER_CELLS="clkinv_8 clkinv_16" ASIC_CTS_TARGET_SKEW=0.35
#   B  A + ASIC_CTS_CLOCK_LAYERS=met3:met5
#   C  B + ASIC_CTS_RC_FACTORS=<res>:<cap>   (generateRCFactor output)
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd); INV=$(cd -- "$HERE/.." && pwd)
BASE=${1:?usage: cts_experiment.sh <base_stamp> <new_stamp> <tmux_tag> [VAR=VAL ...]}; NEW=${2:?new stamp}; TAG=${3:?tmux tag}; shift 3
SRC=$INV/runs/$BASE/checkpoints
[ -e "$SRC/03_place.enc.dat" ] || { echo "no $SRC/03_place.enc.dat" >&2; exit 1; }
[ -e "$INV/runs/$NEW/logs" ] && { echo "runs/$NEW already ran" >&2; exit 1; }
mkdir -p "$INV/runs/$NEW/checkpoints"
ln -sfn "$SRC/03_place.enc"     "$INV/runs/$NEW/checkpoints/03_place.enc"
ln -sfn "$SRC/03_place.enc.dat" "$INV/runs/$NEW/checkpoints/03_place.enc.dat"
echo "== seeded runs/$NEW/checkpoints/03_place.enc -> $SRC"
exec "$HERE/launch_from_knobs.sh" "$BASE" "$NEW" "$TAG" ASIC_PNR_FROM=04 ASIC_PNR_TO=04 ASIC_CTS_UPDATE_IO_LATENCY=0 "$@"
