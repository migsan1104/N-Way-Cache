#!/usr/bin/env bash
# Run an OpenRAM generation + characterization job.
#
#   ./run_openram.sh <config.py>
#
# Intended to be launched inside tmux so it survives a disconnect:
#
#   tmux new-session -d -s <name> "<repo>/asic/openram/run_openram.sh <config.py>"
#   tmux ls                 # list
#   tmux attach -t <name>   # watch
#   (Ctrl-B then D to detach again)
#
# Why tmux and not just '&': a Genus run was lost on 2026-08-20 when its
# parent shell died with the session that started it. tmux's server
# daemonizes away from whatever launched it, so the job outlives the
# terminal, the SSH connection, and the CLI.
#
# Environment traps this script exists to encode (see asic/MACROS.md):
#   - /apps/anaconda/bin/python3 is REQUIRED; three pythons collide on this
#     server and the others lack OpenRAM's dependencies.
#   - PDK_ROOT must point at the WRITABLE assembled PDK (~/pdk_openram), not
#     the read-only server PDK it symlinks to.
#   - Characterization uses ngspice from OpenRAM's own conda env, not hspice
#     (the open_pdks sky130 models are ngspice dialect).
set -u

CFG="${1:?usage: run_openram.sh <config.py>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OR_PKG="$HOME/.local/lib/python3.9/site-packages/openram"
PY=/apps/anaconda/bin/python3

export PDK_ROOT="$HOME/pdk_openram"
export OPENRAM_HOME="$OR_PKG/compiler"
export OPENRAM_TECH="$OR_PKG/technology"

cd "$HERE" || exit 1

LOG="$HERE/$(basename "${CFG%.py}")_run.log"
echo "=== $(date '+%F %T') launching OpenRAM: $CFG" | tee "$LOG"
echo "=== python : $PY" | tee -a "$LOG"
echo "=== pdk    : $PDK_ROOT" | tee -a "$LOG"

"$PY" "$OR_PKG/sram_compiler.py" "$CFG" 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}

echo "=== $(date '+%F %T') exited rc=$RC" | tee -a "$LOG"

# Leave the pane open on failure so the error is readable after attaching.
if [ "$RC" -ne 0 ]; then
    echo "=== FAILED (rc=$RC). Pane held open; Ctrl-C or 'exit' to close." | tee -a "$LOG"
    sleep infinity
fi
