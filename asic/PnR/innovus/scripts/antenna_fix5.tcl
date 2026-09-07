# antenna_fix5.tcl - 2026-09-06 (iter19b). The 26 nets attachDiode could not
# fix (diodes legalized 25-38 um away, wired on met1 only, D.Area 0 in the
# report): rip up ONLY those nets and let NanoRoute fix them itself -
# pass 1 layer hopping (drouteFixAntenna, no diodes), pass 2 (if needed)
# router-inserted, router-legalized diodes. TD/SI off, no refinePlace.
# Exit 0 iff verify_drc = 0 & antenna = 0 & no ANTDIODE overlaps.
#   ASIC_ANTENNA_SRC  checkpoint (05_antenna_fix4_pass1.enc)
#   ASIC_ANTENNA_RPT  antenna report listing the nets
#   ASIC_ANTENNA_DST  checkpoint written when clean (05_antenna_fixed.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ANTENNA_SRC 05_antenna_fix4_pass1.enc]
set _dst [config_env ASIC_ANTENNA_DST 05_antenna_fixed.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt antenna_fix5 fix5.txt] w]
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
proc nets_from_rpt {rpt} {
    set out {}; set f [open $rpt r]
    while {[gets $f l] >= 0} { if {[regexp {^(\S+)\s+\(\d+\)\s*$} $l -> n]} { lappend out $n } }
    close $f; return [lsort -u $out]
}
proc antenna_count {rpt} {
    set f [open $rpt r]; set t [read $f]; close $f
    if {[regexp {No Violations Found} $t]} { return 0 }
    if {[regexp {Total number of process antenna violations:\s*(\d+)} $t -> a]} { return $a }
    return -1
}
set rpt [config_env ASIC_ANTENNA_RPT [pnr_rpt antenna_fix4 antenna_pass1.rpt]]
set d -1; set a -1; set ov -1
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false
foreach pass {1 2} {
    set nets [nets_from_rpt $rpt]
    if {![llength $nets]} { break }
    if {$pass == 1} {
        setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode false
    } else {
        setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode true -routeAntennaCellName sky130_fd_sc_hd__diode_2
    }
    lq "pass $pass: [llength $nets] nets rip-up + reroute (insertDiode=[expr {$pass==2}])"
    foreach n $nets { editDelete -net $n }
    deselectAll
    foreach n $nets { selectNet $n }
    setNanoRouteMode -routeSelectedNetOnly true
    routeDesign
    setNanoRouteMode -routeSelectedNetOnly false
    deselectAll
    clearDrc
    verify_drc -limit 100000 -report [pnr_rpt antenna_fix5 drc_pass$pass.rpt]
    set d [llength [dbGet -e top.markers]]
    set rpt [pnr_rpt antenna_fix5 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $rpt
    set a [antenna_count $rpt]
    set ov [overlap_count]
    lq "pass $pass: verify_drc = $d antenna = $a diode_overlaps = $ov"
    saveDesign [pnr_ckpt 05_antenna_fix5_pass$pass.enc]
    if {$d == 0 && $a == 0 && $ov == 0} { break }
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt antenna_fix5 hold_after.rpt]}
lq "ANTENNA FIX5: verify_drc = $d antenna = $a diode_overlaps = $ov"
pnr_note "ANTENNA FIX5: verify_drc = $d antenna = $a diode_overlaps = $ov"
if {$d == 0 && $a == 0 && $ov == 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
close $fh
exit 2
