# Stage 04 - CTS + post-CTS optimisation (old stages 05+06, combined and
# renumbered 2026-08-30; run-1/v2 artifacts keep the old numbers).
# Build the clock tree, switch to real clock timing, then optimise: setup
# first, then hold - hold fixes insert delay buffers which can only hurt
# setup, so fixing setup afterwards would undo them. That order holds at
# every optimisation stage in this flow and is not interchangeable. This is
# the first stage where hold is real.
#
# This is where the constraints change meaning. Up to now the clock has been
# IDEAL, with golden.sdc's 0.250 ns setup uncertainty standing in for the skew
# and jitter of a tree that did not exist. After CTS the tree is real: the clock
# becomes propagated, the pre-CTS margin comes off, and hold becomes a genuine
# question for the first time in this project's flow.
#
# The reset is a timed synchronous signal in this design (golden.sdc is explicit
# that rst gets an input delay and is NOT false-pathed). The E29 campaign
# (2026-08, letters a-o, all in the frozen e35abcde netlist) stripped reset from
# everything but the architectural roots: ~590 flops keep it, 87% of them
# allocated_mem, and the rst port itself drives only 2 cells (clkinv_2 + buf_6).
# It is not a clock and is not built by CTS; after E29 it should NOT appear as a
# monster net in the post-CTS reports - if it does, something regressed.

set _here [file normalize [file dirname [info script]]]
# Config first (idempotent), then restore the previous stage ONLY if no
# design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# failed after sourcing the config leaves the variable defined and a
# re-source then skips the restore (floorPlan "unithd does not match any
# object in design" - first shakedown 2026-08-26).
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
if {[dbGet -e top] eq ""} { pnr_restore_stage 03_place.enc }

# ---------------------------------------------------------------------------
# Routing layer limits - MUST precede any real routing (CTS routes the clock).
# li1 is routing layer 1 at 12.8 ohm/sq; leaving it available poisons both the
# clock routing and every wire-RC estimate (the discarded flow measured -4 to
# -9 ns of pure li1 pessimism per path; its -3.8 preCTS reference had this fix).
# Layer numbers are INTs: li1=1, met1=2 ... met5=6. Signals met1-met5.
# ---------------------------------------------------------------------------
setDesignMode -bottomRoutingLayer 2 -topRoutingLayer 6
pnr_note "routing layers constrained: met1..met5 (li1 excluded)"

# ---------------------------------------------------------------------------
# G7a hook: constrain CLOCK routing to upper layers with a 2x-width/2x-spacing
# NDR. iter5's drc.rpt opened with a met1 CTS_789 trunk shorting picket-fence
# rows of nets through the hub (../DRC.md, hypothesis 4): clock trunks do not
# belong on met1/met2 in a congested core. Leaf nets keep the default rule -
# they must still drop to met1 pins. Default OFF; enable with e.g.
#   ASIC_CTS_CLOCK_LAYERS=met3:met5
# ---------------------------------------------------------------------------
set CTS_CLOCK_LAYERS [config_env ASIC_CTS_CLOCK_LAYERS ""]
if {$CTS_CLOCK_LAYERS ne ""} {
    lassign [split $CTS_CLOCK_LAYERS :] _cl_bot _cl_top
    add_ndr -name cts_2w2s -width_multiplier "$_cl_bot:$_cl_top 2" \
            -spacing_multiplier "$_cl_bot:$_cl_top 2"
    create_route_type -name cts_trunk -non_default_rule cts_2w2s \
        -bottom_preferred_layer $_cl_bot -top_preferred_layer $_cl_top
    set_ccopt_property route_type -net_type trunk cts_trunk
    set_ccopt_property route_type -net_type top   cts_trunk
    pnr_note "CTS clock trunk/top routing: $_cl_bot..$_cl_top with 2w2s NDR (G7a)"
}

# ---------------------------------------------------------------------------
# Clock tree synthesis
# ---------------------------------------------------------------------------
set CTS_TARGET_SKEW   [config_env ASIC_CTS_TARGET_SKEW 0.100]
set CTS_TARGET_LATENCY [config_env ASIC_CTS_TARGET_LATENCY 0.500]

