#!/usr/bin/env bash
set -uo pipefail
# NIGHT WATCH (2026-09-02): unattended trigger for winner_chain.sh.
# Polls each listed run's stage-05 DRC gate line in logs/flow.log; a raw
# route that beats BEAT (default 706, fp_iter7's baseline) gets the winner
# chain launched in its own tmux session (chain_<tag>). Runs that don't beat
# it are recorded and left for morning triage. Exits when every run is
# adjudicated. See DRC.md "Iteration 16" for the decision tree.
#
# Usage: night_watch.sh   (defaults below)   — run it inside tmux.
REPO=/ecel/UFAD/miguel.sanchez1/Cache
RUNS=$REPO/asic/PnR/innovus/runs
SCR=$REPO/asic/PnR/innovus/scripts
BEAT=${BEAT:-706}
LOG=$RUNS/night_watch_$(date +%Y%m%d_%H%M).log
# stamp:tag — tag names the chain's tmux session (chain_<tag>)
JOBS=${JOBS:-"20260902_iter16_e35_fp16_die2780:16 20260902_iter16b_e35_fp16_die2900:16b 20260901_iter15_e35_fp15_damp:15"}

note() { echo "$(date '+%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }
declare -A DONE
note "night_watch up: BEAT=$BEAT jobs=$JOBS"

deadline=$(( $(date +%s) + 36*3600 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    pending=0
    for jt in $JOBS; do
        stamp=${jt%%:*}; tag=${jt##*:}
        [ -n "${DONE[$stamp]:-}" ] && continue
        f=$RUNS/$stamp/logs/flow.log
        if [ ! -f "$f" ]; then pending=1; continue; fi
        # pnr_note is a Tcl puts: it reaches the tmux pane, NOT flow.log
        # (found 2026-09-03: iter16 gated at 123 and nothing fired). Read
        # the pane (session iter$tag) first, flow.log as a fallback.
        line=$( { tmux capture-pane -p -t "iter$tag" -S -20000 2>/dev/null; cat "$f"; } \
                | grep -aoE 'DRC GATE FAILED: [0-9]+|DRC gate passed: [0-9]+' | tail -1)
        if [ -z "$line" ]; then
            # flow died without reaching the gate? innovus gone + no gate line
            if ! pgrep -f "runs/$stamp" >/dev/null 2>&1; then
                DONE[$stamp]=died
                note "$stamp: innovus exited with NO gate line - flow died pre-route, judge log by hand"
                continue
            fi
            pending=1; continue
        fi
        n=$(grep -oE '[0-9]+' <<<"$line" | tail -1)
        DONE[$stamp]=$n
        note "$stamp gate: verify_drc=$n"
        if [ "$n" -lt "$BEAT" ]; then
            note "$stamp BEATS $BEAT -> launching winner_chain (tmux chain_$tag)"
            tmux new-session -d -s "chain_$tag" \
                "bash -lc '$SCR/winner_chain.sh $stamp 2>&1 | tee -a $RUNS/$stamp/logs/winner_chain_sh.log; echo CHAIN_${tag}_EXIT=\$?; sleep 86400'" \
                && note "chain_$tag launched" || note "chain_$tag tmux launch FAILED"
        else
            note "$stamp does not beat $BEAT - no chain, morning triage"
        fi
    done
    [ "$pending" = 0 ] && { note "all runs adjudicated - night_watch exiting"; exit 0; }
    sleep 300
done
note "36h deadline hit with runs still pending - exiting"
