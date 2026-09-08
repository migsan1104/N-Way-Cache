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

# SIGNOFF_TEMPUS_TAG (optional) suffixes the output dir - e.g. "ss_n40C_1v76"
# -> tempus_ss_n40C_1v76/ - so runs at several corners on one package do not
# overwrite each other (run_two_corner.sh, 2026-09-04).
set out [file join $env(SIGNOFF_RESULTS) tempus]
if {[info exists env(SIGNOFF_TEMPUS_TAG)] && $env(SIGNOFF_TEMPUS_TAG) ne ""} {
    append out "_$env(SIGNOFF_TEMPUS_TAG)"
}
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
# SIGNOFF_SI=1: signal-integrity-aware delay calculation (crosstalk on
# delays). The Innovus export's timeDesign -signoff ran SI-aware and found
# 9 hold violators (-0.075) that the plain calculator did not; a Tempus
# number without SI is not comparable to it. Added 2026-09-04.
if {[info exists env(SIGNOFF_SI)] && $env(SIGNOFF_SI) eq "1"} {
    setDelayCalMode -SIAware true
    setSIMode -analysisType default
    puts "TEMPUS: SI-aware delay calculation ON"
}

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
# Either branch is followed by interactive constraints (the vclk_io block
# below), which Tempus rejects with TCLCMD-1048 unless a constraint mode is
# enabled interactively - so enable it for BOTH branches, not just the replay.
# The export writes two as-implemented SDCs that differ in exactly four
# lines: CTS's negative source latency on the clk port (update_io_latency).
# write_sdc -view setup_view emits only the -max values (-4.59 here) and
# -view hold_view only the -min values (-1.85); the Innovus DB itself holds
# all four early/late x min/max combos per view. Three Tempus passes on
# iter16b (2026-09-04) showed the checker takes max-qualified latency for
# the capture clock and min-qualified for launch, so a view with only one
# kind is internally inconsistent: setup SDC alone -> hold +4.6 (fake);
# both SDCs in one mode -> the 2nd create_clock wipes clk (TCLCMD-1594);
# setup SDC + hold's -min lines -> hold +2.8 and setup -0.22 (both fake).
# Correct emulation: one constraint mode PER VIEW, and within each mode set
# every min/max combo to that view's own value.
set sdc_hold [file join $PNR_OUT_DIR ${RUN_TAG}_hold.sdc]
# SIGNOFF_PERIOD (optional, ns): what-if STA at another clock period on the
# SAME routed package. Both as-implemented SDCs are copied into $out with
# every "create_clock ... -period P -waveform {0 P/2}" rewritten; nothing
# else changes (CTS, hold fixes and I/O budgets were built for the exported
# period, so this is "the routed netlist meets/does not meet setup at P",
# never an Fmax). io_vclk.tcl re-reads the period from the clk object.
if {[info exists env(SIGNOFF_PERIOD)] && $env(SIGNOFF_PERIOD) ne ""} {
    set _P [expr {double($env(SIGNOFF_PERIOD))}]
    set _H [expr {$_P / 2.0}]
    foreach _v {sdc_asimpl sdc_hold} {
        set _src [set $_v]
        if {![file readable $_src]} { continue }
        set _dst [file join $out "whatif_p${_P}_[file tail $_src]"]
        set _f [open $_src r]; set _t [read $_f]; close $_f
        set _n [regsub -all -- {-period\s+[0-9.]+\s+-waveform\s+\{[0-9.]+\s+[0-9.]+\}} $_t \
                    [format {-period %.6f -waveform {0.000000 %.6f}} $_P $_H] _t]
        # 2026-09-07: Innovus's update_io_latency leaves a NEGATIVE source
        # latency on clk in the exported SDC (-7.33 ns setup / -2.97 hold on
        # iter19b). It exists to centre IDEAL-referenced I/O constraints on
        # the tree; our I/O model (virtual clock or reference pin) does not
        # want it, and Tempus applied it to the LAUNCH clock only (full_clock
        # report: launch "Source Insertion Delay -7.331", capture 0.000),
        # which hands every path ~7.3 ns. Strip it unless told otherwise.
        if {![info exists ::env(SIGNOFF_KEEP_CLK_SRC_LATENCY)] || $::env(SIGNOFF_KEEP_CLK_SRC_LATENCY) ne "1"} {
            set _ns [regsub -all -line {^\s*set_clock_latency\s+-source\s[^\n]*\[get_ports\s*\{clk\}\][^\n]*\n} $_t {} _t]
            puts "TEMPUS: $_v -> stripped $_ns clk source-latency lines (SIGNOFF_KEEP_CLK_SRC_LATENCY=1 to keep)"
        }
        set _f [open $_dst w]; puts -nonewline $_f $_t; close $_f
        set $_v $_dst
        puts "TEMPUS WHAT-IF: $_v -> $_dst ($_n clock definitions rewritten to period $_P ns)"
    }
}
proc _mirror_source_latency {sdc from to} {
    # Re-issue every "set_clock_latency -source ... -$from ..." line of $sdc
    # with -$to so both qualifiers carry the same value in this mode.
    set f [open $sdc r]; set n 0
    while {[gets $f l] >= 0} {
        if {[regexp "^\\s*set_clock_latency\\s+-source\\s.*-$from\\s" $l]} {
            regsub -- "-$from\\s" $l "-$to " l2
            eval $l2; incr n
        }
    }
    close $f
    return $n
}
if {[file readable $sdc_asimpl]} {
    update_constraint_mode -name func -sdc_files [list $sdc_asimpl]
    set_interactive_constraint_modes [list func]
    set _n [_mirror_source_latency $sdc_asimpl max min]
    puts "TEMPUS: setup_view <- $sdc_asimpl (+ $_n -max source latencies mirrored to -min)"
    if {[file readable $sdc_hold]} {
        create_constraint_mode -name func_hold -sdc_files [list $sdc_hold]
        # attach the mode to a view BEFORE making it interactive (TCLCMD-1047)
        update_analysis_view -name hold_view -constraint_mode func_hold
        set_analysis_view -setup {setup_view} -hold {hold_view}
        set_interactive_constraint_modes [list func_hold]
        set _n [_mirror_source_latency $sdc_hold min max]
        puts "TEMPUS: hold_view <- $sdc_hold (+ $_n -min source latencies mirrored to -max)"
    } else {
        puts "TEMPUS WARN: no hold SDC ($sdc_hold) - hold_view shares the setup SDC, hold slack is NOT trustworthy"
    }
    set_interactive_constraint_modes [all_constraint_modes -active]
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
# Latency-matched virtual clock for I/O timing (2026-09-02; rationale, knobs
# and the corner-consistency rules are in the shared file). Factored out
# 2026-09-03 so the winner chain applies the IDENTICAL model before its hold
# opt - armC showed P&R hold fixing under the raw SDC manufactures both the
# in2reg setup wall and a reg2reg violator at signoff. io_vclk.txt is written
# to $out; port numbers are only quotable with the latency recorded there.
set _vclk_out $out
source [file join $pnr_scripts io_vclk.tcl]
if {!$io_vclk_applied} { puts "TEMPUS WARN: I/O vclk not applied - port groups are latency-skewed" }

report_analysis_summary                          > $out/summary.rpt
report_clock_timing -type summary                > $out/clock_summary.rpt
report_timing -late  -max_paths 50               > $out/setup.rpt
report_timing -early -max_paths 50               > $out/hold.rpt
report_timing -late  -max_paths 1000 -path_type summary > $out/census.rpt
report_constraint -all_violators                 > $out/violators.rpt
# Per-group worst paths: the in2reg reset fan-out buries everything else in
# the ranked reports (armC: 1000/1000 census entries were port-launched), so
# the reg2reg/reg2out truth needs its own file. The summary's reg2reg/in2reg
# categories are NOT path groups (-path_group reg2reg -> "no constrained
# paths"), so select by endpoints instead.
set _regs  [all_registers]
set _ins   [remove_from_collection [all_inputs] [get_ports clk]]
set _outs  [all_outputs]
report_timing -late -from $_regs -to $_regs -max_paths 20 > $out/reg2reg.rpt
report_timing -late -from $_regs -to $_outs -max_paths 20 > $out/reg2out.rpt
report_timing -late -from $_ins  -to $_outs -max_paths 20 > $out/in2out.rpt
report_timing -late -from $_ins  -to $_regs -max_paths 20 > $out/in2reg.rpt
report_timing -late -from [remove_from_collection $_ins [get_ports rst]] -to $_regs -max_paths 20 > $out/in2reg_data.rpt
# SIGNOFF_FULLCLOCK=1: the same worst paths with the clock network expanded
# cell by cell (source latency, every buffer, derates), for reading exactly
# what each clock end is made of. 2026-09-07: the reg2reg launch clock read
# -1.324 ns "(Prop)" on iter19b - an exported-SDC source-latency artefact.
if {[info exists ::env(SIGNOFF_FULLCLOCK)] && $::env(SIGNOFF_FULLCLOCK) eq "1"} {
    report_timing -late -from $_regs -to $_regs -max_paths 1 -path_type full_clock > $out/reg2reg_fullclock.rpt
    report_timing -late -from $_regs -to $_outs -max_paths 1 -path_type full_clock > $out/reg2out_fullclock.rpt
    report_timing -late -from [remove_from_collection $_ins [get_ports rst]] -to $_regs -max_paths 1 -path_type full_clock > $out/in2reg_data_fullclock.rpt
    catch {report_clocks > $out/clocks.rpt}
    catch {report_clock_timing -type latency > $out/clock_latency5.rpt}
}
puts "TEMPUS: reports in $out"
exit
