# vss_jumper_eco5.tcl - 2026-09-07 (iter19b, v5: EM). v4 fixed the IR drop
# (VSS 60.8 -> 30.3 mV) but Voltus EM on VSS is still 2.71x the LEF limit,
# all on single-cut via4 where a 2 um strap crosses a 2 um met4 shape:
#   x 2882.6  right strap end <-> jumper      2.4-3.2 mA / 1.2 mA per cut (45)
#   x 21.1    left strap <-> VSS vert stripe   2.0-2.5 mA                 (39)
#   x 6.1     left stub <-> VSS ring                                      (29)
#   x 2893.7  right jumper <-> VSS ring                                   (15)
# plus 14 via3 at (21.1, y_link) = the 1 um met3 leg on the stripe (<=1.29x).
# via4: cut 0.8, spacing 0.8, met5 enclosure 0.31 -> 1 cut across a 2 um
# strap, N cuts along need ~1.6N um. v5 adds, per strap: a met4 pad under
# the strap beyond the VDD stripe on the left (x 18.5..26.5, merges with the
# VSS stripe), a met4 pad under the right strap end (8 um), a 4 um tall met4
# pad over each VSS ring segment at the strap y (2x2 cuts), and a 2 um met3
# pad over the stripe at y_link (x 19.5..22.7, clear of the VDD stripe's
# via pads by x). Then the reroute loop; gate = drc 0, antenna 0, pieces 0,
# and a cut-count audit (via4 cuts at every strap-end pad >= 3).
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 07_vssfix_v4ir.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt vss_eco5 vss_eco5.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }

# ---- 1. geometry
set vss [dbGet -p top.nets.name VSS]; set vdd [dbGet -p top.nets.name VDD]
set ringL ""; set ringR ""; set straps {}; set vL {}; set m3links {}
foreach w [dbGet $vss.sWires] {
    set lay [dbGet $w.layer.name]
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    set horiz [expr {($x2 - $x1) > ($y2 - $y1)}]
    if {$lay eq "met5" && !$horiz && ($y2 - $y1) > 2000} { if {$x1 < 100} { set ringL [list $x1 $x2] } elseif {$x1 > 2800} { set ringR [list $x1 $x2] } }
    if {$lay eq "met5" && $horiz && ($x2 - $x1) > 2000} { lappend straps [list [expr {($y1+$y2)/2.0}] $x1 $x2 [expr {$y2-$y1}] $y1 $y2] }
    if {$lay eq "met4" && !$horiz && ($y2 - $y1) > 100 && $x1 < 100} { lappend vL [list $x1 $y1 $x2 $y2] }
    if {$lay eq "met3" && $horiz && $x1 < 16 && $x2 > 19 && ($y2 - $y1) < 1.2} { lappend m3links [list $x1 $y1 $x2 $y2] }
}
# VDD met4 vertical stripes near the left edge (to keep the strap pad clear of them)
set vddV {}
foreach w [dbGet $vdd.sWires] {
    if {[dbGet $w.layer.name] ne "met4"} continue
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    if {($y2 - $y1) > 100 && ($x1 < 60 || $x2 > 2840)} { lappend vddV [list $x1 $y1 $x2 $y2] }
}
lq "ring L=$ringL R=$ringR straps=[llength $straps] VSS vstripes L=[llength $vL] met3 links=[llength $m3links] VDD vstripes near edges=[llength $vddV]: $vddV"
if {$ringL eq "" || $ringR eq "" || ![llength $straps]} { lq "ECO ABORT: geometry not found"; close $fh; exit 3 }

