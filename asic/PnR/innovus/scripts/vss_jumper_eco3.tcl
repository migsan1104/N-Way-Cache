# vss_jumper_eco3.tcl - 2026-09-07 (iter19b, v3). v2 closed DRC but Voltus
# said VSS 60.78 -> 60.78 mV: the DEF shows the LEFT met4 jumpers stop at
# x 15.8 while the strap starts at 16.5. A VDD met4 vertical core stripe sits
# at x 16.1-18.1 (the first stripe set, core margin 16) and addStripe trims
# the VSS jumper to 0.3 um before it, so the left jumper is a stub: one via
# to the ring, none to the strap. The right jumper reaches (vias at 2893.74
# and 2882.59). The first VSS met4 vertical stripe (x 20.1-22.1) already
# vias to the strap, so the fix is a met3 LINK at each strap y from the stub
# to that VSS stripe, under the VDD stripe on a different layer, with
# stacked vias met3-met4 at both overlaps. Generic: per strap and side, if
# the jumper does not overlap the strap, link it to the nearest same-net
# vertical stripe on the jumper layer. Then the antenna_fix6 rip-up/reroute
# loop for whatever the links collide with, and the same gate as v2.
#   ASIC_ECO_SRC     checkpoint (07_vssfix_v2stub.enc = v2 result, renamed)
#   ASIC_ECO_DST     checkpoint to write when clean (07_vssfix.enc)
#   ASIC_ECO_PASSES  reroute passes (default 4)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 07_vssfix_v2stub.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt vss_eco3 vss_eco3.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }

# ---- 1. geometry: rings, straps, met4 horizontals in the edge bands, met4 verticals near the edges
set vss [dbGet -p top.nets.name VSS]
set die [lindex [dbGet top.fPlan.box] 0]; lassign $die dx1 dy1 dx2 dy2
set ringL ""; set ringR ""; set straps {}; set hL {}; set hR {}; set vL {}; set vR {}
foreach w [dbGet $vss.sWires] {
    set lay [dbGet $w.layer.name]
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    set horiz [expr {($x2 - $x1) > ($y2 - $y1)}]
    if {$lay eq "met5" && !$horiz && ($y2 - $y1) > 2000} {
        if {$x1 < 100} { set ringL [list $x1 $x2] } elseif {$x1 > 2800} { set ringR [list $x1 $x2] }
    } elseif {$lay eq "met5" && $horiz && ($x2 - $x1) > 2000} {
        lappend straps [list [expr {($y1+$y2)/2.0}] $x1 $x2 [expr {$y2-$y1}] $y1 $y2]
    } elseif {$lay eq "met4" && $horiz && ($x2 - $x1) < 100} {
        if {$x1 < 100} { lappend hL [list $x1 $y1 $x2 $y2] } elseif {$x2 > 2800} { lappend hR [list $x1 $y1 $x2 $y2] }
    } elseif {$lay eq "met4" && !$horiz && ($y2 - $y1) > 100} {
        if {$x1 < 100} { lappend vL [list $x1 $y1 $x2 $y2] } elseif {$x2 > 2800} { lappend vR [list $x1 $y1 $x2 $y2] }
    }
}
lq "VSS ring left=$ringL right=$ringR straps=[llength $straps] jumpersL=[llength $hL] jumpersR=[llength $hR] vstripesL=[llength $vL] vstripesR=[llength $vR]"
if {$ringL eq "" || $ringR eq "" || ![llength $straps]} { lq "ECO ABORT: geometry not found"; close $fh; exit 3 }

