# antenna_attach2.tcl (2026-09-09 11:00). Second attempt at the explicit diode
# attach. antenna_attach.tcl v1 and antenna_eco.tcl both wrecked the route
# (257k DRC / setup -6 and -66 ns) - common factor: ecoRoute run with
# -drouteFixAntenna true -routeInsertAntennaDiode true (the router's own
# diode insertion) plus a full refinePlace -preserveRouting. Here: attachDiode
# on every reported pin, checkPlace (ecoPlace only if the diodes overlap),
# ecoRoute with the antenna-insertion mode OFF (dirty nets only), then
# verify_drc + verifyProcessAntenna + timeDesign BEFORE any opt and a
# checkpoint; then hold opt, re-verify, checkpoint, exit.
# Knobs: ASIC_ANTENNA_ATTACH_SRC (05_route_opt.enc), ASIC_ANTENNA_ATTACH_RPT.
set _here [file normalize [file dirname [info script]]]
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
set _src [config_env ASIC_ANTENNA_ATTACH_SRC 05_route_opt.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt antenna_attach2 io_vclk.txt]]
set io_vclk_applied 0
if {[catch {source [file join $_here io_vclk.tcl]} _m]} { puts "ATTACH2 io_vclk failed: $_m" }
proc ax {msg} { puts "ATTACH2 $msg"; pnr_note "ATTACH2 $msg" }
proc wns {tag} {
    set s [get_property [report_timing -late  -max_paths 1 -collection] slack]
    set h [get_property [report_timing -early -max_paths 1 -collection] slack]
    ax "$tag: setup WNS $s hold WNS $h"
}
ax "src=$_src io_vclk=$io_vclk_applied"
wns "before"
set DIODE sky130_fd_sc_hd__diode_2
proc parse_rpt {f} {
    set pins {}
    set fh [open $f r]
    while {[gets $fh l] >= 0} {
        if {[regexp {^  (\S+)\s+\((\S+)\)\s+(\S+)\s*$} $l -> inst cell pin]} { lappend pins [list $inst $pin] }
    }
    close $fh
    return [lsort -u $pins]
}
set rpt [config_env ASIC_ANTENNA_ATTACH_RPT [pnr_rpt antenna_eco antenna_pass2.rpt]]
set pins [parse_rpt $rpt]
ax "[llength $pins] pins from [file tail $rpt]"
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
set ok 0; set bad 0
foreach ip $pins {
    lassign $ip inst pin
    if {[catch {attachDiode -diodeCell $DIODE -pin $inst $pin} m]} { incr bad; if {$bad <= 3} { ax "attachDiode failed on $inst/$pin: $m" } } else { incr ok }
}
ax "attached $ok, failed $bad"
set _cp [pnr_rpt antenna_attach2 checkplace.rpt]
catch {checkPlace $_cp}
set _ov [expr {[catch {exec grep -c -i -E {overlap|violat} $_cp} _n] ? -1 : $_n}]
ax "checkPlace lines mentioning overlap/violation: $_ov (see checkplace.rpt)"
set _dio [dbGet -e [dbGet -p2 top.insts.cell.name $DIODE].name]
ax "diode instances in design: [llength $_dio]"
if {[llength [dbGet -e -p top.insts.pStatus unplaced]]} { ax "unplaced instances present -> ecoPlace"; catch {ecoPlace} }
wns "after attach (pre-route)"
ecoRoute
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_attach2 drc_after_route.rpt]
set d [llength [dbGet -e top.markers]]
set arpt [pnr_rpt antenna_attach2 antenna_after_route.rpt]
verifyProcessAntenna -report $arpt
set fh [open $arpt r]; set t [read $fh]; close $fh
set n -1
if {[regexp {No Violations Found} $t]} { set n 0 } elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $t -> n]} { regexp {Verification Complete\s*:\s*(\d+)\s+Violation} $t -> n }
ax "after ecoRoute: verify_drc = $d, antenna = $n"
wns "after ecoRoute"
saveDesign [pnr_ckpt 05_antenna_attach.enc]
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true
if {![config_env ASIC_CTS_USEFUL_SKEW 0]} { catch {setOptMode -usefulSkew false}; catch {setOptMode -usefulSkewCCOpt none}; catch {setAnalysisMode -usefulSkew false} }
catch {optDesign -postRoute -hold}
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_attach2 drc_final.rpt]
set d [llength [dbGet -e top.markers]]
set arpt [pnr_rpt antenna_attach2 antenna_final.rpt]
verifyProcessAntenna -report $arpt
set fh [open $arpt r]; set t [read $fh]; close $fh
set n -1
if {[regexp {No Violations Found} $t]} { set n 0 } elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $t -> n]} { regexp {Verification Complete\s*:\s*(\d+)\s+Violation} $t -> n }
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt antenna_attach2 x]] -prefix final}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt antenna_attach2 x]] -prefix final}
} { catch {eval $_r} }
wns "final (after hold opt)"
ax "FINAL: verify_drc = $d, antenna = $n; checkpoint 05_antenna_attach_hold.enc"
saveDesign [pnr_ckpt 05_antenna_attach_hold.enc]
exit
