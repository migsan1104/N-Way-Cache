#!/usr/bin/env bash
set -uo pipefail
# WINNER-DAY CHAIN (2026-09-02, UNTESTED until a winner exists): take a run
# whose RAW ROUTE verified at/near zero and drive it to signed-off, in order:
#   hold-only opt + plateau-guarded eco passes  (the armC recipe, generalized)
#   -> antenna ECO (diode insertion)            (antenna_eco.tcl)
#   -> stage 06 export                          (fill + GDS + SDCs)
#   -> KLayout BEOL DRC + black-box LVS + Tempus (sta.tcl, vclk model)
# Usage:
#   bash -lc 'scripts/winner_chain.sh <RUN_STAMP>'
# Stops at the first gate that fails; every step logs into the run dir.
STAMP="${1:?usage: winner_chain.sh <run_stamp>}"
REPO=/ecel/UFAD/miguel.sanchez1/Cache
RUN=$REPO/asic/PnR/innovus/runs/$STAMP
SCR=$REPO/asic/PnR/innovus/scripts
[ -d "$RUN" ] || { echo "no run dir $RUN"; exit 1; }
source /apps/settings
source $REPO/asic/PnR/innovus/env.sh
# Without the stamp pinned, innovus_config.tcl mints a NEW timestamped run dir
# and pnr_restore_stage finds no database (its own error message names this
# trap). Pin it for EVERY innovus session below, and carry the Quantus/derate
# knobs the arms ran with so restored corners match the route's.
export ASIC_PNR_RUN_STAMP="$STAMP"
export ASIC_QRC_TECH="${ASIC_QRC_TECH:-$REPO/asic/signoff/quantus/techfiles/sky130A_nom.tch}"
export ASIC_SRAM_MACRO_DERATE="${ASIC_SRAM_MACRO_DERATE:-1.5}"
export ASIC_MACRO_DERATE_EARLY="${ASIC_MACRO_DERATE_EARLY:-0.67}"
# Campaign setup corner (MACROS.md "Run 2 sign-off corner", run_v3.sh):
# ss_n40C_1v76 cells + the x1.5 macro derate above. Without this, sta.tcl
# (Tempus) falls back to project_config.tcl's ss_100C_1v60 - which is what
# every Tempus run before 2026-09-03 20:40 silently did, and why armC's
# Innovus-vs-Tempus latency (2.961 vs 4.834) never reconciled. Restored
# Innovus checkpoints keep the MMMC they were built with; this affects the
# Tempus step and any fresh-MMMC session.
export ASIC_SIGNOFF_LIB="${ASIC_SIGNOFF_LIB:-/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_n40C_1v76.lib}"
[ -r "$ASIC_SIGNOFF_LIB" ] || { echo "ASIC_SIGNOFF_LIB not readable: $ASIC_SIGNOFF_LIB"; exit 1; }

# ASIC_CHAIN_SRC: checkpoint the chain starts from (default: the raw stage-05
# route). iter16b 2026-09-03: the legalize session (legalize_init/fix.tcl)
# fixed placement on top of 05_route_opt.enc and saved 05_legal_*.enc; the
# chain re-runs from there so the whole hold/eco/antenna/export/signoff
# sequence is still the one documented path to a signed-off package.
export ASIC_CHAIN_SRC="${ASIC_CHAIN_SRC:-05_route.enc}"
cat > "$RUN/chain.tcl" <<'EOT'
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
pnr_restore_stage [config_env ASIC_CHAIN_SRC 05_route.enc]
# Placement-legality gate (2026-09-03): a chain that plateaus on an illegal
# placement wastes the eco passes - ecoRoute cannot move cells. Report only;
# the region/fence section is soft guides (way0-3/hub) and always non-zero.
checkPlace [pnr_rpt chain checkplace_start.rpt]
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
# Match the signoff I/O model BEFORE hold fixing (armC lesson 2026-09-03:
# under golden.sdc's ideal-edge I/O reference the hold opt inserted 715
# delay cells that Tempus's latency-matched view proved unnecessary, and
# they cost reg2reg setup +0.699 -> -1.468). io_vclk.tcl = same block
# sta.tcl uses; io_vclk.txt lands in reports/chain/.
set _vclk_out [file dirname [pnr_rpt chain io_vclk.txt]]
set io_vclk_applied 0
if {[catch {source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/io_vclk.tcl} _m]} {
    pnr_note "CHAIN io_vclk FAILED ($_m) - hold opt proceeds under the raw SDC (armC-style padding expected)"
}
pnr_note "CHAIN io_vclk applied = $io_vclk_applied"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt chain hold_before_fix.rpt]}
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true
optDesign -postRoute -hold
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt chain reg2reg_after_hold.rpt]}
set prev 999999999
for {set p 1} {$p <= 6} {incr p} {
    clearDrc
    verify_drc -limit 100000 -report [pnr_rpt chain drc_pass${p}.rpt]
    set n [llength [dbGet -e top.markers]]
    pnr_note "CHAIN pass $p: verify_drc = $n"
    if {$n == 0} { break }
    if {$n >= $prev} { pnr_note "CHAIN PLATEAU: $n >= $prev"; break }
    set prev $n
    saveDesign [pnr_ckpt 05_chain_pass${p}.enc]
    if {[catch {ecoRoute -target} _m]} { pnr_note "CHAIN ecoRoute -target: $_m"; break }
}
catch {optDesign -postRoute -hold}
clearDrc
verify_drc -limit 100000 -report [pnr_rpt chain drc_holdclean.rpt]
set n [llength [dbGet -e top.markers]]
pnr_note "CHAIN HOLDCLEAN verify_drc = $n"
saveDesign [pnr_ckpt 05_route_opt.enc]
if {$n != 0} { pnr_note "CHAIN STOP: not clean ($n)"; exit 2 }
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/antenna_eco.tcl
EOT
# antenna_eco.tcl ends with its own exit; export runs in a fresh session so a
# clean-but-antenna-dirty verdict still leaves judgment to the log reader.
# ASIC_CHAIN_FROM=export skips steps 1+2 and exports ASIC_EXPORT_SRC (default
# 05_antenna_clean.enc) directly - for a checkpoint already judged DRC 0 +
# antenna 0 (iter16b 05_route_opt.enc, 2026-09-04).
EXPORT_SRC="${ASIC_EXPORT_SRC:-05_antenna_clean.enc}"
if [ "${ASIC_CHAIN_FROM:-}" = "export" ]; then
  [ -r "$RUN/checkpoints/$EXPORT_SRC" ] || { echo "no checkpoint $RUN/checkpoints/$EXPORT_SRC"; exit 1; }
  echo "== CHAIN steps 1+2 skipped (ASIC_CHAIN_FROM=export, src=$EXPORT_SRC) =="