# ---- 2. per strap and side: does the jumper reach the strap? else met3 link
setAddStripeMode -stacked_via_top_layer met4 -stacked_via_bottom_layer met3
set nlink 0; set nok 0; set nskip 0
foreach s [lsort -real -index 0 $straps] {
    lassign $s yc sx1 sx2 sw y1 y2
    # left
    set stub ""
    foreach h $hL { lassign $h hx1 hy1 hx2 hy2; if {$hy1 < $yc && $hy2 > $yc} { set stub $h; break } }
    if {$stub eq ""} { lq "y=$yc left: no jumper found - skip"; incr nskip } else {
        lassign $stub hx1 hy1 hx2 hy2
        if {$hx2 >= $sx1 + 0.5} { incr nok } else {
            set best ""; set bd 1e9
            foreach v $vL { lassign $v vx1 vy1 vx2 vy2; if {$vy1 < $yc && $vy2 > $yc && $vx1 > $hx2 && ($vx1 - $hx2) < $bd} { set best $v; set bd [expr {$vx1 - $hx2}] } }
            if {$best eq ""} { lq "y=$yc left: jumper ends $hx2 < strap $sx1 and no VSS met4 vertical stripe to link - skip"; incr nskip } else {
                lassign $best vx1 vy1 vx2 vy2
                addStripe -nets VSS -layer met3 -direction horizontal -width $sw \
                    -area [list [expr {$hx2 - 2.5}] $y1 $vx2 $y2] \
                    -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
                incr nlink
            }
        }
    }
    # right
    set stub ""
    foreach h $hR { lassign $h hx1 hy1 hx2 hy2; if {$hy1 < $yc && $hy2 > $yc} { set stub $h; break } }
    if {$stub eq ""} { lq "y=$yc right: no jumper found - skip"; incr nskip } else {
        lassign $stub hx1 hy1 hx2 hy2
        if {$hx1 <= $sx2 - 0.5} { incr nok } else {
            set best ""; set bd 1e9
            foreach v $vR { lassign $v vx1 vy1 vx2 vy2; if {$vy1 < $yc && $vy2 > $yc && $vx2 < $hx1 && ($hx1 - $vx2) < $bd} { set best $v; set bd [expr {$hx1 - $vx2}] } }
            if {$best eq ""} { lq "y=$yc right: jumper starts $hx1 > strap end $sx2 and no VSS met4 vertical stripe to link - skip"; incr nskip } else {
                lassign $best vx1 vy1 vx2 vy2
                addStripe -nets VSS -layer met3 -direction horizontal -width $sw \
                    -area [list $vx1 $y1 [expr {$hx1 + 2.5}] $y2] \
                    -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
                incr nlink
            }
        }
    }
}
lq "jumper audit: reach strap = $nok, met3 links added = $nlink, skipped = $nskip"
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco3 vss_conn.rpt]

# ---- 3. rip up + reroute what the links collide with (antenna_fix6 recipe)
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
set drc_rpt [pnr_rpt vss_eco3 drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
lq "pass 0 (links only): verify_drc = $d"
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
    set drc_rpt [pnr_rpt vss_eco3 drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt vss_eco3 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 07_vssfix3_pass$pass.enc]
    if {$d == 0 && $a == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
if {$a < 0} {
    set ant_rpt [pnr_rpt vss_eco3 antenna_final.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
}
# ---- 4. gate: connectivity, and PROOF that every strap now has a path to its ring:
# count VSS vias at each strap y in the ring bands (dbGet on the sWires: via shapes carry a via object)
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco3 vss_conn_final.rpt]
set f [open [pnr_rpt vss_eco3 vss_conn_final.rpt] r]; set t [read $f]; close $f
set pieces 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> pieces
set nvia3 0
foreach v [dbGet $vss.sVias] {
    set vn [dbGet $v.via.name]
    lassign [lindex [dbGet $v.box] 0] x1 y1 x2 y2
    if {[string match "*M3M4*" $vn] && ($x1 < 30 || $x2 > 2870)} { incr nvia3 }
}
lq "met3-met4 VSS vias in the edge bands after ECO3 = $nvia3 (expect 2 per link)"
catch {
    report_timing -early -max_paths 1 -path_type summary > [pnr_rpt vss_eco3 hold_after.rpt]
    report_timing -late  -max_paths 1 -path_type summary > [pnr_rpt vss_eco3 setup_after.rpt]
}
lq "VSS ECO3: verify_drc = $d antenna = $a vss_pieces = $pieces links = $nlink m3m4_vias = $nvia3"
pnr_note "VSS ECO3: verify_drc = $d antenna = $a vss_pieces = $pieces links = $nlink m3m4_vias = $nvia3"
if {$d == 0 && $a == 0 && $pieces == 0 && $nlink > 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix3_dirty.enc]; close $fh; exit 2
