#!/usr/bin/env bash
set -euo pipefail
# Pegasus DRC on a P&R run's streamed GDS.
#
#   bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
#             <repo>/asic/signoff/pegasus/run_pegasus_drc.sh [gds]'
#
# gds defaults to $SIGNOFF_PNR_DIR/outputs/*.gds. Results in
# $SIGNOFF_RESULTS/pegasus_drc/.
#
# DRAFT 2026-09-01, UNTESTED: the Pegasus Verification binary is NOT installed
# on this server (see Pegasus.md — /apps/cds/pegasus231 is Pegasus DFM, a
# different product). The pegasus command-line flags below were written from
# memory and must be verified against `pegasus -help` once IT installs it.
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDS="${1:-$(ls "$SIGNOFF_PNR_DIR"/outputs/*.gds 2>/dev/null | head -1)}"
[ -r "${GDS:-}" ] || { echo "ERROR: no GDS (run stage 06 export, or pass a path)" >&2; exit 1; }

# Pegasus Verification lives in its own release dir, not $PEGASUS_HOME (DFM).
# Set PEGASUS_VERIFY_HOME in env.sh when IT installs it.
PEGASUS_BIN=""
for c in "${PEGASUS_VERIFY_HOME:-}/bin/pegasus" "${PEGASUS_VERIFY_HOME:-}/tools.lnx86/bin/pegasus"; do
    [ -x "$c" ] && PEGASUS_BIN="$c" && break
done
[ -n "$PEGASUS_BIN" ] || PEGASUS_BIN=$(command -v pegasus || true)
[ -n "$PEGASUS_BIN" ] || {
    echo "ERROR: no pegasus DRC/LVS executable on this system." >&2
    echo "  /apps/cds/pegasus231 is Pegasus DFM (LPA/CMP/CAA), not Pegasus Verification." >&2
    echo "  See $HERE/Pegasus.md — the install is an open IT request." >&2
    exit 2
}

OUT="$SIGNOFF_RESULTS/pegasus_drc"; mkdir -p "$OUT"

# Top cell = the Innovus design name, not the GDS basename (the vacuous-run
# lesson from drc/run_drc.sh). Take it from the exported netlist.
NETLIST=$(ls "$SIGNOFF_PNR_DIR"/outputs/*.v 2>/dev/null | head -1)
[ -r "${NETLIST:-}" ] || { echo "ERROR: no netlist next to the GDS to discover the top cell" >&2; exit 1; }
TOP=$(grep -m1 -oE '^module +[A-Za-z0-9_]+' "$NETLIST" | awk '{print $2}')
[ -n "$TOP" ] || { echo "ERROR: could not parse top module from $NETLIST" >&2; exit 1; }

# The staged deck hardcodes the OSU demo's results_db name — rewrite it into
# a run-local copy so decks/ stays pristine.
DECK="$OUT/sky130_drcRules.pvl"
sed "s|^results_db .*|results_db -drc $OUT/drc_errors.ascii -ascii|" \
    "$HERE/decks/sky130_drcRules.pvl" > "$DECK"

echo "pegasus DRC: $GDS (top $TOP) -> $OUT"
"$PEGASUS_BIN" -drc -dp 8 -license_dp_continue \
    -gds "$GDS" -top_cell "$TOP" "$DECK" > "$OUT/pegasus.log" 2>&1 || {
    echo "ERROR: pegasus exited nonzero — read $OUT/pegasus.log (flags unverified, see header)" >&2
    exit 1
}
grep -icE 'error|violation' "$OUT/drc_errors.ascii" 2>/dev/null | \
    xargs -I{} echo "raw error-ish lines in results db: {}"
echo "results: $OUT/drc_errors.ascii  log: $OUT/pegasus.log"
