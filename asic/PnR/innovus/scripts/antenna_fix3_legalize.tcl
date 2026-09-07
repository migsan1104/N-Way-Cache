# antenna_fix3_legalize.tcl - 2026-09-06 (iter19b). attachDiode drops diodes
# on top of neighbours when the row is full (ANTDIODE1__g2187271_B1 over
# g2186340 -> li1 SHORT with g2186340/B2 that a reroute cannot remove).
# Global refinePlace is forbidden (46k-instance wreck, chain19b). This
# script: for every ANTDIODE* instance that overlaps another instance, find
# the nearest free run of >= 2 sites in the same or neighbouring rows, move
# it there with placeInstance, then ecoRoute, verify_drc, antenna, and
# overwrite ASIC_LEGALIZE_DST iff both are 0. Exit 0 iff clean.
#   ASIC_ANTENNA_SRC  checkpoint to fix (05_antenna_fixed.enc)
#   ASIC_ANTENNA_DST  checkpoint to write when clean (05_antenna_fixed.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ANTENNA_SRC 05_antenna_fixed.enc]
set _dst [config_env ASIC_ANTENNA_DST 05_antenna_fixed.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt antenna_fix3 legalize.txt] w]
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
        # strict interior overlap (abutting edges are fine)
        if {$ox1 < $x2 - 0.001 && $ox2 > $x1 + 0.001 && $oy1 < $y2 - 0.001 && $oy2 > $y1 + 0.001} { lappend out $o }
    }
    return $out
}
# free run of >= need um in row [y0,y0+ROW_H) between xa and xb; returns {x orient} or {}
proc find_gap {y0 xa xb need} {
    global ROW_H SITE_W
    set insts [dbQuery -area [list $xa $y0 $xb [expr {$y0 + $ROW_H}]] -objType inst]
    set boxes {}
    set orient ""
    foreach o $insts {
        lassign [box_of $o] x1 y1 x2 y2
        if {abs($y1 - $y0) > 0.01} continue   ;# only cells whose row origin is this row
        lappend boxes [list $x1 $x2]
        if {$orient eq ""} { set orient [dbGet $o.orient] }
    }
    if {$orient eq ""} { return {} }        ;# empty window: no reference for orientation, skip
    set boxes [lsort -real -index 0 $boxes]
    set cur $xa
    foreach bx $boxes {
        lassign $bx x1 x2
        if {$x1 - $cur >= $need - 0.001 && $cur > $xa} { return [list $cur $orient] }
        if {$x2 > $cur} { set cur $x2 }
    }
    return {}
}
set diodes [dbGet -p top.insts.name ANTDIODE*]
lq "src=$_src diodes=[llength $diodes] markers_before=[llength [dbGet -e top.markers]]"
set moved 0; set failed 0
foreach d $diodes {
    set ov [overlappers $d]
    if {![llength $ov]} continue
    set nm [dbGet $d.name]
    lassign [box_of $d] x1 y1 x2 y2
    set w [expr {$x2 - $x1}]
    lq "overlap: $nm box=[box_of $d] over [join [dbGet $ov.name] ,]"
    set placed 0
    # same row first, then +-1, +-2, +-3 rows; window +-40 um
    foreach dr {0 1 -1 2 -2 3 -3} {
        set y0 [expr {$y1 + $dr * $ROW_H}]
        set g [find_gap $y0 [expr {$x1 - 40.0}] [expr {$x2 + 40.0}] $w]
        if {[llength $g]} {
            lassign $g gx gor
            placeInstance $nm $gx $y0 $gor
            # confirm no overlap after the move
            if {![llength [overlappers $d]]} { lq "moved $nm -> ($gx,$y0) $gor (row offset $dr)"; incr moved; set placed 1; break }
            lq "candidate ($gx,$y0) still overlaps, trying next"
        }
    }
    if {!$placed} { lq "NO FREE SITE for $nm"; incr failed }
}
lq "moved=$moved failed=$failed"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false -drouteFixAntenna false
setNanoRouteMode -routeWithEco true
ecoRoute
setNanoRouteMode -routeWithEco false
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_fix3 drc_legalize.rpt]
set dcount [llength [dbGet -e top.markers]]
set rpt [pnr_rpt antenna_fix3 antenna_legalize.rpt]
verifyProcessAntenna -report $rpt
set f [open $rpt r]; set t [read $f]; close $f
set a -1
if {[regexp {No Violations Found} $t]} { set a 0 } elseif {[regexp {Total number of process antenna violations:\s*(\d+)} $t -> _a]} { set a $_a }
set still 0
foreach d $diodes { if {[llength [overlappers $d]]} { incr still } }
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt antenna_fix3 hold_legalize.rpt]}
lq "LEGALIZE: verify_drc = $dcount antenna = $a diode_overlaps_left = $still failed_moves = $failed"
pnr_note "ANTENNA FIX3 LEGALIZE: verify_drc = $dcount antenna = $a overlaps_left = $still"
if {$dcount == 0 && $a == 0 && $still == 0 && $failed == 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 05_antenna_legalize_dirty.enc]
close $fh
exit 2
