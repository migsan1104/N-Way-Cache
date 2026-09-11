#!/usr/bin/env bash
# legalize_cascade.sh <run_stamp> <src_ckpt> <drc_rpt> [tmux_tag]  (2026-09-06)
# Drive a routed checkpoint with a verify_drc report to 0 markers with the
# report-driven scripts, each in its own innovus session:
#   legalize_targeted.tcl  (rip up the marker nets, reroute them alone, eco passes)
#   legalize_fixup.tcl     (windowed rip-up around every remaining signal marker)
#   legalize_pgfix.tcl     (met5 via pads / VSS stub)   } only if PG markers remain
#   legalize_pgfix2.tcl    (dangling VSS via by object) }
# Stops as soon as a step reports 0. Prints "CASCADE FINAL verify_drc = N ckpt=X".
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INV=$(cd -- "$HERE/.." && pwd)
STAMP=${1:?stamp}; SRC=${2:?src ckpt}; RPT=${3:?drc report}; TAG=${4:-}
RUN=$INV/runs/$STAMP; LEG=$RUN/reports/legalize
if [ -n "$TAG" ]; then
  tmux has-session -t "$TAG" 2>/dev/null && { echo "tmux $TAG exists" >&2; exit 1; }
  tmux new-session -d -s "$TAG" -x 200 -y 50 "bash -lc '$HERE/legalize_cascade.sh $STAMP $SRC $RPT 2>&1 | tee -a $RUN/logs/legalize_cascade_sh.log; echo ${TAG^^}_DONE=1; exec bash'"
  echo "== tmux $TAG started; log $RUN/logs/legalize_cascade_sh.log"; exit 0
fi
[ "${RPT#/}" = "$RPT" ] && RPT=$RUN/$RPT
step() {  # step <tcl> <src> <rpt> -> sets N, CKPT
  local tcl=$1 src=$2 rpt=$3
  echo "== cascade: $tcl from $src report $(basename $rpt) ($(date '+%T'))"
  ASIC_LEGALIZE_TCL=$tcl ASIC_LEGALIZE_SRC=$src ASIC_LEGALIZE_DRC_RPT=$rpt ASIC_LEGALIZE_CHAIN=0 "$HERE/legalize_route.sh" "$STAMP" | grep -E '^== legalize_route result|LEGALQ (after|LEGAL FINAL|PG|DELETE|vias)'
  case $tcl in
    legalize_targeted.tcl) CKPT=05_legal_targeted.enc; RES=targeted.txt;;
    legalize_fixup.tcl)    CKPT=05_legal_fixup.enc;    RES=fixup.txt;;
    legalize_pgfix.tcl)    CKPT=05_legal_pgfix.enc;    RES=pgfix.txt;;
    legalize_pgfix2.tcl)   CKPT=05_legal_pgfix2.enc;   RES=pgfix2.txt;;
  esac
  N=$(grep -aoE 'LEGAL FINAL verify_drc = [0-9]+' "$LEG/$RES" | tail -1 | grep -oE '[0-9]+$')
}
newest_rpt() { ls -t "$LEG"/drc_after_*.rpt "$LEG"/drc_best.rpt 2>/dev/null | head -1; }
# no -q inside pipelines: with pipefail an early exit of the last grep gives
# the first one SIGPIPE (141) and the test reads as false (2026-09-06)
has_pg()  { [ "$(grep -cE '^(MINWIDTH|NSMETAL).*Special Wire' "$1")" -gt 0 ]; }
has_sig() { [ "$(grep -E '^[A-Z]+:' "$1" | grep -vcE 'Special Wire')" -gt 0 ]; }
step legalize_targeted.tcl "$SRC" "$RPT"
if [ "${N:-1}" != 0 ]; then R=$(newest_rpt); has_sig "$R" && step legalize_fixup.tcl "$CKPT" "$R"; fi
if [ "${N:-1}" != 0 ]; then R=$(newest_rpt); has_pg "$R" && step legalize_pgfix.tcl "$CKPT" "$R"; fi
if [ "${N:-1}" != 0 ]; then R=$(newest_rpt); has_pg "$R" && step legalize_pgfix2.tcl "$CKPT" "$R"; fi
echo "CASCADE FINAL verify_drc = ${N:-?} ckpt=$CKPT ($(date '+%T'))"
