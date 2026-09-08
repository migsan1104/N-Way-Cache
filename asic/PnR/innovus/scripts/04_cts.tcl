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

# ---------------------------------------------------------------------------
# iter21 (2026-09-07): boundary-register skew group. The I/O budgets are
# referenced to ONE boundary register's clock pin (io_vclk.tcl reference-pin
# mode), which is only honest if every boundary register shares that insertion
# delay. On iter19b they spanned 0.45..9.6 ns at signoff (Tempus, n40C). This
# group asks CCOpt to balance them among themselves (the core keeps its useful
# skew). Patterns are netlist instance names; every pattern must match or the
# list is stale and the stage refuses to continue.
#   ASIC_CTS_IO_SINK_PATTERNS  space-separated dbGet globs (default below)
#   ASIC_CTS_IO_SKEW           group target skew, ns (default 0.100)
# Pre-route RC correlation: the 1.6 ns CTS-estimate vs 7.4 ns signoff gap
# (CTS.md section 5) is the LEF/capTable RC vs Quantus. Until factors are
# derived (generateRCFactor against the 19b Quantus SPEF - TODO), the knob
# below applies explicit preRoute scaling when set, e.g. "2.1:2.1".
#   ASIC_CTS_RC_FACTORS        "res:cap" for setRCFactor -preRoute (default none)
# ---------------------------------------------------------------------------
# 2026-09-07 generateRCFactor on 19b (reference = Quantus signoff extraction):
#   preRoute_res 0.205  preRoute_cap 1.031  preRoute_clkres 0.247  preRoute_clkcap 0.949
# i.e. the LEF-based estimator's wire RESISTANCE was ~5x Quantus. Format
# "res:cap" or "res:cap:clkres:clkcap"; applied per rc corner with
# update_rc_corner (what the tool itself prints), setRCFactor as fallback.
set _rcf [config_env ASIC_CTS_RC_FACTORS ""]
if {$_rcf ne ""} {
    set _f [split $_rcf :]
    lassign $_f _rres _rcap _rclkres _rclkcap
    if {$_rclkres eq ""} { set _rclkres $_rres }
    if {$_rclkcap eq ""} { set _rclkcap $_rcap }
    set _applied 0
    foreach _c [list rc_slow rc_fast] {
        if {![catch {update_rc_corner -name $_c -preRoute_res $_rres -preRoute_cap $_rcap -preRoute_clkres $_rclkres -preRoute_clkcap $_rclkcap}]} { incr _applied }
    }
    if {!$_applied} { setRCFactor -preRoute_res $_rres -preRoute_cap $_rcap -preRoute_clkres $_rclkres -preRoute_clkcap $_rclkcap }
    pnr_note "CTS: preRoute RC factors res x$_rres cap x$_rcap clkres x$_rclkres clkcap x$_rclkcap on $_applied rc corners (ASIC_CTS_RC_FACTORS)"
}
set CTS_IO_SKEW [config_env ASIC_CTS_IO_SKEW 0.100]
set CTS_IO_PATS [config_env ASIC_CTS_IO_SINK_PATTERNS \
    "*inreg_*_r_reg* *rindex_rep_r_reg* *rst_r_reg* *RESP_SKID_* *mem_req_*_reg* *REG_STAGE0_q_reg* *RESP_DEMUX_mshr_resp_valid_reg* *HIT_FIFO_wr_ptr_r_reg* *RES_STATION_valid_count_reg*"]
