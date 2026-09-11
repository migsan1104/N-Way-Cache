# antenna_fix3.tcl - 2026-09-06 (iter19b, 122 antenna violations the chain's
# antenna_eco.tcl could not move). Report-driven version of antenna_fix2.tcl:
# parse a verifyProcessAntenna report, attachDiode on EVERY listed pin, then
# ecoRoute with antenna auto-fix OFF and no refinePlace (the 16b lesson),
# verify, and repeat once on whatever is left. Exit 0 iff drc = 0 & antenna = 0.
#   ASIC_ANTENNA_SRC  checkpoint (05_route_opt.enc = chain HOLDCLEAN state)
#   ASIC_ANTENNA_RPT  report to start from (reports/antenna_eco/antenna_base.rpt)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ANTENNA_SRC 05_route_opt.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt antenna_fix3 antenna_fix3.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
proc pins_from_rpt {rpt} {
    # "  INST  (cell) PIN" lines under each "NET (n)" header
    set out {}
    set f [open $rpt r]
    while {[gets $f l] >= 0} {
        if {[regexp {^\s+(\S+)\s+\(sky130_\S+\)\s+(\S+)\s*$} $l -> inst pin]} { lappend out [list $inst $pin] }
    }
    close $f
    return [lsort -u $out]
}
proc antenna_count {rpt} {
    set f [open $rpt r]; set t [read $f]; close $f
    if {[regexp {No Violations Found} $t]} { return 0 }
    if {[regexp {Total number of process antenna violations:\s*(\d+)} $t -> a]} { return $a }
    return -1
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
set rpt [config_env ASIC_ANTENNA_RPT [pnr_rpt antenna_eco antenna_base.rpt]]
lq "src=$_src report=$rpt markers=[llength [dbGet -e top.markers]]"
set d -1; set a -1
for {set pass 1} {$pass <= 2} {incr pass} {
    set pins [pins_from_rpt $rpt]
    lq "pass $pass: [llength $pins] pins to diode"
    if {![llength $pins]} { break }
    set n 0
    foreach p $pins {
        lassign $p inst pin
        if {[catch {attachDiode -diodeCell sky130_fd_sc_hd__diode_2 -pin $inst $pin -prefix ANTDIODE${pass}_} m]} { lq "attachDiode $inst/$pin FAILED: $m" } else { incr n }
    }
    lq "pass $pass: diodes attached: $n"
    setNanoRouteMode -routeWithEco true
    ecoRoute
    setNanoRouteMode -routeWithEco false
    clearDrc
    verify_drc -limit 100000 -report [pnr_rpt antenna_fix3 drc_pass$pass.rpt]
    set d [llength [dbGet -e top.markers]]
    set rpt [pnr_rpt antenna_fix3 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $rpt
    set a [antenna_count $rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 05_antenna_fixed.enc]
    if {$a == 0} { break }
}
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt antenna_fix3 hold_after.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt antenna_fix3 reg2reg_after.rpt]}
lq "ANTENNA FIX3: verify_drc = $d antenna = $a"
pnr_note "ANTENNA FIX3: verify_drc = $d antenna = $a"
close $fh
if {$d == 0 && $a == 0} { exit 0 } else { exit 2 }
