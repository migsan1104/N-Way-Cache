# vss_eco_continue.tcl - 2026-09-07. Continuation of vss_jumper_eco5.tcl:
# restore a pass checkpoint, run ONLY the rip-up/reroute loop from its DRC
# report (no new PG shapes), then the same gate and via4 cut audit, and save.
#   ASIC_ECO_SRC     checkpoint (07_vssfix5_pass4.enc)
#   ASIC_ECO_DRC     verify_drc report matching it (reports/vss_eco5/drc_pass4.rpt)
#   ASIC_ECO_DST     checkpoint to write when clean (07_vssfix.enc)
#   ASIC_ECO_PASSES  reroute passes (default 4)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 07_vssfix5_pass4.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
set _drc0 [config_env ASIC_ECO_DRC [pnr_rpt vss_eco5 drc_pass4.rpt]]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt vss_eco5c vss_eco5c.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
set vss [dbGet -p top.nets.name VSS]
set ringL ""; set ringR ""; set straps {}
foreach w [dbGet $vss.sWires] {
    set lay [dbGet $w.layer.name]
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    set horiz [expr {($x2 - $x1) > ($y2 - $y1)}]
    if {$lay eq "met5" && !$horiz && ($y2 - $y1) > 2000} { if {$x1 < 100} { set ringL [list $x1 $x2] } elseif {$x1 > 2800} { set ringR [list $x1 $x2] } }
    if {$lay eq "met5" && $horiz && ($x2 - $x1) > 2000} { lappend straps [list [expr {($y1+$y2)/2.0}] $x1 $x2 [expr {$y2-$y1}] $y1 $y2] }
}
lq "continue from $_src with $_drc0: ring L=$ringL R=$ringR straps=[llength $straps]"

