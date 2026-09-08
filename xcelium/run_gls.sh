#!/usr/bin/env bash
# run_gls.sh - gate-level simulation of the exported P&R netlist with SDF
# back-annotation, through the normal Test_Complete regression (2026-09-07).
#   ./run_gls.sh <pnr_run_stamp> [req_prob] [resp_prob]
# Modes (GLS_MODE): postlayout (default) = *_pnr_sim.v + SDF + timing models;
#        postsynth = the Genus mapped netlist the run was built from
#        (knobs.txt ASIC_NETLIST), +define+FUNCTIONAL cell models, no SDF.
# Knobs: GLS_HALF_PERIOD (ns, default 5 = the TB's 10 ns clock),
#        GLS_TIMING_CHECKS=1 to enable $setup/$hold checks (default off: the
#        TB drives inputs at the clock edge with no input delay, so checks on
#        port-fed flops fire regardless of design correctness - see the
#        golden.sdc 0.700 ns input contract), GLS_MTM=MAXIMUM|MINIMUM|TYPICAL.
# Only the ASSOC=4 DUT is the netlist (Cache_gls_wrap.sv); ASSOC is forced
# to 4 so the runner exercises just that DUT. PASS = the same banner as run.sh.
set -uo pipefail
STAMP="${1:?usage: run_gls.sh <pnr_run_stamp> [req_prob] [resp_prob]}"
CPU_REQ_PROB="${2:-1.0}"; CPU_RESP_PROB="${3:-$CPU_REQ_PROB}"
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
RUN=$REPO/asic/PnR/innovus/runs/$STAMP
MODE="${GLS_MODE:-postlayout}"
if [ "$MODE" = "postsynth" ]; then
  NET=$(grep -E '^ASIC_NETLIST=' "$RUN/knobs.txt" | head -1 | sed 's/^ASIC_NETLIST=//'); SDF=""
  [ -r "$NET" ] || { echo "ERROR: ASIC_NETLIST from $RUN/knobs.txt not readable: $NET" >&2; exit 1; }
