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

report_analysis_summary                          > $out/summary.rpt
report_timing -late  -max_paths 50               > $out/setup.rpt
report_timing -early -max_paths 50               > $out/hold.rpt
report_timing -late  -max_paths 1000 -path_type summary > $out/census.rpt
report_constraint -all_violators                 > $out/violators.rpt
puts "TEMPUS: reports in $out"
exit
