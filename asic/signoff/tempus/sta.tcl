# Tempus signoff STA on a P&R run's deliverables.
#
#   bash -lc 'source /apps/settings && source <repo>/asic/PnR/innovus/env.sh && \
#             source <repo>/asic/signoff/env.sh && cd <repo>/asic/signoff/tempus && \
#             tempus -no_gui -files sta.tcl -log $SIGNOFF_RESULTS/tempus/tempus'
#
# Reuses the P&R configuration verbatim: innovus_config.tcl (libs, macro
# libs, derates, TOP, RUN_TAG, output dir) and mmmc.tcl (SS setup / FF hold
# views). Tempus reads the same legacy init_* globals and MMMC Tcl as Innovus,
# so the corner definitions cannot drift between the two tools.
#
# Shaken down 2026-09-01 on iteration 7's export. The scripts dir is the bare
# innovus tree's (a run dir has no scripts/); the run itself is selected by
# ASIC_PNR_RUN_STAMP, which env.sh copies from SIGNOFF_PNR_STAMP.
if {[info exists env(SIGNOFF_PNR_SCRIPTS)]} {
    set pnr_scripts $env(SIGNOFF_PNR_SCRIPTS)
} else {
    set pnr_scripts [file join $env(SIGNOFF_PNR_DIR) scripts]
}
source [file join $pnr_scripts innovus_config.tcl]

set out [file join $env(SIGNOFF_RESULTS) tempus]
file mkdir $out

set netlist [file join $PNR_OUT_DIR ${RUN_TAG}_pnr.v]
# Per-corner Quantus SPEFs when extract_pnr.tcl produced them (2026-08-30);
# fall back to the single SPEF for both corners otherwise.
set spef      [file join $PNR_OUT_DIR ${RUN_TAG}_pnr.spef]
set spef_fast [file join $PNR_OUT_DIR ${RUN_TAG}_pnr_rc_fast.spef]
if {![file readable $spef_fast]} { set spef_fast $spef }
foreach f [list $netlist $spef] {
    if {![file readable $f]} { error "sta.tcl: missing P&R deliverable $f (run the export stage first)" }
}

set init_verilog   $netlist
set init_top_cell  $TOP
set init_design_netlisttype Verilog
set init_design_settop 1
set init_mmmc_file [file join $pnr_scripts mmmc.tcl]
init_design
pnr_apply_macro_derates

# Quantus per-corner SPEFs (techfile validated for signal widths 2026-08-30,
# quantus/quantus.md); the rc_slow/rc_fast +/-10% scaling in mmmc.tcl still
# applies on top as the corner spread.
spefIn $spef      -rc_corner rc_slow
spefIn $spef_fast -rc_corner rc_fast

setAnalysisMode -analysisType onChipVariation -cppr both

# Constraints, in preference order (decision 2026-09-01, user call):
#
# 1. The AS-IMPLEMENTED SDC exported by stage 06 (write_sdc -view). This is
#    the standard signoff handoff: it carries everything the flow changed
#    interactively after the source SDC was read - the 4.000 ns clock, the
#    propagated-clock switch, the post-CTS uncertainties - straight from the
#    final Innovus database, so nothing can be forgotten in a replay.
# 2. Fallback for runs exported BEFORE the handoff existed (iter7 and older):
#    the source SDC was already read via mmmc.tcl; replay the two CTS-time
#    mutations by hand, mirroring 04_cts.tcl exactly. Without this replay the
#    source SDC describes the PRE-CTS world - ideal clock, 0.250 stand-in
#    uncertainty - and signoff is fiction (measured: iter7's first run showed
#    "Clock Network Latency (Ideal) 0.000" and a fake-clean +0.127 hold).
set sdc_asimpl [file join $PNR_OUT_DIR ${RUN_TAG}_setup.sdc]
if {[file readable $sdc_asimpl]} {
    update_constraint_mode -name func -sdc_files [list $sdc_asimpl]
    puts "TEMPUS: constraints = as-implemented export $sdc_asimpl"
} else {
    set_interactive_constraint_modes [all_constraint_modes -active]
    set_propagated_clock [all_clocks]
    set _su [config_env ASIC_POSTCTS_SETUP_UNCERT 0.100]
    set _hu [config_env ASIC_POSTCTS_HOLD_UNCERT  0.050]
    set_clock_uncertainty -setup $_su [all_clocks]
    set_clock_uncertainty -hold  $_hu [all_clocks]
    puts "TEMPUS: no exported SDC - source SDC + replayed post-CTS treatment (setup $_su / hold $_hu)"
}