# ---- 2. pads
set PADL 8.0
set n4 0; set nr 0; set n3 0
foreach s [lsort -real -index 0 $straps] {
    lassign $s yc sx1 sx2 sw y1 y2
    # left strap pad: from 0.4 past the nearest VDD vertical stripe right edge (else strap start+2) to +PADL
    set lx1 [expr {$sx1 + 2.0}]
    foreach v $vddV { lassign $v vx1 vy1 vx2 vy2; if {$vx1 < 60 && $vx2 + 0.4 > $lx1 && $vx1 < $sx1 + 12} { set lx1 [expr {$vx2 + 0.4}] } }
    set lx2 [expr {$lx1 + $PADL}]
    setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met4
    addStripe -nets VSS -layer met4 -direction horizontal -width $sw -area [list $lx1 $y1 $lx2 $y2] \
        -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    incr n4
    # right strap pad: last PADL um of the strap (any VDD vertical stripe there? clip)
    set rx2 $sx2; set rx1 [expr {$sx2 - $PADL}]
    foreach v $vddV { lassign $v vx1 vy1 vx2 vy2; if {$vx2 > 2840 && $vx1 - 0.4 < $rx2 && $vx2 > $rx1} { set rx1 [expr {$vx2 + 0.4}] } }
    addStripe -nets VSS -layer met4 -direction horizontal -width $sw -area [list $rx1 $y1 $rx2 $y2] \
        -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    incr n4
    # ring pads: 4 um tall met4 over each vertical ring segment at the strap y
    set py1 [expr {$yc - 2.0}]; set py2 [expr {$yc + 2.0}]
    addStripe -nets VSS -layer met4 -direction vertical -width [expr {[lindex $ringL 1] - [lindex $ringL 0]}] \
        -area [list [lindex $ringL 0] $py1 [lindex $ringL 1] $py2] \
        -start_from left -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    addStripe -nets VSS -layer met4 -direction vertical -width [expr {[lindex $ringR 1] - [lindex $ringR 0]}] \
        -area [list [lindex $ringR 0] $py1 [lindex $ringR 1] $py2] \
        -start_from left -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    incr nr 2
    # met3 pad over the VSS vertical stripe at this strap's y_link (the L-link leg, if any)
    set vs ""; set bd 1e9
    foreach v $vL { lassign $v vx1 vy1 vx2 vy2; if {$vy1 < $yc && $vy2 > $yc && $vx1 > $sx1 && ($vx1 - $sx1) < $bd} { set vs $v; set bd [expr {$vx1 - $sx1}] } }
    if {$vs ne ""} {
        lassign $vs vx1 vy1 vx2 vy2
        foreach m $m3links { lassign $m mx1 my1 mx2 my2
            set myc [expr {($my1 + $my2)/2.0}]
            if {abs($myc - $yc) > 14.0 || ($myc > $y1 - 0.5 && $myc < $y2 + 0.5)} continue
            setAddStripeMode -stacked_via_top_layer met4 -stacked_via_bottom_layer met3
            addStripe -nets VSS -layer met3 -direction horizontal -width 2.0 \
                -area [list [expr {$vx1 - 0.6}] [expr {$myc - 1.0}] [expr {$vx2 + 0.6}] [expr {$myc + 1.0}]] \
                -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
            incr n3
        }
    }
}
lq "pads: strap-end met4 = $n4, ring met4 = $nr, met3 over stripe at y_link = $n3"
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco5 vss_conn.rpt]

