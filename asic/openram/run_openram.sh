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

# ngspice-41 must come FIRST on PATH. OpenRAM's bundled build is revision 26
# (2014): on an identical 150 ns stimulus, 41 finished in 24.7 min while 26 ran
# 7 h 19 m without finishing. 26 predates the KLU solver and ignores the
# num_threads=3 that .spiceinit requests. Pair this with use_conda=False in the
# config - while use_conda is true, find_exe() searches CONDA_HOME/bin before
# $PATH and the bundled 26 wins regardless of what is set here.
NG41="$HOME/ngspice41env/bin"
if [ -x "$NG41/ngspice" ]; then
    export PATH="$NG41:$PATH"
else
    echo "WARNING: ngspice-41 not found at $NG41 - falling back to the bundled" \
         "revision 26, which is ~18x slower and may never finish." >&2
fi

cd "$HERE" || exit 1

# ngspice reads .spiceinit from the directory it RUNS FROM - which is here,
# because of the cd above. OpenRAM writes its own copy into /tmp/openram_*_temp/
# on the assumption that ngspice runs there, so without a copy in this directory
# every setting in it is dropped with NO error message: num_threads (falls back
# to one core), ngbehavior=hsa, and ng_nomodcheck. Measured cost of losing them
# on an identical 150 ns stimulus: 24.7 min becomes >6.5 h. Refuse to launch
# rather than repeat that - a 15x slowdown with no diagnostic is worse than a
# hard stop.
if [ ! -f "$HERE/.spiceinit" ]; then
    echo "ERROR: $HERE/.spiceinit is missing." >&2
    echo "       ngspice would run single-threaded with model checking on," >&2
    echo "       roughly 15x slower, and would not tell you." >&2
    exit 1
fi

LOG="$HERE/$(basename "${CFG%.py}")_run.log"
echo "=== $(date '+%F %T') launching OpenRAM: $CFG" | tee "$LOG"
echo "=== python : $PY" | tee -a "$LOG"
echo "=== pdk    : $PDK_ROOT" | tee -a "$LOG"

# -v -v: verbose_level 2 - logs every feasible/min-period/sweep/setup-hold step.
# Without it the log stops at "LIB: Characterizing..." for the whole run
# (2026-08-24..26: 47 h with no progress line).
"$PY" "$OR_PKG/sram_compiler.py" -v -v "$CFG" 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}

echo "=== $(date '+%F %T') exited rc=$RC" | tee -a "$LOG"

# Leave the pane open on failure so the error is readable after attaching.
if [ "$RC" -ne 0 ]; then
    echo "=== FAILED (rc=$RC). Pane held open; Ctrl-C or 'exit' to close." | tee -a "$LOG"
    sleep infinity
fi
