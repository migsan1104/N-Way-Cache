# vss_jumper_eco4.tcl - 2026-09-07 (iter19b, v4). v3's straight met3 links
# (stub -> first VSS met4 vertical stripe, at the strap y) got 2 vias on only
# 16 of 48 straps ("ViaGen created 2 via" 16x, 1 via 27x, 0 via 5x): the VDD
# met4 vertical stripe at x 16.1-18.1 stacks vias down to every VPWR rail, so
# wherever a VPWR rail crosses the 2 um strap band there is a VDD met3 pad in
# the link's path and addStripe trims the link around it.
# v4: per left strap, audit the real M3M4 VSS vias in the link box; if fewer
# than one at each end, add an L-link: a met3 vertical piece over the stub
# (x stub_end-1.4 .. stub_end, strap band -> y_link) and a met3 horizontal at
# y_link = the nearest VSS met3 pad on the vertical stripe (a VGND rail height:
# the VDD stripe has no pads there, the VSS stripe already has one), from the
# stub x to the far edge of the VSS stripe. Same reroute loop and gate; the
# gate now requires every strap to have a via at BOTH ends.
#   ASIC_ECO_SRC  checkpoint (07_vssfix_v3partial.enc = v3 result, renamed)
#   ASIC_ECO_DST  checkpoint to write when clean (07_vssfix.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 07_vssfix_v3partial.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt vss_eco4 vss_eco4.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }

# ---- 1. geometry
set vss [dbGet -p top.nets.name VSS]
set ringL ""; set straps {}; set hL {}; set vL {}; set m3L {}
foreach w [dbGet $vss.sWires] {
    set lay [dbGet $w.layer.name]
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    set horiz [expr {($x2 - $x1) > ($y2 - $y1)}]
    if {$lay eq "met5" && !$horiz && ($y2 - $y1) > 2000 && $x1 < 100} { set ringL [list $x1 $x2] }
    if {$lay eq "met5" && $horiz && ($x2 - $x1) > 2000} { lappend straps [list [expr {($y1+$y2)/2.0}] $x1 $x2 [expr {$y2-$y1}] $y1 $y2] }
    if {$lay eq "met4" && $horiz && ($x2 - $x1) < 100 && $x1 < 100} { lappend hL [list $x1 $y1 $x2 $y2] }
    if {$lay eq "met4" && !$horiz && ($y2 - $y1) > 100 && $x1 < 100} { lappend vL [list $x1 $y1 $x2 $y2] }
    if {$lay eq "met3" && $x1 < 100} { lappend m3L [list $x1 $y1 $x2 $y2] }
}
# VSS vias near the left edge, by location (sViaInst has pt_x/pt_y, no box - dbSchema sViaInst).
# viasL = M3M4 only (the audit); allVssL = every VSS via with x < 30 (the vertical stripe's
# via stacks to the VGND rails give the VGND rail heights: via-master pads are not sWires).
set viasL {}; set allVssL {}
foreach v [dbGet $vss.sVias] {
    set vx [dbGet $v.pt_x]; set vy [dbGet $v.pt_y]
    if {$vx >= 30} continue
    lappend allVssL [list $vx $vy]
    if {[string match "*M3M4*" [dbGet $v.via.name]]} { lappend viasL [list $vx $vy] }
}
set vdd [dbGet -p top.nets.name VDD]; set vddL {}
foreach v [dbGet $vdd.sVias] {
    set vx [dbGet $v.pt_x]; set vy [dbGet $v.pt_y]
    if {$vx < 30} { lappend vddL [list $vx $vy] }
}
lq "left: VSS vias x<30 = [llength $allVssL], VDD vias x<30 = [llength $vddL]"
lq "left: ring=$ringL straps=[llength $straps] stubs=[llength $hL] vstripes=[llength $vL] met3 pieces=[llength $m3L] M3M4 vias=[llength $viasL]"
if {$ringL eq "" || ![llength $straps] || ![llength $vL]} { lq "ECO ABORT: geometry not found"; close $fh; exit 3 }
proc vias_in {box} {
    global viasL; lassign $box bx1 by1 bx2 by2; set n 0
    foreach v $viasL { lassign $v vx vy; if {$vx >= $bx1 && $vx <= $bx2 && $vy >= $by1 && $vy <= $by2} { incr n } }
    return $n
}