# ---- 3. reroute loop
proc nets_from_drc {rpt} {
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
clearDrc
set drc_rpt [pnr_rpt vss_eco5 drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
set f [open $drc_rpt r]; set t [read $f]; close $f
lq "pass 0 (pads only): verify_drc = $d, markers naming VDD = [regexp -all {Net VDD} $t]"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode true -routeAntennaCellName sky130_fd_sc_hd__diode_2
set a -1; set prev_key ""
for {set pass 1} {$pass <= $_np} {incr pass} {
    set nets [lsort -u [nets_from_drc $drc_rpt]]
    if {![llength $nets] && $d == 0} { lq "pass $pass: nothing to reroute"; break }
    if {![llength $nets]} { lq "pass $pass: $d markers but no signal net named - stop"; break }
    lq "pass $pass: [llength $nets] nets"
    foreach nn $nets { catch {editDelete -net $nn} }
    deselectAll
    foreach nn $nets { catch {selectNet $nn} }
    setNanoRouteMode -routeSelectedNetOnly true
    routeDesign
    setNanoRouteMode -routeSelectedNetOnly false
    deselectAll
    clearDrc
    set drc_rpt [pnr_rpt vss_eco5 drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt vss_eco5 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 07_vssfix5_pass$pass.enc]
    if {$d == 0 && $a == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
if {$a < 0} { set ant_rpt [pnr_rpt vss_eco5 antenna_final.rpt]; verifyProcessAntenna -report $ant_rpt; set a [antenna_count $ant_rpt] }

# ---- 4. gate: connectivity + via4 cut audit at the strap-end pads and ring pads
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco5 vss_conn_final.rpt]
set f [open [pnr_rpt vss_eco5 vss_conn_final.rpt] r]; set t [read $f]; close $f
set pieces 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> pieces
# via4 cuts (M4M5 vias) by location: list of {x y ncuts}
set v45 {}
foreach v [dbGet $vss.sVias] {
    if {![string match "*M4M5*" [dbGet $v.via.name]]} continue
    set vx [dbGet $v.pt_x]; set vy [dbGet $v.pt_y]
    if {$vx > 40 && $vx < 2860} continue
    lappend v45 [list $vx $vy [llength [lindex [dbGet $v.cutRects] 0]]]   ;# dbGet returns {{r1 r2 ..}}: count the inner list
}
proc cuts_in {box} { global v45; lassign $box bx1 by1 bx2 by2; set n 0
    foreach v $v45 { lassign $v vx vy nc; if {$vx >= $bx1 && $vx <= $bx2 && $vy >= $by1 && $vy <= $by2} { incr n $nc } }
    return $n }
set minL 99; set minR 99; set minRL 99; set minRR 99; set bad {}
foreach s [lsort -real -index 0 $straps] {
    lassign $s yc sx1 sx2 sw y1 y2
    set cl [cuts_in [list $sx1 [expr {$y1 - 0.3}] [expr {$sx1 + 14}] [expr {$y2 + 0.3}]]]
    set cr [cuts_in [list [expr {$sx2 - 10}] [expr {$y1 - 0.3}] $sx2 [expr {$y2 + 0.3}]]]
    set crl [cuts_in [list [lindex $ringL 0] [expr {$yc - 2.3}] [lindex $ringL 1] [expr {$yc + 2.3}]]]
    set crr [cuts_in [list [lindex $ringR 0] [expr {$yc - 2.3}] [lindex $ringR 1] [expr {$yc + 2.3}]]]
    if {$cl < $minL} { set minL $cl }; if {$cr < $minR} { set minR $cr }
    if {$crl < $minRL} { set minRL $crl }; if {$crr < $minRR} { set minRR $crr }
    if {$cl < 3 || $cr < 3 || $crl < 2 || $crr < 2} { lappend bad [format "y=%s(L=%d R=%d ringL=%d ringR=%d)" $yc $cl $cr $crl $crr] }
}
lq "via4 cut audit: min per strap: left strap pad $minL, right strap pad $minR, left ring $minRL, right ring $minRR; below target: [llength $bad] $bad"
catch {
    report_timing -early -max_paths 1 -path_type summary > [pnr_rpt vss_eco5 hold_after.rpt]
    report_timing -late  -max_paths 1 -path_type summary > [pnr_rpt vss_eco5 setup_after.rpt]
}
lq "VSS ECO5: verify_drc = $d antenna = $a vss_pieces = $pieces cut_audit_fail = [llength $bad]"
pnr_note "VSS ECO5: verify_drc = $d antenna = $a vss_pieces = $pieces cut_audit_fail = [llength $bad]"
if {$d == 0 && $a == 0 && $pieces == 0 && ![llength $bad]} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix5_dirty.enc]; close $fh; exit 2
