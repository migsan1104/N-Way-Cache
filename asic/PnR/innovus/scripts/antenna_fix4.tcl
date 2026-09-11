# antenna_fix4.tcl - 2026-09-06 (iter19b). Loop of antenna_fix3 + legalize:
#   pass p: attachDiode on every pin in the current antenna report (prefix
#   ANTDIODE<p>_), move every ANTDIODE* that overlaps another instance to the
#   nearest free run of sites (same row first, then +-1..3 rows, +-40 um),
#   ecoRoute (TD/SI/antenna-fix off, NO refinePlace), verify_drc,
#   verifyProcessAntenna, overlap recount. Stop when drc = antenna = overlaps
#   = 0 (save ASIC_ANTENNA_DST, exit 0) or after ASIC_ANTENNA_PASSES passes
#   (save 05_antenna_fix4_dirty.enc, exit 2).
#   ASIC_ANTENNA_SRC  checkpoint (05_antenna_legalize_dirty.enc)
#   ASIC_ANTENNA_RPT  antenna report to start from
#   ASIC_ANTENNA_DST  checkpoint written when clean (05_antenna_fixed.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ANTENNA_SRC 05_antenna_legalize_dirty.enc]
set _dst [config_env ASIC_ANTENNA_DST 05_antenna_fixed.enc]
set _np  [config_env ASIC_ANTENNA_PASSES 3]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt antenna_fix4 fix4.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
set SITE_W 0.46
set ROW_H  2.72
proc box_of {i} { return [lindex [dbGet $i.box] 0] }
proc overlappers {i} {
    set b [box_of $i]; set me [dbGet $i.name]; set out {}
    foreach o [dbQuery -area $b -objType inst] {
        if {[dbGet $o.name] eq $me} continue
        lassign [box_of $o] ox1 oy1 ox2 oy2
        lassign $b x1 y1 x2 y2
        if {$ox1 < $x2 - 0.001 && $ox2 > $x1 + 0.001 && $oy1 < $y2 - 0.001 && $oy2 > $y1 + 0.001} { lappend out $o }
    }
    return $out
}
proc find_gap {y0 xa xb need} {
    global ROW_H SITE_W
    set insts [dbQuery -area [list $xa $y0 $xb [expr {$y0 + $ROW_H}]] -objType inst]
    set boxes {}; set orient ""
    foreach o $insts {
        lassign [box_of $o] x1 y1 x2 y2
        if {abs($y1 - $y0) > 0.01} continue
        lappend boxes [list $x1 $x2]
        if {$orient eq ""} { set orient [dbGet $o.orient] }
    }
    if {$orient eq ""} { return {} }
    set boxes [lsort -real -index 0 $boxes]
    set cur $xa
    foreach bx $boxes {
        lassign $bx x1 x2
        if {$x1 - $cur >= $need - 0.001 && $cur > $xa} { return [list $cur $orient] }
        if {$x2 > $cur} { set cur $x2 }
    }
    return {}
}
proc legalize_diodes {} {
    global ROW_H
    set moved 0; set failed 0
    foreach d [dbGet -p top.insts.name ANTDIODE*] {
        if {![llength [overlappers $d]]} continue
        set nm [dbGet $d.name]
        lassign [box_of $d] x1 y1 x2 y2
        set w [expr {$x2 - $x1}]
        set placed 0
        foreach dr {0 1 -1 2 -2 3 -3} {
            set y0 [expr {$y1 + $dr * $ROW_H}]
            set g [find_gap $y0 [expr {$x1 - 40.0}] [expr {$x2 + 40.0}] $w]
            if {[llength $g]} {
                lassign $g gx gor
                placeInstance $nm $gx $y0 $gor
                if {![llength [overlappers $d]]} { incr moved; set placed 1; break }
            }
        }
        if {!$placed} { lq "NO FREE SITE for $nm"; incr failed }
    }
    return [list $moved $failed]
}
proc pins_from_rpt {rpt} {
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
proc overlap_count {} { set n 0; foreach d [dbGet -p top.insts.name ANTDIODE*] { if {[llength [overlappers $d]]} { incr n } }; return $n }
set rpt [config_env ASIC_ANTENNA_RPT [pnr_rpt antenna_fix3 antenna_legalize.rpt]]
lq "src=$_src report=$rpt markers=[llength [dbGet -e top.markers]] diodes=[llength [dbGet -p top.insts.name ANTDIODE*]]"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false -drouteFixAntenna false
set d -1; set a -1; set ov -1
for {set pass 1} {$pass <= $_np} {incr pass} {
    set pins [pins_from_rpt $rpt]
    set n 0
    foreach p $pins {
        lassign $p inst pin
        if {[catch {attachDiode -diodeCell sky130_fd_sc_hd__diode_2 -pin $inst $pin -prefix ANTDIODE4${pass}_} m]} { lq "attachDiode $inst/$pin FAILED: $m" } else { incr n }
    }
    lassign [legalize_diodes] mv fl
    lq "pass $pass: pins=[llength $pins] diodes_attached=$n moved=$mv failed_moves=$fl"
    setNanoRouteMode -routeWithEco true
    ecoRoute
    setNanoRouteMode -routeWithEco false
    clearDrc
    verify_drc -limit 100000 -report [pnr_rpt antenna_fix4 drc_pass$pass.rpt]
    set d [llength [dbGet -e top.markers]]
    set rpt [pnr_rpt antenna_fix4 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $rpt
    set a [antenna_count $rpt]
    set ov [overlap_count]
    lq "pass $pass: verify_drc = $d antenna = $a overlaps = $ov"
    saveDesign [pnr_ckpt 05_antenna_fix4_pass$pass.enc]
    if {$d == 0 && $a == 0 && $ov == 0 && $fl == 0} { break }
}
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt antenna_fix4 hold_after.rpt]}
lq "ANTENNA FIX4: verify_drc = $d antenna = $a overlaps = $ov"
pnr_note "ANTENNA FIX4: verify_drc = $d antenna = $a overlaps = $ov"
if {$d == 0 && $a == 0 && $ov == 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 05_antenna_fix4_dirty.enc]
close $fh
exit 2