set _io_sinks {}
set _io_missing {}
# dbGet returns Tcl lists, so a name with [] comes back brace-quoted
# ({inreg_addr_r_reg[21]/CLK}); a raw string compare against "<inst>/CLK"
# therefore matched only the four scalar flops (iter21 CTS abort, 2026-09-07,
# and the "io_regs ... 4 sinks" line in every ctsA-E log). instTerm has no
# isClock attribute either (the IMPDBTCL-204 spam). Match the library pin
# name and lindex the strings out of their lists.
foreach _pat $CTS_IO_PATS {
    set _n 0
    foreach _inst [dbGet -e -p top.insts.name $_pat] {
        if {![dbGet $_inst.cell.isSequential]} continue
        foreach _t [dbGet -e $_inst.instTerms] {
            if {[lindex [dbGet $_t.cellTerm.name] 0] in {CLK CLK_N}} {
                lappend _io_sinks [lindex [dbGet $_t.name] 0]; incr _n; break
            }
        }
    }
    if {!$_n} { lappend _io_missing $_pat }
}
if {[llength $_io_missing] && ![config_env ASIC_CTS_IO_SINK_OPTIONAL 0]} {
    pnr_note "CTS ABORT: boundary skew-group patterns matched nothing: $_io_missing (update ASIC_CTS_IO_SINK_PATTERNS or set ASIC_CTS_IO_SINK_OPTIONAL=1)"
    exit 4
}
create_ccopt_clock_tree_spec
if {[llength $_io_sinks]} {
    create_ccopt_skew_group -name io_regs -sources clk -sinks $_io_sinks
    set_ccopt_property -skew_group io_regs target_skew $CTS_IO_SKEW
    pnr_note "CTS: skew group io_regs = [llength $_io_sinks] boundary register clock pins, target skew $CTS_IO_SKEW ns"
}
# update_io_latency (2026-09-07, CTS.md section 5 "The 7.331 ns gift"): ccopt's
# silent post-tree step writes a NEGATIVE source latency on clk (one value per
# view). It is meant to re-centre ideal-referenced I/O budgets on the tree,
# but it entered every path and, with only -max in the setup view, shifted
# the launch clock alone: reg2reg read 7.3 ns optimistic from route onward on
# iter16b..20. Off by default from iter21; the I/O model is the reference pin
# in io_vclk.tcl (applied below, after set_propagated_clock).
#   ASIC_CTS_UPDATE_IO_LATENCY  1 = legacy behaviour (default 0)
set CTS_UPDATE_IO_LAT [config_env ASIC_CTS_UPDATE_IO_LATENCY 0]
set_ccopt_property update_io_latency [expr {$CTS_UPDATE_IO_LAT ? "true" : "false"}]
pnr_note "CTS: ccopt update_io_latency = [get_ccopt_property update_io_latency] (ASIC_CTS_UPDATE_IO_LATENCY=$CTS_UPDATE_IO_LAT)"
# Clock cell lists (2026-09-07, CTS.md "Is the tree bad"): with no list ccopt
# reported IMPCCOPT-1183 "no usable balanced buffers" and built an inverter-only
# tree from clkinv_2 (max_cap 0.28 pF -> 0.1 pF wall, 25 levels, 7.3 ns).
# Empty = tool auto-selection (legacy). Names are lib cells without the
# sky130_fd_sc_hd__ prefix or with it, either works.
#   ASIC_CTS_BUFFER_CELLS    e.g. "clkbuf_8 clkbuf_16"
#   ASIC_CTS_INVERTER_CELLS  e.g. "clkinv_8 clkinv_16"
foreach {_knob _prop} {ASIC_CTS_BUFFER_CELLS buffer_cells ASIC_CTS_INVERTER_CELLS inverter_cells} {
    set _cells [config_env $_knob ""]
    if {$_cells ne ""} {
        set _full {}
        foreach _c $_cells { lappend _full [expr {[string match sky130_* $_c] ? $_c : "sky130_fd_sc_hd__$_c"}] }
        set_ccopt_property $_prop $_full
        pnr_note "CTS: $_prop = $_full ($_knob)"
    }
}
# Clock DRV targets (2026-09-07). golden.sdc's design-wide set_max_capacitance
# 0.100 pF applied to the clock nets too and, with clkinv_2 as the only
# survivor of ccopt's cell filter, capped every stage at ~500 um of wire:
# 19..44 levels, 7.3 ns. Clock-net limits belong to CTS, not the signal SDC.
#   ASIC_CTS_TARGET_MAX_TRANS  ns (default 0.750 = golden.sdc)
#   ASIC_CTS_MAX_CAP           pF on the clk network (default "" = SDC/lib)
set CTS_MAX_TRANS [config_env ASIC_CTS_TARGET_MAX_TRANS 0.750]
set CTS_MAX_CAP   [config_env ASIC_CTS_MAX_CAP ""]
set_ccopt_property target_skew        $CTS_TARGET_SKEW
set_ccopt_property target_max_trans   $CTS_MAX_TRANS
if {$CTS_MAX_CAP ne ""} {
    set_interactive_constraint_modes [all_constraint_modes -active]
    if {[catch {set_max_capacitance $CTS_MAX_CAP [get_clocks clk]} _m]} { pnr_note "CTS: set_max_capacitance on clk failed: $_m" } else { pnr_note "CTS: clk network max_capacitance = $CTS_MAX_CAP pF (ASIC_CTS_MAX_CAP)" }
    if {![catch {set_ccopt_property target_max_capacitance $CTS_MAX_CAP} _m]} { pnr_note "CTS: ccopt target_max_capacitance = $CTS_MAX_CAP" }
}
pnr_note "CTS: target skew $CTS_TARGET_SKEW ns, max trans $CTS_MAX_TRANS ns"

