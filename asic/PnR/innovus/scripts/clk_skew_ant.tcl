# clk_skew_ant.tcl (2026-09-10): clear the 6 antenna violations the clock-skew
# ECO's ecoRoute left on signal pins. attachDiode (insertion OFF) on each pin,
# legalize with the attach6 discipline (eco legalizer, then explicit row-gap
# placement, zero overlaps or abort), ecoRoute, verify; any pin still violating
# gets its net ripped up and rerouted alone with -drouteFixAntenna true (attach5
# layer hopping). Save ASIC_ECO_DST only if DRC 0, antenna 0, overlaps 0.
# Knobs: ASIC_ECO_SRC (05_clkskew8_dirty.enc) ASIC_ECO_DST (05_clkskew8.enc) ASIC_ANTENNA_RPT
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 05_clkskew8_dirty.enc]
set _dst [config_env ASIC_ECO_DST 05_clkskew8.enc]
set rpt  [config_env ASIC_ANTENNA_RPT [pnr_rpt clk_skew antenna_final.rpt]]
set DIODE sky130_fd_sc_hd__diode_2
set WIN 60; set SITE 0.46
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt clk_skew_ant io_vclk.txt]]
set io_vclk_applied 0
catch {source [file join [file dirname [info script]] io_vclk.tcl]}
proc ax {msg} { puts "SKEWANT $msg"; pnr_note "SKEWANT $msg" }
proc count_ant {rpt} {
    set fh [open $rpt r]; set t [read $fh]; close $fh; set n -1
    if {[regexp {No Violations Found} $t]} { set n 0 } elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $t -> n]} { regexp {Verification Complete\s*:\s*(\d+)} $t -> n }
    return $n
}
proc parse_rpt {f} {
    set pins {}; set fh [open $f r]
    while {[gets $fh l] >= 0} { if {[regexp {^  (\S+)\s+\((\S+)\)\s+(\S+)\s*$} $l -> inst cell pin]} { if {$cell ne "sky130_fd_sc_hd__diode_2"} { lappend pins [list $inst $pin] } } }
    close $fh; return [lsort -u $pins]
}
proc overlapping {insts} {
    set bad {}
    foreach d $insts {
        set p [dbGet -p top.insts.name $d]; if {$p eq "0x0" || $p eq ""} { continue }
        set box [lindex [dbGet $p.box] 0]
        foreach o [dbQuery -area $box -objType inst] {
            if {$o == $p || [dbGet $o.cell.baseClass] eq "block"} { continue }
            lassign [lindex [dbGet $o.box] 0] ox1 oy1 ox2 oy2; lassign $box x1 y1 x2 y2
            if {$ox2 - $x1 > 0.001 && $x2 - $ox1 > 0.001 && $oy2 - $y1 > 0.001 && $y2 - $oy1 > 0.001} { lappend bad $d; break }
        }
    }
    return $bad
}
proc place_in_gap {name} {
    global WIN SITE
    set p [dbGet -p top.insts.name $name]
    lassign [lindex [dbGet $p.box] 0] x1 y1 x2 y2
    set w [expr {$x2 - $x1}]; set orient [dbGet $p.orient]
    set occ {}
    foreach o [dbQuery -area [list [expr {$x1 - $WIN}] [expr {$y1 + 0.01}] [expr {$x2 + $WIN}] [expr {$y2 - 0.01}]] -objType inst] {
        if {$o == $p} { continue }
        lassign [lindex [dbGet $o.box] 0] ox1 oy1 ox2 oy2; lappend occ [list $ox1 $ox2] }
    set occ [lsort -real -index 0 $occ]
    set rowx [lindex [lindex [dbGet top.fPlan.coreBox] 0] 0]
    set best ""; set bestd 1e9; set prev_end [expr {$x1 - $WIN}]
    foreach seg [concat $occ [list [list [expr {$x2 + $WIN}] [expr {$x2 + $WIN}]]]] {
        lassign $seg s e
        if {$s - $prev_end >= $w + 0.001} {
            foreach cand [list $prev_end [expr {$s - $w}]] {
                set cx [expr {$rowx + round(($cand - $rowx) / $SITE) * $SITE}]
                if {$cx < $prev_end - 0.001} { set cx [expr {$cx + $SITE}] }
                if {$cx + $w > $s + 0.001} { set cx [expr {$cx - $SITE}] }
                if {$cx < $prev_end - 0.001 || $cx + $w > $s + 0.001} { continue }
                if {abs($cx - $x1) < $bestd} { set bestd [expr {abs($cx - $x1)}]; set best $cx } } }
        if {$e > $prev_end} { set prev_end $e }
    }
    if {$best eq ""} { return "nogap" }
    placeInstance $name $best $y1 $orient -placed
    return $best
}
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
set pins [parse_rpt $rpt]
ax "src=$_src pins to fix: [llength $pins]"
set k 0; set dio {}
foreach ip $pins {
    lassign $ip inst pin; incr k
    if {[catch {attachDiode -diodeCell $DIODE -pin $inst $pin -prefix USKD_${k}_} m]} { ax "attachDiode $inst/$pin failed: $m" }
}
set dio [dbGet -e [dbGet -p top.insts.name USKD_*].name]
ax "diodes attached: [llength $dio]"
foreach d $dio { catch { dbSet [dbGet -p top.insts.name $d].pStatus placed } }
catch {refinePlace -eco true -inst $dio}
set bad [overlapping $dio]
ax "overlapping after refinePlace -eco: [llength $bad]"
foreach d $bad { ax "  $d -> [place_in_gap $d]" }
set bad [overlapping $dio]
if {[llength $bad]} { ax "ABORT: [llength $bad] diodes still overlap"; exit 5 }
ecoRoute
clearDrc
verify_drc -limit 100000 -report [pnr_rpt clk_skew_ant drc_pass1.rpt]
set d [llength [dbGet -e top.markers]]
set arpt [pnr_rpt clk_skew_ant antenna_pass1.rpt]
verifyProcessAntenna -report $arpt
set n [count_ant $arpt]
ax "after diodes + ecoRoute: verify_drc = $d, antenna = $n"
if {$n > 0} {
    # layer hopping for the stubborn ones: rip up only those nets, reroute alone with the antenna fixer
    setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode false
    set nets {}
    foreach ip [parse_rpt $arpt] { lassign $ip inst pin
        set nn [get_object_name [get_nets -quiet -of_objects [get_pins -quiet $inst/$pin]]]
        if {$nn ne ""} { lappend nets $nn } }
    set nets [lsort -u $nets]
    ax "layer-hop reroute of [llength $nets] nets: $nets"
    foreach nn $nets { catch {editDelete -net $nn} }
    deselectAll; foreach nn $nets { catch {selectNet $nn} }
    setNanoRouteMode -routeSelectedNetOnly true
    routeDesign
    setNanoRouteMode -routeSelectedNetOnly false
    deselectAll
    setNanoRouteMode -drouteFixAntenna false
    clearDrc
    verify_drc -limit 100000 -report [pnr_rpt clk_skew_ant drc_pass2.rpt]
    set d [llength [dbGet -e top.markers]]
    set arpt [pnr_rpt clk_skew_ant antenna_pass2.rpt]
    verifyProcessAntenna -report $arpt
    set n [count_ant $arpt]
    ax "after layer hop: verify_drc = $d, antenna = $n"
}
set bad [overlapping $dio]
catch {checkPlace [pnr_rpt clk_skew_ant checkplace_final.rpt]}
set D [file dirname [pnr_rpt clk_skew_ant x]]
foreach _r {
    {timeDesign -postRoute       -outDir $D -prefix final}
    {timeDesign -postRoute -hold -outDir $D -prefix final}
} { catch {eval $_r} }
set s [get_property [report_timing -late  -max_paths 1 -collection] slack]
set h [get_property [report_timing -early -max_paths 1 -collection] slack]
set regs [get_cells -quiet [config_env ASIC_SKEW_REGS {COMPARE_SELECT_REPLACE_out_rdata_reg* COMPARE_SELECT_REPLACE_out_victim_line_reg*}]]
set tr [get_property [report_timing -late -to $regs -max_paths 1 -collection] slack]
ax "FINAL: verify_drc = $d, antenna = $n, diode overlaps = [llength $bad], setup WNS $s hold WNS $h, to_regs setup $tr"
if {$d == 0 && $n == 0 && ![llength $bad]} { saveDesign [pnr_ckpt $_dst]; ax "saved $_dst (clean)" } else { saveDesign [pnr_ckpt [string map {.enc _dirty2.enc} $_dst]]; ax "NOT CLEAN - saved [string map {.enc _dirty2.enc} $_dst]" }
exit
