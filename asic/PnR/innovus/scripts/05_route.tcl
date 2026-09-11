# Stage 05 - route + gated post-route optimisation (old stages 07+08,
# combined and renumbered 2026-08-30): route -> checkpoint -> verify_drc GATE -> optDesign. The gate
# encodes the v2 post-mortem as flow structure: opt ran on a netlist with
# 331k routing DRCs and drove them to 1.8M while setup went -12.8 -> -22 ns.
# Optimising an unroutable placement is never recoverable downstream - stop
# and fix the floorplan instead.
#
# The first stage whose timing numbers are worth quoting. Everything before this
# used estimated parasitics; synthesis used placement-based estimates (PLE),
# which asic/README.md is explicit are a FLOOR - post-route slack is expected to
# be worse. This is where that expectation gets tested.

set _here [file normalize [file dirname [info script]]]
# Config first (idempotent), then restore the previous stage ONLY if no
# design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# failed after sourcing the config leaves the variable defined and a
# re-source then skips the restore (floorPlan "unithd does not match any
# object in design" - first shakedown 2026-08-26).
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
if {[dbGet -e top] eq ""} { pnr_restore_stage 04_cts.enc }

# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------
setNanoRouteMode -reset
# li1 excluded (12.8 ohm/sq; layer INTs li1=1..met5=6) - belt-and-suspenders
# with 00_init's setDesignMode, since -reset just cleared NanoRoute modes.
setNanoRouteMode -routeBottomRoutingLayer 2 -routeTopRoutingLayer 6
setNanoRouteMode -routeWithTimingDriven true \
                 -routeWithSiDriven false \
                 -drouteFixAntenna true \
                 -routeAntennaCellName sky130_fd_sc_hd__diode_2

routeDesign

# Save the routed design BEFORE any report: routing is hours, and the v2
# attempt (2026-08-26) died in post-route steps with no checkpoint.
saveDesign [pnr_ckpt 05_route_raw.enc]

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
# Both corners, both directions. The setup view against the 4.000 ns real target
# (golden.sdc: 3.500 ns is a synthesis guardband, NOT the signoff number) and
# the hold view against the FF corner.
#
# The deep census report is what asic/census.py reads: it groups paths by
# startpoint->endpoint class, the same grouping the Genus censuses use, which
# is what makes a PnR result comparable to them.
#
# Wrapped in catch so a report quirk cannot abort before the final save
# (stage-05 lesson, 2026-08-28).
# Post-route timing refuses to run without OCV (IMPOPT-7027, hit 2026-08-28;
# stage 08 sets the same thing - it has to be on before the first postRoute
# timeDesign, which is here).
setAnalysisMode -analysisType onChipVariation -cppr both

# clearDrc first: the gate below counts top.markers, and a continued run
# (sweep_continue restoring 03_place.enc) or NanoRoute's own checks can leave
# stale/antenna markers stacked on top of verify_drc's. That inflated the
# iter14 gate to 2,375 when verify_drc itself found 706, and contE to 8,437
# vs a real 3,377 (discovered 2026-09-01) - iter7/iter11 were single-pass
# runs and never hit it, which is why the mismatch went unseen.
foreach _r {
    {clearDrc}
    {verify_drc -limit 100000 -report [pnr_rpt route drc.rpt]}
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt route x]] -prefix postroute}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt route x]] -prefix postroute}
    {report_timing -late  -max_paths 50 > [pnr_rpt route setup.rpt]}
    {report_timing -early -max_paths 50 > [pnr_rpt route hold.rpt]}
    {report_timing -late -max_paths 1000 -path_type summary > [pnr_rpt route census.rpt]}
    {reportCongestion -overflow > [pnr_rpt route congestion.rpt]}
    {report_power     > [pnr_rpt route power.rpt]}
    {report_area      > [pnr_rpt route area.rpt]}
    {summaryReport -noHtml -outfile [pnr_rpt route summary.rpt]}
} {
    if {[catch {eval $_r} _msg]} { pnr_note "REPORT FAILED (fix cmd, rerun by hand): $_r -> $_msg" }
}

saveDesign [pnr_ckpt 05_route.enc]

