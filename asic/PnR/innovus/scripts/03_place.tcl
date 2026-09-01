# Stage 03 - place: well taps, endcaps, then INTEGRATED placement + pre-CTS
# optimisation (place_opt_design). Stages 03+04 were combined 2026-08-30: the
# split (placeDesign, then optDesign -preCTS as its own stage) bought iteration
# speed but measurably worse QoR - v2 measured -3.8 (integrated estimate)
# vs -6.97 (split) on the same floorplan. 04_prects_opt.tcl is retired.
#
# SETUP ONLY here, deliberately. The clock is still ideal - golden.sdc's 0.250 ns
# uncertainty is standing in for a tree that does not exist yet - so any hold
# "fix" made now is fixing a number CTS is about to invalidate, at the cost of
# buffers that stay in the design. Hold becomes real at post-CTS opt.
#
# Order matters. Taps and endcaps are physical-only cells that must exist BEFORE
# standard cells are placed, or the placer fills the rows and there is nowhere
# legal left to put them. In sky130 taps are not optional - the process requires
# a well tap within a fixed distance of every cell, and a missing tap surfaces as
# DRC failures at the very end of a long run.

set _here [file normalize [file dirname [info script]]]
# Config first (idempotent), then restore the previous stage ONLY if no
# design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# failed after sourcing the config leaves the variable defined and a
# re-source then skips the restore (floorPlan "unithd does not match any
# object in design" - first shakedown 2026-08-26).
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
if {[dbGet -e top] eq ""} { pnr_restore_stage 02_power.enc }

# ---------------------------------------------------------------------------
# Physical-only cells
# ---------------------------------------------------------------------------
# Endcaps close the ends of every row.
setEndCapMode -reset
setEndCapMode -leftEdge $ENDCAP_CELL -rightEdge $ENDCAP_CELL
addEndCap
pnr_note "endcaps: $ENDCAP_CELL"

# Well taps. TAP_DISTANCE is the max spacing between taps; 13 um is a
# conservative starting value for sky130's tapvpwrvgnd. No macro-avoidance
# flag needed (or legal - IMPTCM-48, shakedown 2026-08-27): taps only go in
# rows, and the rows were already cut around the macros+halos at floorplan.
addWellTap -cell $TAP_CELL \
           -cellInterval $TAP_DISTANCE \
           -prefix WELLTAP
pnr_note "well taps: $TAP_CELL every $TAP_DISTANCE um"

# -report, not -reportfile, and -rule is mandatory (IMPTCM-48 + IMPVFG-18,
# shakedown 2026-08-27). The rule is the max tap spacing to check against;
# checking against the insertion interval verifies insertion did its job.
verifyWellTap -rule $TAP_DISTANCE -report [pnr_rpt place welltap.rpt]

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------
setPlaceMode -reset
setPlaceMode -place_global_place_io_pins true \
             -place_detail_legalization_inst_gap 1
# Local-density relief valve (iter5+): iter4's route gated on hub shorts from
# local over-density under a soft guide while GLOBAL overflow was only 7%.
# 0 = tool default (uncapped). Set e.g. 0.62 to keep any bin below 62%.
set _pmax [config_env ASIC_PLACE_MAX_DENSITY 0]
if {$_pmax > 0} {
    setPlaceMode -place_global_max_density $_pmax
    pnr_note "placement max local density capped at $_pmax"
}

