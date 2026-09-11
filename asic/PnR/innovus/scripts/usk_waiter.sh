#!/usr/bin/env bash
# Watches the iter26 a-j base runs; when one has ended stage 05 (its tmux pane
# shows <TAG>_DONE=1 and flow.log* has 'Ending "Innovus"'), launches
# usk_rerun.sh on it once. Exits when all ten have been handled. 2026-09-09.
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd); INV=$(cd -- "$HERE/.." && pwd)
cd "$INV"
while true; do
  left=0
  for d in runs/20260908_iter26*_1v76; do
    b=$(basename "$d"); case "$b" in *_usk_*) continue;; esac
    t=$(echo "$b" | grep -oE 'iter26[a-z]?')
    n=$(echo "$b" | sed -E 's/_(p[0-9]+_1v76)$/_usk_\1/')
    [ -d "runs/$n/logs" ] && continue          # already relaunched
    f=$(ls -t "$d"/logs/flow.log "$d"/logs/flow.log[0-9]* 2>/dev/null | head -1)
    if [ -n "$f" ] && grep -q 'Ending "Innovus"' "$f" && tmux capture-pane -pt "$t" 2>/dev/null | grep -q "${t^^}_DONE=1" \
       && [ -e "$d/checkpoints/05_route_opt.enc" ]; then
      echo "$(date '+%F %T') $t ended stage 05 -> launching usk rerun"
      bash "$HERE/usk_rerun.sh" "$b" 2>&1 | grep -E '^== '
    else
      left=$((left+1))
    fi
  done
  [ "$left" -eq 0 ] && { echo "$(date '+%F %T') all base runs handled"; exit 0; }
  sleep 120
done