# ---- 2a. vias on the parallel overlaps. The probe on 07_vssfix5_pass4.enc
# showed the eco5 met4 pads under the straps got NO vias: addStripe's ViaGen
# only drops vias where shapes CROSS, and a met4 pad running parallel under
# a met5 strap is an overlap, not a crossing (the ring crossings got 2 cuts
# because the 2 um stub crosses the 4 um ring). editPowerVia with
# -orthogonal_only false fills the parallel overlaps: strap-end pads (met4 x
# met5) and the 4 um ring pads (met4 x met5 ring). ASIC_ECO_PADL (um, 8) must
# match eco5.
set PADL [config_env ASIC_ECO_PADL 8.0]
set nvia 0
foreach s [lsort -real -index 0 $straps] {
    lassign $s yc sx1 sx2 sw y1 y2
    foreach box [list [list $sx1 [expr {$y1 - 0.2}] [expr {$sx1 + 14.0}] [expr {$y2 + 0.2}]] \
                      [list [expr {$sx2 - $PADL - 2.0}] [expr {$y1 - 0.2}] $sx2 [expr {$y2 + 0.2}]] \
                      [list [lindex $ringL 0] [expr {$yc - 2.2}] [lindex $ringL 1] [expr {$yc + 2.2}]] \
                      [list [lindex $ringR 0] [expr {$yc - 2.2}] [lindex $ringR 1] [expr {$yc + 2.2}]]] {
        # ASIC_ECO_DELVIAS=1: remove the existing single-cut via in the box first -
        # with it present ViaGen reports "created 1 via, deleted 1 via to avoid
        # violation" (the new array collides with the old cut) and nothing changes.
        if {[config_env ASIC_ECO_DELVIAS 0]} {
            if {[catch {editPowerVia -delete_vias 1 -nets VSS -top_layer met5 -bottom_layer met4 -area $box} dmsg]} { lq "editPowerVia -delete_vias failed on $box: $dmsg" }
        }
        if {[catch {editPowerVia -add_vias 1 -nets VSS -top_layer met5 -bottom_layer met4 -orthogonal_only false -area $box} msg]} {
            lq "editPowerVia failed on $box: $msg"
        } else { incr nvia }
    }
}
lq "editPowerVia calls that returned ok: $nvia / [expr {4 * [llength $straps]}]"
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
# ---- 2b. windowed rip-up (legalize_fixup.tcl recipe): the eco5 loop bounced
# 10 -> 7 -> 8 on signal-vs-signal met1/met2 shorts among the nets it kept
# rerouting; cut EVERY signal wire in a +-ASIC_ECO_WIN um window around each
# non-PG marker so the neighbours are re-routed together, then routeDesign.
set _win [config_env ASIC_ECO_WIN 6.0]
set items {}; set cur ""
set f [open $_drc0 r]
while {[gets $f l] >= 0} {
    if {[regexp {^([A-Z]+):(.*)$} $l -> t rest]} { set cur [list $t $rest] }
    if {[regexp {^Bounds\s*:\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)} $l -> x1 y1 x2 y2] && $cur ne ""} {
        lappend items [list [lindex $cur 0] [lindex $cur 1] $x1 $y1 $x2 $y2]; set cur ""
    }
}
close $f
set _cut 0
foreach it $items {
    lassign $it t rest x1 y1 x2 y2
    if {[string match *Special* $rest]} { continue }
    set box [list [expr {$x1-$_win}] [expr {$y1-$_win}] [expr {$x2+$_win}] [expr {$y2+$_win}]]
    lq "window: cut signal wires in $box ($t)"
    editDelete -area $box -type Signal
    incr _cut
}
# antenna fixer + router diodes stay ON for every routeDesign in this script, the
# pass-0 full route included (v5c: a window reroute with the fixer off handed the
# gate 2 antenna nets; v8c: a clean pass 0 had no antenna check at all)
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode true -routeAntennaCellName sky130_fd_sc_hd__diode_2
if {$_cut} {
    setNanoRouteMode -drouteEndIteration 40
    routeDesign
}
clearDrc
set drc_rpt [pnr_rpt vss_eco5c drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
lq "pass 0 (after [llength $items] markers, $_cut windows): verify_drc = $d"
set ant_rpt [pnr_rpt vss_eco5c antenna_pass0.rpt]
verifyProcessAntenna -report $ant_rpt
set a0 [antenna_count $ant_rpt]
lq "pass 0: antenna = $a0"
# Nets named in the INPUT report WITHOUT a marker (antenna nets handed in as bare
# "Wire of Net X" lines, v5e style) are rerouted in pass 1 even when the fresh
# verify_drc is clean. Nets whose marker HAS Bounds were already cut by the
# windows and rerouted by the full routeDesign above - ripping them up again
# selected-only after a clean pass 0 is what turned v8c's DRC 0 into 8 shorts.
set bounded {}
foreach it $items { foreach {_ n} [regexp -all -inline {Wire of Net (\S+)} [lindex $it 1]] { lappend bounded $n } }
set extra_nets {}
foreach n [lsort -u [nets_from_drc $_drc0]] { if {[lsearch -exact $bounded $n] < 0} { lappend extra_nets $n } }
# antenna violators left by pass 0 join them (report header lines: "<net> (<n>)")
if {$a0 > 0} {
    set f [open $ant_rpt r]
    while {[gets $f l] >= 0} { if {[regexp {^(\S+) \(\d+\)\s*$} $l -> n]} { lappend extra_nets $n } }
    close $f
}
set extra_nets [lsort -u $extra_nets]
lq "pass 1 will also reroute [llength $extra_nets] nets (markerless input-report nets + pass-0 antenna nets)"
set a [expr {$a0 >= 0 ? $a0 : -1}]; set prev_key ""
for {set pass 1} {$pass <= $_np} {incr pass} {
    set nets [lsort -u [concat [nets_from_drc $drc_rpt] $extra_nets]]; set extra_nets {}
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
    set drc_rpt [pnr_rpt vss_eco5c drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt vss_eco5c antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 07_vssfix5c_pass$pass.enc]
    if {$d == 0 && $a == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
if {$a < 0} { set ant_rpt [pnr_rpt vss_eco5c antenna_final.rpt]; verifyProcessAntenna -report $ant_rpt; set a [antenna_count $ant_rpt] }

# ---- 4. gate: connectivity + via4 cut audit at the strap-end pads and ring pads
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco5c vss_conn_final.rpt]
set f [open [pnr_rpt vss_eco5c vss_conn_final.rpt] r]; set t [read $f]; close $f
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
    report_timing -early -max_paths 1 -path_type summary > [pnr_rpt vss_eco5c hold_after.rpt]
    report_timing -late  -max_paths 1 -path_type summary > [pnr_rpt vss_eco5c setup_after.rpt]
}
lq "VSS ECO5C: verify_drc = $d antenna = $a vss_pieces = $pieces cut_audit_fail = [llength $bad]"
pnr_note "VSS ECO5C: verify_drc = $d antenna = $a vss_pieces = $pieces cut_audit_fail = [llength $bad]"
if {$d == 0 && $a == 0 && $pieces == 0 && ![llength $bad]} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix5c_dirty.enc]; close $fh; exit 2
