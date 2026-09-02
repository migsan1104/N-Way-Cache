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

cat > "$RUN/chain.tcl" <<'EOT'
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
pnr_restore_stage 05_route.enc
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true
optDesign -postRoute -hold
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
echo "== CHAIN step 1+2: hold-only + eco + antenna (innovus) =="
( cd "$RUN" && innovus -no_gui -files chain.tcl -log logs/chain )
grep -aE 'CHAIN (pass|PLATEAU|HOLDCLEAN|STOP)|ANTENNA (pass|PLATEAU|ECO FINAL)' "$RUN/logs/chain.log" | tail -8
grep -aq 'CHAIN STOP' "$RUN/logs/chain.log" && { echo "CHAIN halted: route not clean"; exit 2; }
AF=$(ls -t "$RUN"/reports/antenna_eco/antenna_final.rpt 2>/dev/null | head -1)
AV=$(grep -aoE 'Verification Complete: [0-9]+ Violations' "$AF" 2>/dev/null | grep -oE '[0-9]+' || echo "?")
DV=$(grep -aoE 'ANTENNA ECO FINAL: verify_drc = [0-9]+' "$RUN/logs/chain.log" | grep -oE '[0-9]+$' || echo "?")
echo "post-antenna: antenna=$AV drc=$DV (both must be 0 to proceed)"
[ "$AV" = "0" ] && [ "$DV" = "0" ] || { echo "CHAIN halted before export - judge reports"; exit 3; }

echo "== CHAIN step 3: export =="
( cd "$RUN" && ASIC_PNR_RUN_STAMP=$STAMP ASIC_ANTENNA_SRC=05_antenna_clean.enc \
  innovus -no_gui -files <(echo "source $SCR/innovus_config.tcl
pnr_restore_stage 05_antenna_clean.enc
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
$REPO/asic/signoff/lvs/run_lvs_bb.sh "$GDS" "$(ls "$RUN"/outputs/*_pnr.v | head -1)"
( cd $REPO/asic/signoff/tempus && tempus -no_gui -files sta.tcl -log "$SIGNOFF_RESULTS/tempus/tempus_chain" )
echo "== CHAIN COMPLETE: results under $SIGNOFF_RESULTS =="
