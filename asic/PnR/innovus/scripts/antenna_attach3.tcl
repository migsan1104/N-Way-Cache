# antenna_attach3.tcl (2026-09-09). Finish after antenna_attach2: (1) legalize
# the diodes attachDiode dropped on top of other cells (checkPlace: 79
# overlaps) with refinePlace -eco -inst on the diode list only; (2) the pins
# still violating (v2 left 4 on 3 nets, PAR 401..7026 vs 400..4582) get
# ASIC_ANTENNA_EXTRA (2) more diodes each; (3) ecoRoute with insertion OFF,
# verify DRC + antenna + timing, checkpoint, hold opt, re-verify, checkpoint, exit.
set _here [file normalize [file dirname [info script]]]
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
set _src [config_env ASIC_ANTENNA_ATTACH_SRC 05_antenna_attach_hold.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt antenna_attach3 io_vclk.txt]]
set io_vclk_applied 0
if {[catch {source [file join $_here io_vclk.tcl]} _m]} { puts "ATTACH3 io_vclk failed: $_m" }
proc ax {msg} { puts "ATTACH3 $msg"; pnr_note "ATTACH3 $msg" }
proc wns {tag} {
    set s [get_property [report_timing -late  -max_paths 1 -collection] slack]
    set h [get_property [report_timing -early -max_paths 1 -collection] slack]
    ax "$tag: setup WNS $s hold WNS $h"
}
proc count_ant {rpt} {
    set fh [open $rpt r]; set t [read $fh]; close $fh
    set n -1
    if {[regexp {No Violations Found} $t]} { set n 0 } elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $t -> n]} { regexp {Verification Complete\s*:\s*(\d+)\s+Violation} $t -> n }
    return $n
}
proc parse_rpt {f} {
    set pins {}
    set fh [open $f r]
    while {[gets $fh l] >= 0} {
        if {[regexp {^  (\S+)\s+\((\S+)\)\s+(\S+)\s*$} $l -> inst cell pin]} { if {$cell ne "sky130_fd_sc_hd__diode_2"} { lappend pins [list $inst $pin] } }
    }
    close $fh
    return [lsort -u $pins]
}
ax "src=$_src io_vclk=$io_vclk_applied"
wns "before"
set DIODE sky130_fd_sc_hd__diode_2
set EXTRA [config_env ASIC_ANTENNA_EXTRA 2]
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
set rpt [config_env ASIC_ANTENNA_ATTACH_RPT [pnr_rpt antenna_attach2 antenna_final.rpt]]
set pins [parse_rpt $rpt]
ax "[llength $pins] pins still violating in [file tail $rpt]; adding $EXTRA diodes each"
set k 0
foreach ip $pins {
    lassign $ip inst pin
    for {set e 1} {$e <= $EXTRA} {incr e} {
        incr k
        if {[catch {attachDiode -diodeCell $DIODE -pin $inst $pin -prefix FE_DIODE3_${k}_} m]} { ax "attachDiode failed on $inst/$pin: $m" }
    }
}
set dio [dbGet -e [dbGet -p2 top.insts.cell.name $DIODE].name]
ax "diode instances now: [llength $dio]"
if {[catch {refinePlace -eco true -inst $dio} m]} { ax "refinePlace -eco -inst failed: $m" }
catch {checkPlace [pnr_rpt antenna_attach3 checkplace.rpt]}
wns "after legalize (pre-route)"
ecoRoute
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_attach3 drc_after_route.rpt]
set d [llength [dbGet -e top.markers]]
set arpt [pnr_rpt antenna_attach3 antenna_after_route.rpt]
verifyProcessAntenna -report $arpt
set n [count_ant $arpt]
ax "after ecoRoute: verify_drc = $d, antenna = $n"
wns "after ecoRoute"
saveDesign [pnr_ckpt 05_antenna_attach3.enc]
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true
if {![config_env ASIC_CTS_USEFUL_SKEW 0]} { catch {setOptMode -usefulSkew false}; catch {setOptMode -usefulSkewCCOpt none}; catch {setAnalysisMode -usefulSkew false} }
# v2 lesson: optDesign -postRoute -hold on a state with unlegalized diodes took
# DRC 0 -> 223 and antenna 4 -> 22 for no timing gain (hold was already +0.071).
# Run it only if hold is actually negative (ASIC_ANTENNA_HOLDOPT=1 forces it).
set _h [get_property [report_timing -early -max_paths 1 -collection] slack]
if {$_h < 0 || [config_env ASIC_ANTENNA_HOLDOPT 0]} { ax "hold $_h -> running hold opt"; catch {optDesign -postRoute -hold} } else { ax "hold $_h >= 0 -> hold opt skipped" }
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_attach3 drc_final.rpt]
set d [llength [dbGet -e top.markers]]
set arpt [pnr_rpt antenna_attach3 antenna_final.rpt]
verifyProcessAntenna -report $arpt
set n [count_ant $arpt]
catch {checkPlace [pnr_rpt antenna_attach3 checkplace_final.rpt]}
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt antenna_attach3 x]] -prefix final}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt antenna_attach3 x]] -prefix final}
} { catch {eval $_r} }
wns "final (after hold opt)"
ax "FINAL: verify_drc = $d, antenna = $n; checkpoint 05_antenna_attach3_hold.enc"
saveDesign [pnr_ckpt 05_antenna_attach3_hold.enc]
exit
