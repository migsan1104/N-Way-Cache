#!/usr/bin/env bash
set -euo pipefail
# Build the sky130A QRC techfile from sky130A.ict with Cadence Techgen.
#
#   bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
#             <repo>/asic/signoff/quantus/run_techgen.sh [corner]'
#
# corner = nom (default). min/max are the same ICT with the dielectric
# thickness/k scaled the way OpenRCX's sky130 min/max rule files do - not
# built until nom is validated (README.md).
#
# MODE=cell (default): "Techgen -cell" - cell-level cap models only, which is
# all a DEF/Innovus/Tempus flow uses; minutes. MODE=simulation: the full
# field-solver run (adds transistor-level models, hours; use -multi_cpu).
#
# Output: techfiles/sky130A_<corner>.tch + techgen_<corner>.log in this dir.
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CORNER="${1:-nom}"
ICT="$HERE/sky130A.ict"
OUT="$HERE/techfiles"
mkdir -p "$OUT"
command -v Techgen >/dev/null || { echo "ERROR: Techgen not on PATH (source /apps/settings and asic/signoff/env.sh)" >&2; exit 1; }
[ -r "$ICT" ] || { echo "ERROR: $ICT missing" >&2; exit 1; }

# Techgen writes into the cwd; keep it out of the tree.
WORK="$HERE/work_$CORNER"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"
echo "Techgen: $ICT -> $OUT/sky130A_$CORNER.tch"
MODE="${MODE:-cell}"
CPUS="${CPUS:-8}"
case "$MODE" in
    cell)
        # Techgen -cell is a two-step RCgen flow: -plan parses the ICT and
        # writes the parallel job scripts into the cwd; -parallel -autoconcat
        # runs them and concatenates the models into the techfile (in cwd).
        Techgen -cell -plan -multi_cpu "$CPUS" "$ICT" 2>&1 | tee "$HERE/techgen_$CORNER.log"
        Techgen -cell -parallel -autoconcat "$ICT" "sky130A_$CORNER.tch" 2>&1 | tee -a "$HERE/techgen_$CORNER.log"
        cp -f "sky130A_$CORNER.tch" "$OUT/sky130A_$CORNER.tch"
        ;;
    simulation) Techgen -simulation -multi_cpu "$CPUS" "$ICT" "$OUT/sky130A_$CORNER.tch" 2>&1 | tee "$HERE/techgen_$CORNER.log" ;;
    *) echo "ERROR: MODE must be cell or simulation" >&2; exit 1 ;;
esac
ls -l "$OUT/sky130A_$CORNER.tch"
