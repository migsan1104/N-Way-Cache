# vss_jumper_eco2.tcl - 2026-09-07 (iter19b, v2 of vss_jumper_eco.tcl).
# v1 added 48 x 2 met4 jumpers (VSS ring -> met5 strap end, under the VDD
# ring) and fixed VSS connectivity, but verify_drc = 388: on the LEFT edge the
# band x 4.1..15.5 is a vertical met4 signal channel (94 nets, every track,
# pin escapes), so a met4 jumper at any strap y shorts several of them.
# There is no clear landing window for a met3 alternative either.
# v2 does what a fresh flow would do if the jumpers lived in 02_power.tcl:
# add the jumpers first, then rip up ONLY the nets the DRC report names and
# reroute them (routeSelectedNetOnly) - NanoRoute treats the new special
# wires as obstructions. Same loop as antenna_fix6.tcl (TD/SI off, antenna
# fixer + router diodes on, plateau guard). Gate: verify_drc = 0 AND
# antenna = 0 AND VSS special connectivity pieces = 0. Also prints a hold
# summary (the 19b hold margin is +0.004 ns) so the chain can start from
# the hold step if the reroute ate it.
#   ASIC_ECO_SRC     checkpoint (05_antenna_clean.enc)
#   ASIC_ECO_DST     checkpoint to write when clean (07_vssfix.enc)
#   ASIC_ECO_PASSES  reroute passes (default 4)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 05_antenna_clean.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt vss_eco2 vss_eco2.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }

# ---- 1. geometry (as v1) -------------------------------------------------
set vss [dbGet -p top.nets.name VSS]
set ringL ""; set ringR ""; set ys {}
foreach w [dbGet $vss.sWires] {
    if {[dbGet $w.layer.name] ne "met5"} continue
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    set len [expr {max($x2-$x1, $y2-$y1)}]
    if {$len < 2000} continue
    if {$y2 - $y1 > $x2 - $x1} {
        if {$x1 < 100} { set ringL [list $x1 $x2] } elseif {$x1 > 2800} { set ringR [list $x1 $x2] }
    } else {
        lappend ys [list [expr {($y1+$y2)/2.0}] $x1 $x2 [expr {$y2-$y1}]]
    }
}
lq "VSS ring left=$ringL right=$ringR straps=[llength $ys]"
if {$ringL eq "" || $ringR eq "" || ![llength $ys]} { lq "ECO ABORT: geometry not found"; close $fh; exit 3 }

# ---- 2. jumpers (as v1) --------------------------------------------------
setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met4
set n 0
foreach s [lsort -real -index 0 $ys] {
    lassign $s yc sx1 sx2 sw
    set y1 [expr {$yc - $sw/2.0}]; set y2 [expr {$yc + $sw/2.0}]
    addStripe -nets VSS -layer met4 -direction horizontal -width $sw \
        -area [list [lindex $ringL 0] $y1 [expr {$sx1 + 1.0}] $y2] \
        -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    addStripe -nets VSS -layer met4 -direction horizontal -width $sw \
        -area [list [expr {$sx2 - 1.0}] $y1 [lindex $ringR 1] $y2] \
        -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    incr n
}
lq "jumpers added: $n straps x 2 sides"
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco2 vss_conn.rpt]
set f [open [pnr_rpt vss_eco2 vss_conn.rpt] r]; set t [read $f]; close $f
set pieces 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> pieces
lq "VSS special connectivity: IMPVFC-200 pieces=$pieces"

# ---- 3. rip up + reroute the nets the jumpers collide with ----------------
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
set drc_rpt [pnr_rpt vss_eco2 drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
lq "pass 0 (jumpers only): verify_drc = $d"
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
    set drc_rpt [pnr_rpt vss_eco2 drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    set ant_rpt [pnr_rpt vss_eco2 antenna_pass$pass.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
    lq "pass $pass: verify_drc = $d antenna = $a"
    saveDesign [pnr_ckpt 07_vssfix_pass$pass.enc]
    if {$d == 0 && $a == 0} { break }
    set key "$d/$a"
    if {$key eq $prev_key} { lq "pass $pass: PLATEAU $key"; break }
    set prev_key $key
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
if {$a < 0} {
    set ant_rpt [pnr_rpt vss_eco2 antenna_final.rpt]
    verifyProcessAntenna -report $ant_rpt
    set a [antenna_count $ant_rpt]
}
# ---- 4. connectivity again (the reroute must not have touched VSS) + hold ---
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco2 vss_conn_final.rpt]
set f [open [pnr_rpt vss_eco2 vss_conn_final.rpt] r]; set t [read $f]; close $f
set pieces 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> pieces
catch {
    report_timing -early -max_paths 1 -path_type summary > [pnr_rpt vss_eco2 hold_after.rpt]
    report_timing -late  -max_paths 1 -path_type summary > [pnr_rpt vss_eco2 setup_after.rpt]
    set hf [open [pnr_rpt vss_eco2 hold_after.rpt] r]; set ht [read $hf]; close $hf
    if {[regexp {Slack Time\s+([-0-9.]+)} $ht -> hs]} { lq "hold worst slack after ECO = $hs" }
    set sf [open [pnr_rpt vss_eco2 setup_after.rpt] r]; set st [read $sf]; close $sf
    if {[regexp {Slack Time\s+([-0-9.]+)} $st -> ss]} { lq "setup worst slack after ECO = $ss" }
}
lq "VSS ECO2: verify_drc = $d antenna = $a vss_pieces = $pieces"
pnr_note "VSS ECO2: verify_drc = $d antenna = $a vss_pieces = $pieces"
if {$d == 0 && $a == 0 && $pieces == 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix2_dirty.enc]; close $fh; exit 2
