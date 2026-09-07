# vss_jumper_eco6.tcl - 2026-09-07 (iter19b, v6: EM, vertical stripe ends).
# After v5 the strap-end and ring crossings are multi-cut and VSS EM fell
# 2.71x -> 1.78x. Every remaining via4 offender (28) is at y 17.38 or 2881.46:
# the vertical met4 VSS stripes stop at the core edge (y 16.38 / 2882.46) and
# reach the top/bottom rings through addStripe's own met5 jumpers (2 um wide,
# y 3.98-18.38 / 2880.46-2894.86), a 2x2 um overlap = ONE via4 cut carrying
# ~2.1 mA (limit 1.2). Same fix as v5, vertical: extend each met5 jumper over
# the stripe by ~8 um (bottom up to y 26.4 - the lowest VDD met5 strap at
# y 16.98 is already fragmented around the jumpers and the next is at 76.98;
# top down to 2872.5 - highest VDD strap 2836.98) and regenerate the via4
# array with editPowerVia (delete + add, -orthogonal_only false). Also
# regenerate the y_link met3-met4 vias (5 via3 at <= 1.25x: the v5 met3 pad
# kept the old 10-cut via). Then the reroute loop, windowed rip-up if needed,
# gate: drc 0, antenna 0, pieces 0, >= 4 via4 cuts at every stripe end.
#   ASIC_ECO_SRC  checkpoint (07_vssfix_v5em.enc = v5 renamed)
#   ASIC_ECO_DST  checkpoint to write when clean (07_vssfix.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 07_vssfix_v5em.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
set _win [config_env ASIC_ECO_WIN 6.0]
set EXT  [config_env ASIC_ECO_JEXT 8.0]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt vss_eco6 vss_eco6.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }

# ---- 1. geometry
set vss [dbGet -p top.nets.name VSS]
set die [lindex [dbGet top.fPlan.box] 0]; lassign $die dx1 dy1 dx2 dy2
set jumpB {}; set jumpT {}; set straps {}; set m3pads {}
foreach w [dbGet $vss.sWires] {
    set lay [dbGet $w.layer.name]
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    set horiz [expr {($x2 - $x1) > ($y2 - $y1)}]
    if {$lay eq "met5" && !$horiz && ($y2 - $y1) < 50 && ($x2 - $x1) < 4} {
        if {$y1 < 100} { lappend jumpB [list $x1 $y1 $x2 $y2] } elseif {$y2 > $dy2 - 100} { lappend jumpT [list $x1 $y1 $x2 $y2] }
    }
    if {$lay eq "met5" && $horiz && ($x2 - $x1) > 2000} { lappend straps [list [expr {($y1+$y2)/2.0}] $x1 $x2 $y1 $y2] }
    if {$lay eq "met3" && $horiz && $x1 < 20 && $x2 > 22 && ($y2 - $y1) < 2.5 && ($x2 - $x1) < 12} { lappend m3pads [list $x1 $y1 $x2 $y2] }
}
lq "die $die; bottom met5 jumpers=[llength $jumpB] top=[llength $jumpT] straps=[llength $straps] met3 y_link pads=[llength $m3pads]"
if {![llength $jumpB] || ![llength $jumpT]} { lq "ECO ABORT: jumpers not found"; close $fh; exit 3 }

# ---- 2. extend the jumpers and regenerate the stripe-end via arrays
setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met5
set nb 0; set nt 0; set nv 0
foreach j $jumpB {
    lassign $j x1 y1 x2 y2
    addStripe -nets VSS -layer met5 -direction vertical -width [expr {$x2 - $x1}] \
        -area [list $x1 [expr {$y2 - 1.0}] $x2 [expr {$y2 + $EXT}]] \
        -start_from left -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    incr nb
    set box [list [expr {$x1 - 0.2}] [expr {$y2 - 2.5}] [expr {$x2 + 0.2}] [expr {$y2 + $EXT + 0.5}]]
    catch {editPowerVia -delete_vias 1 -nets VSS -top_layer met5 -bottom_layer met4 -area $box}
    if {![catch {editPowerVia -add_vias 1 -nets VSS -top_layer met5 -bottom_layer met4 -orthogonal_only false -area $box} m]} { incr nv } else { lq "editPowerVia add failed $box: $m" }
}
foreach j $jumpT {
    lassign $j x1 y1 x2 y2
    addStripe -nets VSS -layer met5 -direction vertical -width [expr {$x2 - $x1}] \
        -area [list $x1 [expr {$y1 - $EXT}] $x2 [expr {$y1 + 1.0}]] \
        -start_from left -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    incr nt
    set box [list [expr {$x1 - 0.2}] [expr {$y1 - $EXT - 0.5}] [expr {$x2 + 0.2}] [expr {$y1 + 2.5}]]
    catch {editPowerVia -delete_vias 1 -nets VSS -top_layer met5 -bottom_layer met4 -area $box}
    if {![catch {editPowerVia -add_vias 1 -nets VSS -top_layer met5 -bottom_layer met4 -orthogonal_only false -area $box} m]} { incr nv } else { lq "editPowerVia add failed $box: $m" }
}
lq "jumpers extended: bottom $nb top $nt; via arrays regenerated: $nv"
# ---- 2b. y_link met3-met4 vias (the L-link legs on the VSS vertical stripe)
set n3 0
foreach m $m3pads {
    lassign $m x1 y1 x2 y2
    set box [list [expr {$x1 - 0.2}] [expr {$y1 - 0.2}] [expr {$x2 + 0.2}] [expr {$y2 + 0.2}]]
    catch {editPowerVia -delete_vias 1 -nets VSS -top_layer met4 -bottom_layer met3 -area $box}
    if {![catch {editPowerVia -add_vias 1 -nets VSS -top_layer met4 -bottom_layer met3 -orthogonal_only false -area $box} m]} { incr n3 } else { lq "editPowerVia met3 add failed $box: $m" }
}
lq "y_link met3-met4 via arrays regenerated: $n3"
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco6 vss_conn.rpt]

