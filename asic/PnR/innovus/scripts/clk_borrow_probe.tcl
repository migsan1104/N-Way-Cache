# clk_borrow_probe.tcl (2026-09-09): READ-ONLY probe for the hand-useful-skew
# idea. The 5.5 ns Tempus wall is SRAM dout -> select mux -> the compare-stage
# capture registers (out_rdata[31:0], out_victim_line[127:0]). Delaying THEIR
# clock borrows from the stage after them. Report, period-independent:
#  (1) worst data path delay FROM those registers (downstream borrow room),
#  (2) shortest path delay INTO them (hold room if their clock moves later),
#  (3) their clock leaf structure (how many leaf drivers, fanout per leaf).
# Knob: ASIC_PROBE_SRC (05_pgvia7.enc). Output: reports/clk_borrow/.
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_PROBE_SRC 05_pgvia7.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt clk_borrow io_vclk.txt]]
set io_vclk_applied 0
catch {source [file join [file dirname [info script]] io_vclk.tcl]}
proc pb {msg} { puts "PROBE $msg"; pnr_note "PROBE $msg" }
set regs [get_cells -quiet [config_env ASIC_SKEW_REGS {COMPARE_SELECT_REPLACE_out_rdata_reg* COMPARE_SELECT_REPLACE_out_victim_line_reg*}]]
pb "capture registers: [sizeof_collection $regs]"
set D [file dirname [pnr_rpt clk_borrow x]]
# (1) downstream: worst late paths launched by them
report_timing -late -from $regs -max_paths 20 -path_type full_clock -format {instance cell arc delay arrival required} > $D/from_regs_setup.rpt
# (2) into them: worst early (hold) paths and worst late paths
report_timing -early -to $regs -max_paths 20 -path_type full_clock -format {instance cell arc delay arrival required} > $D/to_regs_hold.rpt
report_timing -late  -to $regs -max_paths 10 -path_type full_clock > $D/to_regs_setup.rpt
# summary numbers: slack + data-path delay (period-independent part) of the worst paths
foreach {tag col} [list from_setup [report_timing -late -from $regs -max_paths 1 -collection] to_hold [report_timing -early -to $regs -max_paths 1 -collection] to_setup [report_timing -late -to $regs -max_paths 1 -collection]] {
    if {[sizeof_collection $col] == 0} { pb "$tag: no path"; continue }
    set p [index_collection $col 0]
    pb "$tag: slack [get_property $p slack] arrival [get_property $p arrival] launch_clk [get_property $p launch_clock_latency] capture_clk [get_property $p capture_clock_latency] start [get_object_name [get_property $p launching_point]] end [get_object_name [get_property $p capturing_point]]"
}
# (3) clock leaf structure: for each register's CLK pin, the driving instance and its fanout
array set leafcnt {}
foreach_in_collection c $regs {
    set n [get_object_name $c]
    set clkpin [get_pins -quiet $n/CLK]
    set net [get_object_name [get_nets -of_objects $clkpin]]
    set drv [dbGet [dbGet -p top.nets.name $net].instTerms.inst.name -e]
    set drvs {}; foreach t [dbGet [dbGet -p top.nets.name $net].instTerms] { if {[dbGet $t.isOutput]} { lappend drvs [dbGet $t.inst.name] } }
    set fan [llength [dbGet [dbGet -p top.nets.name $net].instTerms]]
    foreach d $drvs { if {![info exists leafcnt($d)]} { set leafcnt($d) [list 0 $fan] }; lset leafcnt($d) 0 [expr {[lindex $leafcnt($d) 0] + 1}] }
}
set f [open $D/clock_leaves.txt w]
set nl 0; set shared 0
foreach d [lsort [array names leafcnt]] { lassign $leafcnt($d) ours fan; incr nl; if {$fan > $ours + 1} { incr shared }; puts $f "$d ours=$ours fanout=$fan" }
close $f
pb "clock leaf drivers feeding the capture regs: $nl (of which $shared also drive other flops) -> $D/clock_leaves.txt"
pb "DONE"
exit