# ---- 2. audit + L-links
setAddStripeMode -stacked_via_top_layer met4 -stacked_via_bottom_layer met3
set nok 0; set nfix 0; set nskip 0
foreach s [lsort -real -index 0 $straps] {
    lassign $s yc sx1 sx2 sw y1 y2
    set stub ""
    foreach h $hL { lassign $h hx1 hy1 hx2 hy2; if {$hy1 < $yc && $hy2 > $yc} { set stub $h; break } }
    if {$stub eq ""} { lq "y=$yc: no stub - skip"; incr nskip; continue }
    lassign $stub hx1 hy1 hx2 hy2
    if {$hx2 >= $sx1 + 0.5} { incr nok; continue }
    set vs ""; set bd 1e9
    foreach v $vL { lassign $v vx1 vy1 vx2 vy2; if {$vy1 < $yc && $vy2 > $yc && $vx1 > $hx2 && ($vx1 - $hx2) < $bd} { set vs $v; set bd [expr {$vx1 - $hx2}] } }
    if {$vs eq ""} { lq "y=$yc: no VSS vertical stripe - skip"; incr nskip; continue }
    lassign $vs vx1 vy1 vx2 vy2
    # existing straight link: via on the stub AND via on the stripe, both inside the strap band?
    set a [vias_in [list [expr {$hx2 - 3.0}] [expr {$y1 - 0.3}] $hx2 [expr {$y2 + 0.3}]]]
    set b [vias_in [list $vx1 [expr {$y1 - 0.3}] $vx2 [expr {$y2 + 0.3}]]]
    if {$a > 0 && $b > 0} { lq "y=$yc: v3 link OK (vias stub=$a stripe=$b)"; incr nok; continue }
    # y_link = nearest VSS via height on the vertical stripe (a VGND rail crossing), outside the
    # strap band, and at least 1.5 um from any VDD via height on x 15..19 (the VDD stripe's pads)
    set lyc ""; set bd 1e9
    foreach vv $allVssL { lassign $vv vvx vvy
        if {$vvx < $vx1 - 0.1 || $vvx > $vx2 + 0.1} continue
        if {$vvy > $y1 - 0.8 && $vvy < $y2 + 0.8} continue
        set clear 1
        foreach dv $vddL { lassign $dv dvx dvy; if {$dvx > 15.0 && $dvx < 19.0 && abs($dvy - $vvy) < 1.5} { set clear 0; break } }
        if {!$clear} continue
        if {abs($vvy - $yc) < $bd} { set bd [expr {abs($vvy - $yc)}]; set lyc $vvy } }
    if {$lyc eq "" || $bd > 12.0} { lq "y=$yc: no clear VSS via height on the stripe within 12 um (bd=$bd) - skip"; incr nskip; continue }
    set lw 1.0
    set ly1 [expr {$lyc - $lw/2.0}]; set ly2 [expr {$lyc + $lw/2.0}]
    set kx1 [expr {$hx2 - 1.4}]; set kx2 $hx2
    # vertical piece over the stub end, from the strap band to y_link
    set vy_lo [expr {min($y1, $ly1)}]; set vy_hi [expr {max($y2, $ly2)}]
    addStripe -nets VSS -layer met3 -direction vertical -width [expr {$kx2 - $kx1}] \
        -area [list $kx1 $vy_lo $kx2 $vy_hi] \
        -start_from left -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    # horizontal piece at y_link from the stub x to the far edge of the VSS stripe
    addStripe -nets VSS -layer met3 -direction horizontal -width $lw \
        -area [list $kx1 $ly1 $vx2 $ly2] \
        -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    lq "y=$yc: L-link added (stub end $hx2, y_link $lyc, stripe $vx1-$vx2; v3 vias stub=$a stripe=$b)"
    incr nfix
}
lq "audit: connected = $nok, L-links added = $nfix, skipped = $nskip"

