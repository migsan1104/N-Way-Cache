# vss_jumper_eco8.tcl - 2026-09-07 (iter19b, v8: the LVS finding). The standard-
# cell rows in the 24 um channel between the right SRAM column (x 2860) and
# the core edge (2883.74) are row segments whose met1 VPWR/VGND rails touch
# nothing: no vertical stripe crosses the channel (60 um pitch from x 17.1
# ends at 2837/2841 under the macro), the rails stop 2 um short of the rings,
# and the met5 straps are parallel to them. 288+289 floating rails, every
# cell there unpowered (lvs.md 2026-09-07 12:40). Fix: one VDD + VSS met4
# vertical pair in the channel with stacked vias met1..met5, orthogonal to
# every rail (via stacks down) and to the met5 straps (fed from above); the
# reroute loop for the signal collisions; gate = DRC 0, antenna 0, and
# verifyConnectivity IMPVFC-96 (terminals not connected) = 0 for VDD and VSS.
#   ASIC_ECO_SRC  checkpoint (07_vssfix_v7.enc = v7 renamed)
#   ASIC_ECO_DST  checkpoint to write when clean (07_vssfix.enc)
#   ASIC_ECO_CHX1/CHX2/CHY1/CHY2  stripe area (default 2868.6 610 2879.0 2305)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 07_vssfix_v7.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
set _win [config_env ASIC_ECO_WIN 6.0]
set CX1 [config_env ASIC_ECO_CHX1 2868.6]; set CY1 [config_env ASIC_ECO_CHY1 610.0]
set CX2 [config_env ASIC_ECO_CHX2 2879.0]; set CY2 [config_env ASIC_ECO_CHY2 2305.0]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt vss_eco8 vss_eco8.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
proc unconnected {net rpt} {
    verifyConnectivity -type special -net $net -noAntenna -error 200000 -warning 50 -report $rpt
    set f [open $rpt r]; set t [read $f]; close $f
    set n 0; regexp {(\d+) Problem\(s\) \(IMPVFC-96\)} $t -> n
    set p 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> p
    return [list $n $p]
}
# ---- 0. before
lassign [unconnected VDD [pnr_rpt vss_eco8 conn_vdd_before.rpt]] u0v p0v
lassign [unconnected VSS [pnr_rpt vss_eco8 conn_vss_before.rpt]] u0s p0s
lq "BEFORE: unconnected terminals VDD=$u0v VSS=$u0s; disconnected pieces VDD=$p0v VSS=$p0s"
# ---- 1. channel stripes
setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met1
addStripe -nets {VDD VSS} -layer met4 -direction vertical -width 2.0 -spacing 2.0 \
    -area [list $CX1 $CY1 $CX2 $CY2] -start_from left -start_offset 0 \
    -number_of_sets 1 -set_to_set_distance 1000
set vdd [dbGet -p top.nets.name VDD]; set vss [dbGet -p top.nets.name VSS]
set nvdd 0; set nvss 0
foreach w [dbGet $vdd.sWires] { lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2; if {[dbGet $w.layer.name] eq "met4" && $x1 > $CX1 - 0.1 && $x2 < $CX2 + 0.1 && ($y2 - $y1) > 100} { incr nvdd; lq "VDD channel stripe: $x1 $y1 $x2 $y2" } }
foreach w [dbGet $vss.sWires] { lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2; if {[dbGet $w.layer.name] eq "met4" && $x1 > $CX1 - 0.1 && $x2 < $CX2 + 0.1 && ($y2 - $y1) > 100} { incr nvss; lq "VSS channel stripe: $x1 $y1 $x2 $y2" } }
lq "channel stripes present: VDD $nvdd VSS $nvss"
if {!$nvdd || !$nvss} { lq "ECO ABORT: addStripe did not build the channel pair"; close $fh; exit 3 }
lassign [unconnected VDD [pnr_rpt vss_eco8 conn_vdd_after_stripes.rpt]] u1v p1v
lassign [unconnected VSS [pnr_rpt vss_eco8 conn_vss_after_stripes.rpt]] u1s p1s
lq "AFTER STRIPES: unconnected terminals VDD=$u1v VSS=$u1s; pieces VDD=$p1v VSS=$p1s"
# ---- 2. DRC + reroute loop (windowed rip-up from pass 3)
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
set drc_rpt [pnr_rpt vss_eco8 drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
set f [open $drc_rpt r]; set t [read $f]; close $f
set nvddm [regexp -all {Net VDD} $t]
lq "pass 0 (after stripes): verify_drc = $d, markers naming VDD = $nvddm"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode true -routeAntennaCellName sky130_fd_sc_hd__diode_2
set a -1; set prev_key ""
for {set pass 1} {$pass <= $_np} {incr pass} {
    set nets [lsort -u [nets_from_drc $drc_rpt]]
    if {![llength $nets] && $d == 0} { lq "pass $pass: nothing to reroute"; break }
    if {![llength $nets]} { lq "pass $pass: $d markers but no signal net named - stop"; break }
    lq "pass $pass: [llength $nets] nets"
    if {$pass >= 3} {
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
    set drc_rpt [pnr_rpt vss_eco8 drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt vss_eco8 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 07_vssfix8_pass$pass.enc]
    if {$d == 0 && $a == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key && $pass >= 3} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
if {$a < 0} { set ant_rpt [pnr_rpt vss_eco8 antenna_final.rpt]; verifyProcessAntenna -report $ant_rpt; set a [antenna_count $ant_rpt] }
# ---- 3. gate
lassign [unconnected VDD [pnr_rpt vss_eco8 conn_vdd_final.rpt]] uv pv
lassign [unconnected VSS [pnr_rpt vss_eco8 conn_vss_final.rpt]] us ps
catch {
    report_timing -early -max_paths 1 -path_type summary > [pnr_rpt vss_eco8 hold_after.rpt]
    report_timing -late  -max_paths 1 -path_type summary > [pnr_rpt vss_eco8 setup_after.rpt]
}
lq "VSS ECO8: verify_drc = $d antenna = $a unconnected_terminals VDD=$uv VSS=$us pieces VDD=$pv VSS=$ps (before: VDD=$u0v VSS=$u0s)"
pnr_note "VSS ECO8: verify_drc = $d antenna = $a unconnected_terminals VDD=$uv VSS=$us pieces VDD=$pv VSS=$ps"
if {$d == 0 && $a == 0 && $uv == 0 && $us == 0 && $pv == 0 && $ps == 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix8_dirty.enc]; close $fh; exit 2