create_ccopt_clock_tree_spec
set_ccopt_property target_skew        $CTS_TARGET_SKEW
set_ccopt_property target_max_trans   0.750
pnr_note "CTS: target skew $CTS_TARGET_SKEW ns, max trans 0.750 ns (golden.sdc's DRC)"

ccopt_design

# ---------------------------------------------------------------------------
# The clock is now real
# ---------------------------------------------------------------------------
# SDC-style commands typed after ccopt_design need an interactive constraint
# mode, or Innovus refuses them (TCLCMD-1048, hit 2026-08-28 04:56 - the
# script died here with the fresh tree unsaved; it was rescued by hand).
set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
pnr_note "clock switched to propagated"

# The pre-CTS uncertainty in golden.sdc was a stand-in for the tree. Now that
# the tree exists and its skew is measured, holding the full 0.250 ns on top
# double-counts it. Reduce to a post-CTS jitter/margin allowance.
#
# This is a real signoff decision, not a cleanup: it directly changes reported
# slack. The number below is deliberately conservative, and the value actually
# used must be recorded alongside any quoted post-route result.
set POSTCTS_SETUP_UNCERTAINTY [config_env ASIC_POSTCTS_SETUP_UNCERT 0.100]
set POSTCTS_HOLD_UNCERTAINTY  [config_env ASIC_POSTCTS_HOLD_UNCERT  0.050]

set_clock_uncertainty -setup $POSTCTS_SETUP_UNCERTAINTY [all_clocks]
set_clock_uncertainty -hold  $POSTCTS_HOLD_UNCERTAINTY  [all_clocks]
pnr_note "post-CTS uncertainty: setup $POSTCTS_SETUP_UNCERTAINTY, hold $POSTCTS_HOLD_UNCERTAINTY"

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
# Report commands are wrapped in catch so a report-option version quirk cannot
# abort the script between the expensive ccopt_design and the saveDesign
# (stage-03/04 shakedown lesson, 2026-08-27: verifyWellTap/reportCongestion
# options differ per release, and an error here would lose the built tree).
foreach _r {
    {report_ccopt_clock_trees -summary > [pnr_rpt cts clocks.rpt]}
    {report_clock_timing -type skew    > [pnr_rpt cts skew.rpt]}
    {report_power                       > [pnr_rpt cts power.rpt]}
    {report_timing -late  -max_paths 20 > [pnr_rpt cts setup.rpt]}
    {report_timing -early -max_paths 20 > [pnr_rpt cts hold.rpt]}
    {summaryReport -noHtml -outfile [pnr_rpt cts summary.rpt]}
} {
    if {[catch {eval $_r} _msg]} { pnr_note "REPORT FAILED (fix cmd, rerun by hand): $_r -> $_msg" }
}

# Checkpoint the fresh tree BEFORE optimisation (a checkpoint belongs after
# every expensive step, not only at stage boundaries - the route-v1 lesson).
saveDesign [pnr_ckpt 04_cts_raw.enc]

# ---------------------------------------------------------------------------
# Post-CTS optimisation (was stage 06) - setup, then hold
# ---------------------------------------------------------------------------
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true

optDesign -postCTS
optDesign -postCTS -hold

foreach _r {
    {timeDesign -postCTS       -outDir [file dirname [pnr_rpt postcts_opt x]] -prefix postcts_opt}
    {timeDesign -postCTS -hold -outDir [file dirname [pnr_rpt postcts_opt x]] -prefix postcts_opt}
    {report_timing -late  -max_paths 20 > [pnr_rpt postcts_opt setup.rpt]}
    {report_timing -early -max_paths 20 > [pnr_rpt postcts_opt hold.rpt]}
    {report_area                        > [pnr_rpt postcts_opt area.rpt]}
    {report_power                       > [pnr_rpt postcts_opt power.rpt]}
    {reportCongestion -overflow         > [pnr_rpt postcts_opt congestion.rpt]}
    {summaryReport -noHtml -outfile [pnr_rpt postcts_opt summary.rpt]}
} {
    if {[catch {eval $_r} _msg]} { pnr_note "REPORT FAILED (fix cmd, rerun by hand): $_r -> $_msg" }
}

saveDesign [pnr_ckpt 04_cts.enc]
pnr_note "stage 04 (CTS + post-CTS opt) complete - check postcts_opt/hold.rpt:\
          the first honest hold number in the whole flow"