else
echo "== CHAIN step 1+2: hold-only + eco + antenna (innovus) =="
( cd "$RUN" && innovus -no_gui -files chain.tcl -log logs/chain )
grep -aE 'CHAIN (pass|PLATEAU|HOLDCLEAN|STOP)|ANTENNA (pass|PLATEAU|ECO FINAL)' "$RUN/logs/chain.log" | tail -8
grep -aq 'CHAIN STOP' "$RUN/logs/chain.log" && { echo "CHAIN halted: route not clean"; exit 2; }
AF=$(ls -t "$RUN"/reports/antenna_eco/antenna_final.rpt 2>/dev/null | head -1)
if grep -aq 'No Violations Found' "$AF" 2>/dev/null; then AV=0; else
AV=$(grep -aoE 'Total number of process antenna violations: *[0-9]+' "$AF" 2>/dev/null | grep -oE '[0-9]+$' || echo "?"); fi
DV=$(grep -aoE 'ANTENNA ECO FINAL: verify_drc = [0-9]+' "$RUN/logs/chain.log" | grep -oE '[0-9]+$' || echo "?")
echo "post-antenna: antenna=$AV drc=$DV (both must be 0 to proceed)"
[ "$AV" = "0" ] && [ "$DV" = "0" ] || { echo "CHAIN halted before export - judge reports"; exit 3; }
fi

echo "== CHAIN step 3: export ($EXPORT_SRC) =="
( cd "$RUN" && ASIC_PNR_RUN_STAMP=$STAMP ASIC_ANTENNA_SRC=$EXPORT_SRC \
  innovus -no_gui -files <(echo "source $SCR/innovus_config.tcl
pnr_restore_stage $EXPORT_SRC
source $SCR/06_export.tcl") -log logs/chain_export )

echo "== CHAIN step 4: signoff triplet =="
export SIGNOFF_PNR_STAMP=$STAMP
source $REPO/asic/signoff/env.sh
O=$SIGNOFF_RESULTS/klayout_drc; mkdir -p "$O"
GDS=$(ls "$RUN"/outputs/*.gds | head -1)
TOPC=$(grep -m1 -oE '^module +[A-Za-z0-9_]+' "$RUN"/outputs/*_pnr.v | awk '{print $2}' | head -1)
PATH=$HOME/.local/bin:$PATH klayout -b -r /apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.tech/klayout/drc/sky130A_mr.drc \
  -rd input="$GDS" -rd top_cell="$TOPC" -rd report="$O/drc.lyrdb" -rd beol=true -rd feol=false -rd thr=16 > "$O/klayout.log" 2>&1
echo "klayout items: $(grep -c '<item>' "$O/drc.lyrdb" 2>/dev/null) (classify vs macro boxes before judging)"
$REPO/asic/signoff/lvs/run_lvs_bb.sh "$GDS" "$(ls "$RUN"/outputs/*_pnr_lvs.v "$RUN"/outputs/*_pnr.v 2>/dev/null | head -1)"   # prefer the PG+physical netlist (06_export netlist-lvs step)
( cd $REPO/asic/signoff/tempus && tempus -no_gui -files sta.tcl -log "$SIGNOFF_RESULTS/tempus/tempus_chain" )
echo "== CHAIN COMPLETE: results under $SIGNOFF_RESULTS =="
