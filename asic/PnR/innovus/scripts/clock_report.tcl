# clock_report.tcl (2026-09-09, user: "compare the clock skew and latency for
# iter26b and the useful skew version"). Read-only: restore a post-route
# checkpoint and write the clock-tree reports the stage-05 scripts do not emit
# (CTS-stage reports describe the tree BEFORE post-route useful skew moved it).
# Knob: ASIC_CLKRPT_SRC (05_route_opt.enc). Reports in reports/clkrpt/.
set _here [file normalize [file dirname [info script]]]
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
set _src [config_env ASIC_CLKRPT_SRC 05_route_opt.enc]
pnr_restore_stage $_src
setAnalysisMode -analysisType onChipVariation -cppr both
proc cr {msg} { puts "CLKRPT $msg" }
cr "src=$_src"
# report_clock_timing has no -file option in Innovus 21 (04_cts.tcl redirects too)
foreach t {summary skew latency} {
    if {[catch {eval "report_clock_timing -type $t > [pnr_rpt clkrpt $t.rpt]"} m]} { cr "report_clock_timing $t failed: $m" }
}
if {[catch {report_ccopt_skew_groups -file [pnr_rpt clkrpt skew_groups.rpt]} m]} { cr "skew_groups failed: $m" }
if {[catch {report_ccopt_clock_trees -file [pnr_rpt clkrpt clock_trees.rpt]} m]} { cr "clock_trees failed: $m" }
# delay cells useful skew inserted (skewClock) - none in the base run
set _dly [dbGet -e [dbGet -e top.insts.cell.name *dlygate* -p2].name]
cr "dlygate instances = [llength $_dly]"
set _dlyf [open [pnr_rpt clkrpt dlygate_insts.txt] w]; foreach i $_dly { puts $_dlyf $i }; close $_dlyf
cr "DONE"
exit
