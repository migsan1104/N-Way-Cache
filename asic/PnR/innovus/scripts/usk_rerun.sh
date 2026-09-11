#!/usr/bin/env bash
# Re-run STAGE 05 ONLY (route + post-route setup opt + hold opt) from a finished
# run's post-CTS checkpoint with useful skew ON in the post-route opts
# (ASIC_CTS_USEFUL_SKEW=1, ASIC_DRC_GATE=300 so a marginal gate does not stop the table; stage 04 is not re-run, so the tree is the base
# run's). 2026-09-09, user: "re run each one from the post cts checkpoint and do
# the whole stage 5 but now with setup opt with useful skew turned on".
# The new run dir is <base> with "_usk" inserted before "_p<period>" so the
# route_phases.py glob still matches; checkpoints/04_cts.enc(.dat) are symlinks
# to the base run's, everything else is written fresh.
#   usk_rerun.sh <base_stamp>
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd); INV=$(cd -- "$HERE/.." && pwd)
BASE=${1:?base stamp}
NEW=$(echo "$BASE" | sed -E 's/_(p[0-9]+_1v76)$/_usk_\1/')
[ "$NEW" != "$BASE" ] || { echo "cannot derive usk stamp from $BASE" >&2; exit 1; }
TAG=$(echo "$BASE" | grep -oE 'iter26[a-z]?')usk
SRC=$INV/runs/$BASE/checkpoints
[ -e "$SRC/04_cts.enc" ] || { echo "no $SRC/04_cts.enc" >&2; exit 1; }
mkdir -p "$INV/runs/$NEW/checkpoints"
ln -sfn "$SRC/04_cts.enc"     "$INV/runs/$NEW/checkpoints/04_cts.enc"
ln -sfn "$SRC/04_cts.enc.dat" "$INV/runs/$NEW/checkpoints/04_cts.enc.dat"
echo "== seeded runs/$NEW/checkpoints/04_cts.enc -> $SRC"
exec "$HERE/launch_from_knobs.sh" "$BASE" "$NEW" "$TAG" ASIC_PNR_FROM=05 ASIC_PNR_TO=05 ASIC_CTS_USEFUL_SKEW=1 ASIC_DRC_GATE=2000