# Useful skew (2026-09-07 finding). MUST precede ccopt_design: the cells are
# inserted by ccopt's INTEGRATED post-CTS optimization (ctsA: 367 FE_USKC and
# 56 levels right after ccopt_design returned, 4.6 -> 7.5 ns), so a switch
# after the call is too late. On
# iter19b optDesign inserted 324 FE_USK* delay cells INTO clock branches, up
# to 19 in series, turning ccopt's 7.12-7.64 ns tree into 7.47-9.83 before
# routing (reports/cts/skew.rpt vs the ccopt summary) - honest timer at that
# stage, unreachable target. Default now OFF so the tree stays as ccopt built it;
# ASIC_CTS_USEFUL_SKEW=1 restores the legacy behaviour.
if {![config_env ASIC_CTS_USEFUL_SKEW 0]} {
    catch {setOptMode -usefulSkew false}
    catch {setOptMode -usefulSkewCCOpt none}
    catch {setAnalysisMode -usefulSkew false}
    pnr_note "CTS + post-CTS opt: useful skew OFF (ASIC_CTS_USEFUL_SKEW=0)"
} else { pnr_note "CTS + post-CTS opt: useful skew ON (legacy)" }
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
# Tripwire for the gift: the clock report after ccopt must show NO source
# latency on clk (reports/cts/clocks_after_ccopt.rpt); a reg2reg WNS that jumps
# between stages by more than the RC delta is this bug until proven otherwise.
catch {report_clocks > [pnr_rpt cts clocks_after_ccopt.rpt]}
catch {report_ccopt_clock_trees -file [pnr_rpt cts ccopt_clock_trees.rpt]}
catch {report_ccopt_skew_groups -file [pnr_rpt cts ccopt_skew_groups.rpt]}
catch {report_ccopt_clock_tree_structure -file [pnr_rpt cts ccopt_tree_structure.rpt]}
catch {report_ccopt_cell_filtering_reasons -file [pnr_rpt cts ccopt_cell_filter.rpt]}
set _srclat_lines 0
if {![catch {set _cf [open [pnr_rpt cts clocks_after_ccopt.rpt] r]}]} {
    while {[gets $_cf _l] >= 0} { if {[regexp -nocase {source.*latency|latency.*source} $_l]} { incr _srclat_lines } }
    close $_cf
}
pnr_note "CTS: post-ccopt clock report source-latency lines = $_srclat_lines (expect 0 unless ASIC_CTS_UPDATE_IO_LATENCY=1)"
# iter21 (2026-09-07): apply the I/O timing model HERE, before the post-CTS
# hold fix below. Until now this stage fixed hold against golden.sdc's
# ideal-referenced I/O budgets on a propagated 7 ns tree, i.e. every input
# looked ~7 ns early and optDesign -hold padded the input cones (the armC
# 715-delay-cell finding, io_vclk.tcl header) - the 1.13 ns dlygate on rst
# and 0.92 ns on cpu_resp_ready in iter19b came from exactly this. In
# reference-pin mode (rst_r_reg/CLK exists from iter21 on) the budgets are
# referenced to the boundary registers' own clock arrival. ASIC_IO_MODEL_POSTCTS=0 skips.
if {[config_env ASIC_IO_MODEL_POSTCTS 1]} {
    set _vclk_out [file dirname [pnr_rpt cts io_vclk.txt]]
    set io_vclk_applied 0
    if {[catch {source [file join $_here io_vclk.tcl]} _msg]} { pnr_note "io_vclk.tcl failed post-CTS: $_msg" }
    pnr_note "post-CTS I/O model applied = $io_vclk_applied (see reports/cts/io_vclk.txt)"
}

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
    {report_ccopt_skew_groups           > [pnr_rpt cts skew_groups.rpt]}
    {report_clock_timing -type summary > [pnr_rpt cts clock_summary.rpt]}
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
# -reset above restores usefulSkew=true: ctsE (2026-09-07) left ccopt_design with
# Max Level 19 / 0 FE_USK and ended the stage at 50 levels / 296 FE_USK, all
# inserted by this optDesign. Re-apply the knob after every reset.
if {![config_env ASIC_CTS_USEFUL_SKEW 0]} {
    catch {setOptMode -usefulSkew false}
    catch {setOptMode -usefulSkewCCOpt none}
    catch {setAnalysisMode -usefulSkew false}
    pnr_note "post-CTS opt: useful skew OFF re-applied after setOptMode -reset"
}

optDesign -postCTS
optDesign -postCTS -hold
# Tree state AFTER post-CTS optimization (this is what routing inherits):
catch {report_ccopt_clock_tree_structure -file [pnr_rpt cts ccopt_tree_structure.rpt]}
catch {report_ccopt_skew_groups -file [pnr_rpt cts ccopt_skew_groups_postopt.rpt]}
catch {
    set _sf [open [pnr_rpt cts ccopt_tree_structure.rpt] r]; set _usk 0; set _maxl 0
    while {[gets $_sf _l] >= 0} { if {[string match *FE_USK* $_l]} { incr _usk }; if {[regexp {Max Level: (\d+)} $_l -> _ml]} { set _maxl $_ml } }
    close $_sf
    pnr_note "CTS tripwire: tree Max Level $_maxl, useful-skew/hold cells inside clock branches (FE_USK*) = $_usk (19b: 45 levels, 324 cells)"
}

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
