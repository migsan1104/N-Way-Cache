#!/usr/bin/env bash
set -uo pipefail
# Headless Innovus layout snapshot: dumpToGIF needs a GUI window, so run the
# GUI under Xvfb. (floorplan.gif and the iter*_*.gif gallery in ../floorplans/
# were made this way, 2026-08-30.)
#
#   ./snap_floorplan.sh <checkpoint.enc(.dat)> <out.gif> [TOP]
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CKPT=${1:?checkpoint}; OUT=${2:?out.gif}
TOP=${3:-Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1}
[[ $CKPT == *.dat ]] || CKPT=$CKPT.dat
T=$(mktemp --suffix=.tcl)
printf 'restoreDesign %s %s\nwin\nfit\ndumpToGIF %s\nexit\n' "$CKPT" "$TOP" "$OUT" > "$T"
source /apps/settings
xvfb-run -a -s '-screen 0 1400x1400x24' innovus -win -files "$T" -log /tmp/snap_fp_$$
rm -f "$T"; ls -la "$OUT"
