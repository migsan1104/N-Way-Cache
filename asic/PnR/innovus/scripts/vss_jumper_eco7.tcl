# vss_jumper_eco7.tcl - 2026-09-07 (iter19b, v7: the last 5 via3 at 1.02-1.24x).
# After v6 every via4 is under the limit (worst 0.99). The 5 via3 left are
# the L-link leg -> VSS stripe vias at y_link 383.18 / 443.02 / 502.86 /
# 2423.18 / 2483.02: there the v5 2 um met3 pad was never built (the power
# planner refused 4 with IMPPP-354 and 5 more never landed; those y_links
# sit < 2 um from the strap band where the v3 met3 piece already is), so the
# via is the 10-cut one on the 1 um leg. v7: for every L-link leg whose
# 2 um pad is missing, a VERTICAL met3 pad on the stripe (x 20.1-22.1,
# y_link +- 2.5, ignore_DRC so the planner does not refuse it; verify_drc
# judges afterwards), then editPowerVia delete+add met3-met4 over it, then
# the reroute loop and a via3 cut audit (>= 20 cuts at every y_link).
#   ASIC_ECO_SRC  checkpoint (07_vssfix_v6.enc = v6 renamed)
#   ASIC_ECO_DST  checkpoint to write when clean (07_vssfix.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 07_vssfix_v6.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
set _win [config_env ASIC_ECO_WIN 6.0]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt vss_eco7 vss_eco7.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }

# ---- 1. geometry: L-link legs (1 um met3, x 14.4 -> 22.1), existing 2 um pads, the VSS stripe
set vss [dbGet -p top.nets.name VSS]
set legs {}; set pads {}; set vs ""
foreach w [dbGet $vss.sWires] {
    set lay [dbGet $w.layer.name]
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    set horiz [expr {($x2 - $x1) > ($y2 - $y1)}]
    if {$lay eq "met3" && $horiz && $x1 < 16 && $x2 > 19 && ($y2 - $y1) < 1.2} { lappend legs [list [expr {($y1+$y2)/2.0}] $x1 $x2] }
    if {$lay eq "met3" && $horiz && $x1 > 19 && $x1 < 20 && ($y2 - $y1) > 1.8 && ($x2 - $x1) < 5} { lappend pads [expr {($y1+$y2)/2.0}] }
    if {$lay eq "met4" && !$horiz && ($y2 - $y1) > 100 && $x1 > 19 && $x1 < 22} { set vs [list $x1 $x2] }
}
lq "L-link legs=[llength $legs] existing 2um pads=[llength $pads] VSS stripe x=$vs"
if {![llength $legs] || $vs eq ""} { lq "ECO ABORT: geometry not found"; close $fh; exit 3 }
lassign $vs vx1 vx2

# ---- 2. vertical pads where the horizontal one is missing, then via arrays
setAddStripeMode -stacked_via_top_layer met3 -stacked_via_bottom_layer met3 -ignore_DRC true
set nadd 0; set nskip 0; set targets {}
foreach l $legs {
    lassign $l yl lx1 lx2
    set have 0
    foreach py $pads { if {abs($py - $yl) < 0.3} { set have 1; break } }
    if {$have} { incr nskip; continue }
    addStripe -nets VSS -layer met3 -direction vertical -width [expr {$vx2 - $vx1}] \
        -area [list $vx1 [expr {$yl - 2.5}] $vx2 [expr {$yl + 2.5}]] \
        -start_from left -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    incr nadd; lappend targets $yl
}
setAddStripeMode -ignore_DRC false
lq "vertical met3 pads added at y_link: $nadd ($targets); legs already padded: $nskip"
set nv 0
foreach yl $targets {
    set box [list [expr {$vx1 - 0.3}] [expr {$yl - 2.8}] [expr {$vx2 + 0.3}] [expr {$yl + 2.8}]]
    catch {editPowerVia -delete_vias 1 -nets VSS -top_layer met4 -bottom_layer met3 -area $box}
    if {![catch {editPowerVia -add_vias 1 -nets VSS -top_layer met4 -bottom_layer met3 -orthogonal_only false -area $box} m]} { incr nv } else { lq "editPowerVia failed $box: $m" }
}
lq "met3-met4 via arrays regenerated: $nv"
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco7 vss_conn.rpt]

# ---- 3. DRC, reroute loop (windowed rip-up from pass 3)
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
set drc_rpt [pnr_rpt vss_eco7 drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
set f [open $drc_rpt r]; set t [read $f]; close $f
set nvdd [regexp -all {Net VDD} $t]
lq "pass 0 (after ECO7 shapes): verify_drc = $d, markers naming VDD = $nvdd"
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
    set drc_rpt [pnr_rpt vss_eco7 drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt vss_eco7 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 07_vssfix7_pass$pass.enc]
    if {$d == 0 && $a == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key && $pass >= 3} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
if {$a < 0} { set ant_rpt [pnr_rpt vss_eco7 antenna_final.rpt]; verifyProcessAntenna -report $ant_rpt; set a [antenna_count $ant_rpt] }

# ---- 4. gate: connectivity + via3 cut audit at every y_link
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco7 vss_conn_final.rpt]
set f [open [pnr_rpt vss_eco7 vss_conn_final.rpt] r]; set t [read $f]; close $f
set pieces 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> pieces
set v34 {}
foreach v [dbGet $vss.sVias] {
    if {![string match "*M3M4*" [dbGet $v.via.name]]} continue
    set vx [dbGet $v.pt_x]; if {$vx < 19 || $vx > 23} continue
    lappend v34 [list $vx [dbGet $v.pt_y] [llength [lindex [dbGet $v.cutRects] 0]]]
}
set minc 999; set bad {}
foreach l $legs { lassign $l yl lx1 lx2; set c 0
    foreach v $v34 { lassign $v vx vy nc; if {abs($vy - $yl) < 2.9} { incr c $nc } }
    if {$c < $minc} { set minc $c }; if {$c < 20} { lappend bad [format "y_link=%s cuts=%d" $yl $c] } }
lq "via3 cut audit at the y_links: min $minc; below 20: [llength $bad] $bad"
catch {
    report_timing -early -max_paths 1 -path_type summary > [pnr_rpt vss_eco7 hold_after.rpt]
    report_timing -late  -max_paths 1 -path_type summary > [pnr_rpt vss_eco7 setup_after.rpt]
}
lq "VSS ECO7: verify_drc = $d antenna = $a vss_pieces = $pieces vdd_markers = $nvdd cut_audit_fail = [llength $bad]"
pnr_note "VSS ECO7: verify_drc = $d antenna = $a vss_pieces = $pieces vdd_markers = $nvdd cut_audit_fail = [llength $bad]"
if {$d == 0 && $a == 0 && $pieces == 0 && ![llength $bad]} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix7_dirty.enc]; close $fh; exit 2
