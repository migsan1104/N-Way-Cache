# antenna_fix6.tcl - 2026-09-06 (iter19b). Converge DRC + antenna together on
# a small set of nets: each pass rips up every net named in the current
# verify_drc report AND every net in the current antenna report, reroutes
# only those (TD/SI off, antenna fixer on, router-placed diodes allowed),
# verifies both, and saves. Stops at drc = antenna = overlaps = 0 or after
# ASIC_ANTENNA_PASSES passes. No refinePlace, no attachDiode.
#   ASIC_ANTENNA_SRC  checkpoint to start from
#   ASIC_ANTENNA_DRC  verify_drc report matching that checkpoint
#   ASIC_ANTENNA_RPT  antenna report matching that checkpoint
#   ASIC_ANTENNA_DST  checkpoint written when clean (05_antenna_fixed.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ANTENNA_SRC 05_antenna_fix5_pass2.enc]
set _dst [config_env ASIC_ANTENNA_DST 05_antenna_fixed.enc]
set _np  [config_env ASIC_ANTENNA_PASSES 4]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt antenna_fix6 fix6.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
proc box_of {i} { return [lindex [dbGet $i.box] 0] }
proc overlap_count {} {
    set n 0
    foreach d [dbGet -p top.insts.name ANTDIODE*] {
        set b [box_of $d]; set me [dbGet $d.name]; lassign $b x1 y1 x2 y2
        foreach o [dbQuery -area $b -objType inst] {
            if {[dbGet $o.name] eq $me} continue
            lassign [box_of $o] ox1 oy1 ox2 oy2
            if {$ox1 < $x2 - 0.001 && $ox2 > $x1 + 0.001 && $oy1 < $y2 - 0.001 && $oy2 > $y1 + 0.001} { incr n; break }
        }
    }
    return $n
}
proc nets_from_ant {rpt} {
    set out {}; if {![file readable $rpt]} { return $out }
    set f [open $rpt r]
    while {[gets $f l] >= 0} { if {[regexp {^(\S+)\s+\(\d+\)\s*$} $l -> n]} { lappend out $n } }
    close $f; return $out
}
proc nets_from_drc {rpt} {
    # "Regular Wire of Net X" / "Pin of Cell Y" - nets only; skip PG and clock nets? no: reroute them too
    set out {}; if {![file readable $rpt]} { return $out }
    set f [open $rpt r]
    while {[gets $f l] >= 0} { foreach {_ n} [regexp -all -inline {Wire of Net (\S+)} $l] { if {$n ne "VDD" && $n ne "VSS"} { lappend out $n } } }
    close $f; return $out
}
proc antenna_count {rpt} {
    set f [open $rpt r]; set t [read $f]; close $f
    if {[regexp {No Violations Found} $t]} { return 0 }
    if {[regexp {Total number of process antenna violations:\s*(\d+)} $t -> a]} { return $a }
    return -1
}
set drc_rpt [config_env ASIC_ANTENNA_DRC [pnr_rpt antenna_fix5 drc_pass2.rpt]]
set ant_rpt [config_env ASIC_ANTENNA_RPT [pnr_rpt antenna_fix5 antenna_pass2.rpt]]
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode true -routeAntennaCellName sky130_fd_sc_hd__diode_2
set d -1; set a -1; set ov -1; set prev_key ""
for {set pass 1} {$pass <= $_np} {incr pass} {
    set nets [lsort -u [concat [nets_from_drc $drc_rpt] [nets_from_ant $ant_rpt]]]
    if {![llength $nets]} { lq "pass $pass: nothing to reroute"; break }
    lq "pass $pass: [llength $nets] nets: $nets"
    foreach n $nets { catch {editDelete -net $n} }
    deselectAll
    foreach n $nets { catch {selectNet $n} }
    setNanoRouteMode -routeSelectedNetOnly true
    routeDesign
    setNanoRouteMode -routeSelectedNetOnly false
    deselectAll
    clearDrc
    set drc_rpt [pnr_rpt antenna_fix6 drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt antenna_fix6 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    set ov [overlap_count]
    lq "pass $pass: verify_drc = $d antenna = $a diode_overlaps = $ov"
    saveDesign [pnr_ckpt 05_antenna_fix6_pass$pass.enc]
    if {$d == 0 && $a == 0 && $ov == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt antenna_fix6 hold_after.rpt]}
lq "ANTENNA FIX6: verify_drc = $d antenna = $a diode_overlaps = $ov"
pnr_note "ANTENNA FIX6: verify_drc = $d antenna = $a diode_overlaps = $ov"
if {$d == 0 && $a == 0 && $ov == 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
close $fh
exit 2
