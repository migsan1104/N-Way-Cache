#!/usr/bin/env bash
# legalize_route.sh <run_stamp> [tmux_tag] - 2026-09-06 (iter19).
# Unattended: replay the run's knobs.txt env (like launch_from_knobs.sh),
# run legalize_route.tcl on its stage-05 route (met4 guidance blockages over
# the macros + incremental route, then post-route setup opt), and if the
# result is clean enough hand the checkpoint to winner_chain.sh
# (hold opt + eco passes + antenna + export + KLayout/LVS/Tempus).
#   ASIC_LEGALIZE_SRC      (05_route.enc)   ASIC_LEGALIZE_OPT_MAX (20)
#   ASIC_LEGALIZE_TCL      legalize_route.tcl (default) | legalize_targeted.tcl
#   ASIC_LEGALIZE_CHAIN=0  stop after the innovus session
#   ASIC_LEGALIZE_CHAIN_SRC checkpoint the chain starts from (05_legal_opt.enc)
#   ASIC_LEGALIZE_CHAIN_MAX markers allowed to still start the chain (10):
#                          its eco loop is plateau-guarded and exits 2 if
#                          the route never reaches 0.
# Runs in the foreground; wrap in tmux yourself or pass a tmux tag as $2.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INV=$(cd -- "$HERE/.." && pwd)
STAMP=${1:?usage: legalize_route.sh <run_stamp> [tmux_tag]}
TAG=${2:-}
RUN=$INV/runs/$STAMP
[ -r "$RUN/knobs.txt" ] || { echo "no $RUN/knobs.txt" >&2; exit 1; }
if [ -n "$TAG" ]; then
  tmux has-session -t "$TAG" 2>/dev/null && { echo "tmux session $TAG exists" >&2; exit 1; }
  # tmux starts the command from the tmux SERVER's environment, so the
  # ASIC_LEGALIZE_* knobs of this shell have to be passed explicitly
  # (2026-09-06: attempt 3 silently reran attempt 2 without this).
  ENVS=$(env | grep -E '^ASIC_LEGALIZE_' | sed 's/^/export /; s/$/;/' | tr '\n' ' ')
  echo "== knobs: ${ENVS:-none}"
  tmux new-session -d -s "$TAG" -x 200 -y 50 "bash -lc '$ENVS $HERE/legalize_route.sh $STAMP; echo ${TAG^^}_DONE=1; exec bash'"
  echo "== tmux $TAG started; log $RUN/logs/legalize_route.log"; exit 0
fi
source /apps/settings
source "$INV/env.sh"
# first knobs block only (later sessions append their own header blocks)
eval "$(awk '/^#/{if(seen)exit; seen=1; next} /^ASIC_/{print "export " $0}' "$RUN/knobs.txt" | grep -v '^export ASIC_PNR_RUN_STAMP=')"
export ASIC_PNR_RUN_STAMP=$STAMP
mkdir -p "$RUN/logs"
echo "== legalize_route: $STAMP from ${ASIC_LEGALIZE_SRC:-05_route.enc} ($(date '+%F %T'))"
TCL=${ASIC_LEGALIZE_TCL:-legalize_route.tcl}      # or legalize_targeted.tcl (attempt 4)
case "$TCL" in legalize_targeted.tcl) RES=targeted.txt;; *) RES=route_fix.txt;; esac
( cd "$RUN" && innovus -no_gui -files "$HERE/$TCL" -log logs/${TCL%.tcl} )
F=$(grep -aoE 'LEGAL FINAL verify_drc = [0-9]+' "$RUN/reports/legalize/$RES" 2>/dev/null | tail -1 | grep -oE '[0-9]+$')   # innovus -log does not capture puts; the txt does
echo "== legalize_route result: verify_drc = ${F:-?} ($(date '+%F %T'))"
grep -a LEGALQ "$RUN/reports/legalize/$RES" 2>/dev/null
[ -n "${F:-}" ] || exit 1
[ "${ASIC_LEGALIZE_CHAIN:-1}" = "1" ] || exit 0
[ "$F" -le "${ASIC_LEGALIZE_CHAIN_MAX:-10}" ] || { echo "== chain NOT started ($F markers)"; exit 2; }
CSRC=${ASIC_LEGALIZE_CHAIN_SRC:-05_legal_opt.enc}
[ -r "$RUN/checkpoints/$CSRC" ] || { echo "== chain NOT started (no $CSRC)"; exit 2; }
echo "== starting winner_chain.sh from $CSRC"
ASIC_CHAIN_SRC=$CSRC "$HERE/winner_chain.sh" "$STAMP" 2>&1 | tee "$RUN/logs/legalize_chain_sh.log"