# ---------------------------------------------------------------------------
# Latency-matched virtual clock for I/O timing (2026-09-02, the constraints
# TODO from the iter7 signoff). The tree's insertion delay is ~7.4 ns at ss;
# golden.sdc's I/O budgets reference the ideal edge at the clk port, so
# in2reg setup gets the whole tree depth as free time (reports clean no
# matter what) while reg2out setup and in2reg hold get charged it (report
# huge fake violations). Standard OOC treatment: reference the I/O budgets
# to a VIRTUAL clock carrying the same latency as the real tree - the
# external agent is modeled as living at our clock depth. Port numbers are
# only quotable WITH the latency value used; it is echoed and written to
# $out/io_vclk.txt for exactly that reason.
#   ASIC_IO_VCLK_LATENCY  explicit ns value, or "auto" (default): use the
#                         worst late network latency from report_clock_timing.
#   ASIC_IO_INPUT_DELAY / ASIC_IO_OUTPUT_DELAY  budgets re-applied on the
#                         virtual clock (defaults mirror golden.sdc).
# Latency must be CORNER-CONSISTENT (validation 2026-09-02 caught it): one
# late value applied to both views models an external agent slower than the
# fast-corner tree and mints fake reg2out hold violations (-7.8 observed).
# Late = worst setup-view network latency, early = worst hold-view latency.
set _vlat  [config_env ASIC_IO_VCLK_LATENCY auto]
set _vlate 0
set _vearly 0
if {$_vlat eq "auto"} {
    report_clock_timing -type latency > $out/clock_latency.rpt
    set _view ""
    set _f [open $out/clock_latency.rpt r]
    while {[gets $_f _line] >= 0} {
        if {[regexp {Analysis View:\s+(\S+)} $_line -> _v]} { set _view $_v; continue }
        foreach _tok $_line {
            if {[string is double -strict $_tok] && $_tok > 0 && $_tok < 50} {
                if {[string match *hold* $_view]} {
                    if {$_tok > $_vearly} { set _vearly $_tok }
                } else {
                    if {$_tok > $_vlate}  { set _vlate  $_tok }
                }
            }
        }
    }
    close $_f
    if {$_vearly == 0} { set _vearly $_vlate }
    # CORRELATED-EXTERNAL MODEL (round-4 lesson): applying the measured
    # early (ff 4.318) as vclk early pits ss launch against ff capture inside
    # the setup view - a 7.6 ns fiction in either direction. OOC convention:
    # the external agent's tree TRACKS ours, so early = late; the measured
    # ff-view early is recorded in io_vclk.txt for the integrator, and port
    # hold is deferred (false_path below) rather than faked either way.
    set _vmeas_early $_vearly
    set _vearly $_vlate
    set _vlat $_vlate
    if {$_vlat == 0} {
        puts "TEMPUS WARN: could not auto-measure clock latency - I/O vclk NOT applied; port groups remain latency-skewed"
    }
} else {
    set _vlate  $_vlat
    set _vearly [config_env ASIC_IO_VCLK_LATENCY_EARLY $_vlat]
}
if {$_vlat > 0} {
    # Tempus's legacy UI returns "" for some clock property spellings; try
    # both, then fall back to the flow's known period (pnr.sdc: 4.000).
    set _per ""
    catch {set _per [get_property [get_clocks clk] period]}
    if {$_per eq ""} { catch {set _per [get_attribute [get_clocks clk] period]} }
    if {$_per eq "" || ![string is double -strict $_per]} {
        set _per [config_env ASIC_IO_VCLK_PERIOD 4.000]
        puts "TEMPUS WARN: clock period not queryable - using $_per from ASIC_IO_VCLK_PERIOD/default"
    }
    set _idly [config_env ASIC_IO_INPUT_DELAY  0.700]
    set _odly [config_env ASIC_IO_OUTPUT_DELAY 0.300]
    create_clock -name vclk_io -period $_per
    set_clock_latency -source -late  $_vlate  [get_clocks vclk_io]
    set_clock_latency -source -early $_vearly [get_clocks vclk_io]
    set _inports [remove_from_collection [all_inputs] [get_ports clk]]
    set_input_delay  $_idly -clock vclk_io $_inports
    set_output_delay $_odly -clock vclk_io [all_outputs]
    # reg2out HOLD is deferred to integration (standard OOC): the check pits
    # our fast-corner tree (early ~4.3) against the late external edge (11.9)
    # inside one mode - single-mode SDC latency cannot express "same corner
    # both sides", and the true requirement belongs to whoever integrates the
    # block. in2reg hold stays fully constrained (it verified clean).
    set_false_path -hold -to [all_outputs]
    puts "TEMPUS: I/O virtual clock vclk_io period $_per latency late $_vlate / early $_vearly (in $_idly / out $_odly); reg2out hold deferred to integration"
    set _vf [open $out/io_vclk.txt w]
    puts $_vf "vclk_io latency_late=$_vlate latency_early=$_vearly (correlated model; measured ff-early [expr {[info exists _vmeas_early] ? $_vmeas_early : {n/a}}]) period=$_per input_delay=$_idly output_delay=$_odly reg2out_hold=deferred"
    close $_vf
}

report_analysis_summary                          > $out/summary.rpt
report_timing -late  -max_paths 50               > $out/setup.rpt
report_timing -early -max_paths 50               > $out/hold.rpt
report_timing -late  -max_paths 1000 -path_type summary > $out/census.rpt
report_constraint -all_violators                 > $out/violators.rpt
puts "TEMPUS: reports in $out"
exit