# ---- 3. DRC, windowed rip-up if needed, reroute loop
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
set drc_rpt [pnr_rpt vss_eco6 drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
set f [open $drc_rpt r]; set t [read $f]; close $f
lq "pass 0 (after ECO6 shapes): verify_drc = $d, markers naming VDD = [regexp -all {Net VDD} $t]"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode true -routeAntennaCellName sky130_fd_sc_hd__diode_2
set a -1; set prev_key ""
for {set pass 1} {$pass <= $_np} {incr pass} {
    set nets [lsort -u [nets_from_drc $drc_rpt]]
    if {![llength $nets] && $d == 0} { lq "pass $pass: nothing to reroute"; break }
    if {![llength $nets]} { lq "pass $pass: $d markers but no signal net named - stop"; break }
    lq "pass $pass: [llength $nets] nets"
    if {$pass >= 3} {
        # windowed rip-up around each remaining marker (legalize_fixup recipe)
        set items {}; set cur ""
        set f [open $drc_rpt r]
        while {[gets $f l] >= 0} {
            if {[regexp {^([A-Z]+):(.*)$} $l -> t rest]} { set cur [list $t $rest] }
            if {[regexp {^Bounds\s*:\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)} $l -> x1 y1 x2 y2] && $cur ne ""} {
                lappend items [list [lindex $cur 0] [lindex $cur 1] $x1 $y1 $x2 $y2]; set cur "" } }
        close $f
        set nc 0
        foreach it $items { lassign $it t rest x1 y1 x2 y2
            if {[string match *Special* $rest]} { continue }
            editDelete -area [list [expr {$x1-$_win}] [expr {$y1-$_win}] [expr {$x2+$_win}] [expr {$y2+$_win}]] -type Signal; incr nc }
        lq "pass $pass: windowed rip-up on $nc markers"
    }
    foreach nn $nets { catch {editDelete -net $nn} }
    deselectAll
    foreach nn $nets { catch {selectNet $nn} }
    setNanoRouteMode -routeSelectedNetOnly true
    routeDesign
    setNanoRouteMode -routeSelectedNetOnly false
    deselectAll
    clearDrc
    set drc_rpt [pnr_rpt vss_eco6 drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt vss_eco6 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 07_vssfix6_pass$pass.enc]
    if {$d == 0 && $a == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key && $pass >= 3} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
if {$a < 0} { set ant_rpt [pnr_rpt vss_eco6 antenna_final.rpt]; verifyProcessAntenna -report $ant_rpt; set a [antenna_count $ant_rpt] }

# ---- 4. gate
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco6 vss_conn_final.rpt]
set f [open [pnr_rpt vss_eco6 vss_conn_final.rpt] r]; set t [read $f]; close $f
set pieces 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> pieces
set v45 {}
foreach v [dbGet $vss.sVias] {
    if {![string match "*M4M5*" [dbGet $v.via.name]]} continue
    set vy [dbGet $v.pt_y]
    if {$vy > 40 && $vy < $dy2 - 40} continue
    lappend v45 [list [dbGet $v.pt_x] $vy [llength [lindex [dbGet $v.cutRects] 0]]]
}
proc cuts_in {box} { global v45; lassign $box bx1 by1 bx2 by2; set n 0
    foreach v $v45 { lassign $v vx vy nc; if {$vx >= $bx1 && $vx <= $bx2 && $vy >= $by1 && $vy <= $by2} { incr n $nc } }
    return $n }
set minB 99; set minT 99; set bad {}
foreach j $jumpB { lassign $j x1 y1 x2 y2; set c [cuts_in [list [expr {$x1-0.3}] 15.0 [expr {$x2+0.3}] [expr {$y2 + $EXT + 1}]]]; if {$c < $minB} { set minB $c }; if {$c < 4} { lappend bad [format "bottom x=%s cuts=%d" $x1 $c] } }
foreach j $jumpT { lassign $j x1 y1 x2 y2; set c [cuts_in [list [expr {$x1-0.3}] [expr {$y1 - $EXT - 1}] [expr {$x2+0.3}] [expr {$dy2 - 15.0}]]]; if {$c < $minT} { set minT $c }; if {$c < 4} { lappend bad [format "top x=%s cuts=%d" $x1 $c] } }
lq "via4 cut audit at the stripe ends: min bottom $minB, min top $minT; below 4: [llength $bad] $bad"
catch {
    report_timing -early -max_paths 1 -path_type summary > [pnr_rpt vss_eco6 hold_after.rpt]
    report_timing -late  -max_paths 1 -path_type summary > [pnr_rpt vss_eco6 setup_after.rpt]
}
lq "VSS ECO6: verify_drc = $d antenna = $a vss_pieces = $pieces cut_audit_fail = [llength $bad]"
pnr_note "VSS ECO6: verify_drc = $d antenna = $a vss_pieces = $pieces cut_audit_fail = [llength $bad]"
if {$d == 0 && $a == 0 && $pieces == 0 && ![llength $bad]} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix6_dirty.enc]; close $fh; exit 2
