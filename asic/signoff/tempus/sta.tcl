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
# DRAFT 2026-08-28 - not yet shaken down (waits on run 1's stage 09 outputs).
set pnr_scripts [file join $env(SIGNOFF_PNR_DIR) scripts]
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

report_analysis_summary                          > $out/summary.rpt
report_timing -late  -max_paths 50               > $out/setup.rpt
report_timing -early -max_paths 50               > $out/hold.rpt
report_timing -late  -max_paths 1000 -path_type summary > $out/census.rpt
report_constraint -all_violators                 > $out/violators.rpt
puts "TEMPUS: reports in $out"
exit