elif [ "$MODE" = "postlayout_nosdf" ]; then
  # bisect step for a failing SDF run (GLS.md 2026-09-07 07:30): the post-layout
  # netlist (CTS, hold buffers, fillers) with the functional unit-delay models
  NET=$(ls "$RUN"/outputs/*_pnr_sim.v | head -1); SDF=""
  [ -r "$NET" ] || { echo "ERROR: no *_pnr_sim.v under $RUN/outputs" >&2; exit 1; }
else
  NET=$(ls "$RUN"/outputs/*_pnr_sim.v | head -1); SDF=$(ls "$RUN"/outputs/*_pnr.sdf | head -1)
  [ -r "$NET" ] && [ -r "$SDF" ] || { echo "ERROR: no *_pnr_sim.v / *_pnr.sdf under $RUN/outputs" >&2; exit 1; }
fi
PDKV=/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/verilog
# GLS.md step 0: the PDK library file does not compile as-is (lpflow_bleeder_1
# specify path on VPWR outside USE_POWER_PINS); use a copy without that cell.
GLSLIB=$HERE/gls_lib/sky130_fd_sc_hd_gls.v
if [ ! -s "$GLSLIB" ]; then mkdir -p "$HERE/gls_lib"
  awk 'BEGIN{skip=0} /^module sky130_fd_sc_hd__lpflow_bleeder_1\y/{skip=1} skip==0{print} /^endmodule/{if(skip)skip=0}' "$PDKV/sky130_fd_sc_hd.v" > "$GLSLIB"
fi
command -v xrun >/dev/null || { echo "ERROR: xrun not found (source /apps/settings)" >&2; exit 1; }
cd "$HERE"; mkdir -p logs
SCOPE="Test_Complete.GEN_ASSOC_SET[2].DUT.g_gate.u"   # Cache_gls_wrap generate block adds g_gate
SDFARGS=(); MODEDEF=()
if [ "$MODE" = "postsynth" ] || [ "$MODE" = "postlayout_nosdf" ]; then
  MODEDEF=(+define+FUNCTIONAL "+define+UNIT_DELAY=#1")   # sky130 functional models: no specify, `UNIT_DELAY gate delays
else
# SDF: annotated from inside Cache_gls_wrap.sv ($sdf_annotate on the netlist
# instance) - the -sdf_cmd route needs the scope as a string and Xcelium did
# not accept the generate-block path (SDFSNF "scope not found", 2026-09-07;
# before that a bare-keyword command file annotated nothing at all). Log:
# logs/gls_sdf_annotate.log. xmelab compiles the ASCII SDF on the fly.
  SDFARGS=(+define+GLS_SDF_FILE="\"$SDF\"" +define+GLS_SDF_MTM="\"${GLS_MTM:-MAXIMUM}\"" -sdf_verbose)
fi
TC=(); [ "${GLS_TIMING_CHECKS:-0}" = "1" ] || TC=(+notimingchecks)
TAG=${MODE}
# GLS filelist = the RTL filelist minus the plain macro model; the gls_lib copy
# (with the netlists' wmask1 port) replaces it. Cache.sv & co. stay for the four
# RTL DUTs the wrapper keeps.
grep -vE 'sram_1rw1r_32_256_8_sky130_sim\.v' filelist.f > logs/gls_filelist.f
HP=(); [ -n "${GLS_HALF_PERIOD:-}" ] && HP=(+define+GLS_HALF_PERIOD=$GLS_HALF_PERIOD)
# GLS_IO_LATENCY (ns): TB-side clock delayed by the signoff virtual-clock latency
# (io_vclk.txt latency_late for the SDF corner) - see the Test_Complete.sv comment.
[ -n "${GLS_IO_LATENCY:-}" ] && HP+=(+define+GLS_IO_LATENCY=$GLS_IO_LATENCY)
# GLS_MEM_LATENCY (ns): RAM_ID alone on a clock delayed by this much (memory-port flops sit ~7.6 ns deep).
[ -n "${GLS_MEM_LATENCY:-}" ] && HP+=(+define+GLS_MEM_LATENCY=$GLS_MEM_LATENCY)
echo "== GLS mode=$MODE netlist=$NET"; echo "== GLS: sdf ${SDF:-none} scope $SCOPE mtm ${GLS_MTM:-MAXIMUM} checks=${GLS_TIMING_CHECKS:-0} half_period=${GLS_HALF_PERIOD:-5} io_latency=${GLS_IO_LATENCY:-0} mem_latency=${GLS_MEM_LATENCY:-0}"
xrun -64bit -sv -timescale 1ns/1ps \
  +define+GLS "${MODEDEF[@]}" "${HP[@]}" "${TC[@]}" \
  -f logs/gls_filelist.f "$HERE/gls_lib/sram_1rw1r_32_256_8_sky130_gls.v" \
  "$PDKV/primitives.v" "$GLSLIB" \
  "$NET" ../Verification/Cache_gls_wrap.sv \
  "${SDFARGS[@]}" \
  -top Test_Complete \
  -defparam "Test_Complete.ASSOC=4" \
  -defparam "Test_Complete.CPU_REQ_VALID_PROBABILITY=$CPU_REQ_PROB" \
  -defparam "Test_Complete.CPU_RESP_READY_PROBABILITY=$CPU_RESP_PROB" \
  -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_1=0" -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_2=0" \
  -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_4=0" -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_8=0" \
  -defparam "Test_Complete.TOGGLE_ASSOC_DEBUG_16=0" \
  -xmlibdirname xcelium_gls_$TAG.d -l logs/xrun_gls_$TAG.log
st=$?
if grep -q "Congrats all associativity tests passed" logs/xrun_gls_$TAG.log; then echo "GLS $MODE PASSED"; exit 0; fi
echo "GLS $MODE FAILED (xrun exit $st) - see logs/xrun_gls_$TAG.log"; exit 1