# ---------------------------------------------------------------------------
# Congestion-control hooks (2026-08-31, the placement sweep - DRC.md
# "Methodology: the placement sweep"). ALL DEFAULT OFF: with no ASIC_PLACE_*
# / ASIC_OPT_CONG_EFFORT env set this block emits nothing and the stage
# behaves exactly as it did for iterations 1-11, so historical numbers stay
# comparable.
#
# Why they exist: iterations 7 and 9 steered congestion with hand-carved
# placement BLOCKAGES while the tool's own congestion machinery sat at
# defaults. The professional escalation order is the reverse - effort knobs
# and cell padding first, manual geometry last. These hooks open that axis.
#
# Every setting is catch-wrapped and reported: option spellings vary across
# Innovus builds and an unknown option must not cost a 2-hour placement.
# reports/place/cong_knobs.txt records what actually applied.
# ---------------------------------------------------------------------------
set _knob_ok {} ; set _knob_bad {}
set _cong [config_env ASIC_PLACE_CONG_EFFORT ""]
if {$_cong ne ""} {
    if {[catch {setPlaceMode -place_global_cong_effort $_cong} m]} {
        lappend _knob_bad "place_global_cong_effort=$_cong -> $m"
    } else {
        lappend _knob_ok "place_global_cong_effort=$_cong"
        pnr_note "cong knob: place_global_cong_effort $_cong"
    }
}
set _gap [config_env ASIC_PLACE_INST_GAP ""]
if {$_gap ne ""} {
    if {[catch {setPlaceMode -place_detail_legalization_inst_gap $_gap} m]} {
        lappend _knob_bad "legalization_inst_gap=$_gap -> $m"
    } else {
        lappend _knob_ok "legalization_inst_gap=$_gap"
        pnr_note "cong knob: legalization_inst_gap $_gap (cell padding)"
    }
}
set _ocong [config_env ASIC_OPT_CONG_EFFORT ""]
if {$_ocong ne ""} {
    if {[catch {setOptMode -congEffort $_ocong} m]} {
        if {[catch {setOptMode -congestionEffort $_ocong} m2]} {
            lappend _knob_bad "opt congestion effort=$_ocong -> $m / $m2"
        } else {
            lappend _knob_ok "setOptMode -congestionEffort=$_ocong"
            pnr_note "cong knob: setOptMode -congestionEffort $_ocong"
        }
    } else {
        lappend _knob_ok "setOptMode -congEffort=$_ocong"
        pnr_note "cong knob: setOptMode -congEffort $_ocong"
    }
}
if {[llength $_knob_ok] || [llength $_knob_bad]} {
    set _kf [open [pnr_rpt place cong_knobs.txt] w]
    puts $_kf "applied:"
    foreach k $_knob_ok { puts $_kf "  $k" }
    puts $_kf "rejected:"
    foreach k $_knob_bad { puts $_kf "  $k" }
    close $_kf
}

# Opt settings first (they were stage 04's) - place_opt_design honours them.
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true

place_opt_design
pnr_note "place_opt_design (integrated placement + preCTS optimisation)"

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
# Congestion is the number to look at here, not just slack: the 16 macros plus
# the PG stripes over them are the likeliest source of trouble, and the fix for
# congestion is in 01_floorplan.tcl (spacing, columns, utilisation), not here.
# timeDesign -preCTS is the headline WNS/TNS table the v3 floorplan choice is
# made on (FLOORPLAN.md "How the choice is made"); geography + hotspot are the
# other two comparison artifacts. All land in reports/place/.
timeDesign -preCTS -outDir [file dirname [pnr_rpt place x]] -prefix prects
report_timing -late  -max_paths 20 > [pnr_rpt place setup.rpt]
# hold.rpt is written even though hold is not fixed yet: it is the baseline the
# post-CTS hold number is compared against, and a wildly bad pre-CTS hold
# usually means a constraint problem rather than a real violation.
report_timing -early -max_paths 20 > [pnr_rpt place hold.rpt]
report_timing -late -max_paths 1000 -path_type summary > [pnr_rpt place census.rpt]
# -overflow/-hotspot are mandatory in v21.16 (IMPSP-9110, shakedown 08-27).
reportCongestion -overflow         > [pnr_rpt place congestion.rpt]
reportCongestion -hotspot          > [pnr_rpt place congestion_hotspot.rpt]
report_area                        > [pnr_rpt place area.rpt]
report_power                       > [pnr_rpt place power.rpt]
summaryReport -noHtml -outfile [pnr_rpt place summary.rpt]
source [file join $_here dbg_geography.tcl]

saveDesign [pnr_ckpt 03_place.enc]
pnr_note "stage 03 (place+preCTS opt) complete - compare reports/place/{prects*,congestion_hotspot.rpt,placement_geography.txt}"