# ---------------------------------------------------------------------------
# The DRC gate
# ---------------------------------------------------------------------------
# verify_drc (in the report loop above) left its violations as markers on the
# design. A healthy route is hundreds; v2 was 331k. Above the gate, post-route
# optimisation is not run: it cannot fix routing DRCs and demonstrably
# multiplies them (v2: x5.5). The routed database is saved either way.
set DRC_GATE [config_env ASIC_DRC_GATE 2000]
set _drc [llength [dbGet -e top.markers]]
if {$_drc > $DRC_GATE} {
    pnr_note "DRC GATE FAILED: $_drc violation markers > $DRC_GATE."
    # pnr_fail (not return): a plain return from a sourced stage would let the
    # driver continue into stage 09 against a checkpoint this stage never
    # wrote. The routed database IS saved (05_route.enc, above) - fix the
    # floorplan/congestion and re-route, or rerun with ASIC_DRC_GATE=<n> if
    # the count is understood.
    pnr_fail "stage 05 DRC gate: $_drc violations > $DRC_GATE - post-route opt\
              and export not run; routed db saved in 05_route.enc"
}
pnr_note "DRC gate passed: $_drc violation markers <= $DRC_GATE"

# ---------------------------------------------------------------------------
# Post-route optimisation (was stage 08) - setup, then hold
# ---------------------------------------------------------------------------
# OCV was already set before the postRoute timeDesign above (IMPOPT-6080:
# post-route opt refuses to run without it).
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true
# setOptMode -reset restores usefulSkew=true (04_cts.tcl lesson, 2026-09-07); the
# 24a stage-05 log showed -usefulSkew true / -usefulSkewCCOpt standard going into
# the post-route opts. Re-apply the CTS knob so no delay cells enter clock branches here.
if {![config_env ASIC_CTS_USEFUL_SKEW 0]} {
    catch {setOptMode -usefulSkew false}
    catch {setOptMode -usefulSkewCCOpt none}
    catch {setAnalysisMode -usefulSkew false}
    pnr_note "post-route opt: useful skew OFF re-applied after setOptMode -reset"
}

optDesign -postRoute
saveDesign [pnr_ckpt 05_postroute_setup.enc]
# iter21 (2026-09-07): re-assert the I/O timing model before the post-route
# hold fix (same reason as in 04_cts.tcl; idempotent if it survived restore).
if {[config_env ASIC_IO_MODEL_POSTCTS 1]} {
    set _vclk_out [file dirname [pnr_rpt route io_vclk.txt]]
    set io_vclk_applied 0
    if {[catch {source [file join $_here io_vclk.tcl]} _msg]} { pnr_note "io_vclk.tcl failed post-route: $_msg" }
    pnr_note "post-route I/O model applied = $io_vclk_applied (see reports/route/io_vclk.txt)"
}
optDesign -postRoute -hold

# The deep census report is what asic/census.py parses - same grouping as
# every synthesis census, which is what makes this comparable to them.
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt postroute_opt x]] -prefix postroute_opt}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt postroute_opt x]] -prefix postroute_opt}
    {verify_drc -limit 100000 -report [pnr_rpt postroute_opt drc.rpt]}
    {report_timing -late  -max_paths 50 > [pnr_rpt postroute_opt setup.rpt]}
    {report_timing -early -max_paths 50 > [pnr_rpt postroute_opt hold.rpt]}
    {report_timing -late -max_paths 1000 -path_type summary > [pnr_rpt postroute_opt census.rpt]}
    {report_area      > [pnr_rpt postroute_opt area.rpt]}
    {report_power     > [pnr_rpt postroute_opt power.rpt]}
    {reportCongestion -overflow > [pnr_rpt postroute_opt congestion.rpt]}
    {summaryReport -noHtml -outfile [pnr_rpt postroute_opt summary.rpt]}
} {
    if {[catch {eval $_r} _msg]} { pnr_note "REPORT FAILED (fix cmd, rerun by hand): $_r -> $_msg" }
}

saveDesign [pnr_ckpt 05_route_opt.enc]
pnr_note "stage 05 (route + post-route opt) complete - first quotable timing numbers"
