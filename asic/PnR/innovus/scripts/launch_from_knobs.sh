#!/usr/bin/env bash
# Relaunch an Innovus flow from a previous run's knobs.txt, changing only
# what is passed on the command line (2026-09-05, written for iter18).
#
#   launch_from_knobs.sh <base_run_stamp> <new_stamp> <tmux_tag> [VAR=VAL ...]
#
# Every ASIC_* line of runs/<base>/knobs.txt is re-exported verbatim (so the
# new run is a true one-variable experiment against the base), then the
# overrides are applied, ASIC_PNR_RUN_STAMP is set to <new_stamp>, and
# innovus runs scripts/run_innovus.tcl in tmux session <tmux_tag> with
# -log logs/flow (flow.log, same as every iteration since 16). The pane
# ends with <TAG>_DONE=1 for monitors. The launch line is written to
# runs/<new_stamp>/launch.sh for the record.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INV=$(cd -- "$HERE/.." && pwd)
BASE=${1:?usage: launch_from_knobs.sh <base_stamp> <new_stamp> <tmux_tag> [VAR=VAL ...]}
NEW=${2:?new stamp}; TAG=${3:?tmux tag}; shift 3
K=$INV/runs/$BASE/knobs.txt
[ -r "$K" ] || { echo "no $K" >&2; exit 1; }
[ -e "$INV/runs/$NEW/logs" ] && { echo "runs/$NEW already has logs (a run)" >&2; exit 1; }   # a seeded checkpoints/ dir (cts_experiment.sh) is allowed
tmux has-session -t "$TAG" 2>/dev/null && { echo "tmux session $TAG exists" >&2; exit 1; }
mkdir -p "$INV/runs/$NEW/logs"
L=$INV/runs/$NEW/launch.sh
{
  echo "#!/usr/bin/env bash"
  echo "# generated $(date '+%F %T') by launch_from_knobs.sh from runs/$BASE/knobs.txt"
  echo "source /apps/settings"
  echo "source $INV/env.sh"
  # first block of knobs only (a knobs.txt gains a second header block when a
  # later session, e.g. classify_drc, restores the DB with its own env)
  awk '/^#/{if(seen)exit; seen=1; next} /^ASIC_/{print "export " $0}' "$K" \
    | grep -v '^export ASIC_PNR_RUN_STAMP='
  for o in "$@"; do echo "export \"$o\""; done
  echo "export ASIC_PNR_RUN_STAMP=$NEW"
  echo "cd $INV/runs/$NEW"
  echo "innovus -no_gui -files $HERE/run_innovus.tcl -log logs/flow"
  echo "echo ${TAG^^}_DONE=1"
} > "$L"
chmod +x "$L"
echo "== launch.sh for $NEW:"; sed 's/^/   /' "$L"
tmux new-session -d -s "$TAG" -x 200 -y 50 "bash -lc '$L; exec bash'"
echo "== tmux $TAG started; log $INV/runs/$NEW/logs/flow.log"