# ---- 3. reroute loop (antenna_fix6 recipe)
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
set drc_rpt [pnr_rpt vss_eco4 drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
lq "pass 0 (L-links only): verify_drc = $d"
set pgshort [expr {[llength [dbGet -e top.markers]] > 0 ? [regexp -all {Net VDD} [exec cat $drc_rpt]] : 0}]
lq "pass 0: markers mentioning VDD = $pgshort (a VSS-VDD short cannot be rerouted away)"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode true -routeAntennaCellName sky130_fd_sc_hd__diode_2
set a -1; set prev_key ""
for {set pass 1} {$pass <= $_np} {incr pass} {
    set nets [lsort -u [nets_from_drc $drc_rpt]]
    if {![llength $nets] && $d == 0} { lq "pass $pass: nothing to reroute"; break }
    if {![llength $nets]} { lq "pass $pass: $d markers but no signal net named - stop"; break }
    lq "pass $pass: [llength $nets] nets: $nets"
    foreach nn $nets { catch {editDelete -net $nn} }
    deselectAll
    foreach nn $nets { catch {selectNet $nn} }
    setNanoRouteMode -routeSelectedNetOnly true
    routeDesign
    setNanoRouteMode -routeSelectedNetOnly false
    deselectAll
    clearDrc
    set drc_rpt [pnr_rpt vss_eco4 drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt vss_eco4 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 07_vssfix4_pass$pass.enc]
    if {$d == 0 && $a == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
if {$a < 0} { set ant_rpt [pnr_rpt vss_eco4 antenna_final.rpt]; verifyProcessAntenna -report $ant_rpt; set a [antenna_count $ant_rpt] }

# ---- 4. gate: connectivity + re-audit the vias after everything
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco4 vss_conn_final.rpt]
set f [open [pnr_rpt vss_eco4 vss_conn_final.rpt] r]; set t [read $f]; close $f
set pieces 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> pieces
set viasL {}
foreach v [dbGet $vss.sVias] {
    set vn [dbGet $v.via.name]; if {![string match "*M3M4*" $vn]} continue
    set vx [dbGet $v.pt_x]; set vy [dbGet $v.pt_y]
    if {$vx < 30} { lappend viasL [list $vx $vy] }
}
set conn 0; set unconn {}
foreach s [lsort -real -index 0 $straps] {
    lassign $s yc sx1 sx2 sw y1 y2
    set stub ""; foreach h $hL { lassign $h hx1 hy1 hx2 hy2; if {$hy1 < $yc && $hy2 > $yc} { set stub $h; break } }
    if {$stub eq ""} { lappend unconn $yc; continue }
    lassign $stub hx1 hy1 hx2 hy2
    if {$hx2 >= $sx1 + 0.5} { incr conn; continue }
    set vs ""; set bd 1e9
    foreach v $vL { lassign $v vx1 vy1 vx2 vy2; if {$vy1 < $yc && $vy2 > $yc && $vx1 > $hx2 && ($vx1 - $hx2) < $bd} { set vs $v; set bd [expr {$vx1 - $hx2}] } }
    lassign $vs vx1 vy1 vx2 vy2
    # a via on the stub (any y within 14 um of the band) AND a via on the stripe within 14 um
    set a1 [vias_in [list [expr {$hx2 - 3.0}] [expr {$y1 - 14}] $hx2 [expr {$y2 + 14}]]]
    set b1 [vias_in [list $vx1 [expr {$y1 - 14}] $vx2 [expr {$y2 + 14}]]]
    if {$a1 > 0 && $b1 > 0} { incr conn } else { lappend unconn [format "%s(stub=%d,stripe=%d)" $yc $a1 $b1] }
}
lq "final audit: straps with a via at both ends = $conn / [llength $straps]; unconnected: $unconn"
catch {
    report_timing -early -max_paths 1 -path_type summary > [pnr_rpt vss_eco4 hold_after.rpt]
    report_timing -late  -max_paths 1 -path_type summary > [pnr_rpt vss_eco4 setup_after.rpt]
}
lq "VSS ECO4: verify_drc = $d antenna = $a vss_pieces = $pieces connected = $conn/[llength $straps]"
pnr_note "VSS ECO4: verify_drc = $d antenna = $a vss_pieces = $pieces connected = $conn/[llength $straps]"
if {$d == 0 && $a == 0 && $pieces == 0 && $conn == [llength $straps]} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix4_dirty.enc]; close $fh; exit 2
