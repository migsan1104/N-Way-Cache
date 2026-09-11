# antenna_attach4.tcl (2026-09-09). Last antenna violator on iter26b after v3:
# FE_OCPN309085_FE_OFN5269_alloc_tag_7 -> bank_tags_reg[3][7]/D, met3 side-area
# PAR 401.9 vs 400, D.Area 0 even with three diodes on the pin (they are not on
# the met3 segment the checker attributes) and one of them unplaceable.
# Fix by layer hopping instead: delete the unplaceable diode(s), rip up ONLY
# that net, reroute it alone with -drouteFixAntenna true (jumpers) and diode
# insertion OFF, then verify DRC + antenna + timing, checkpoint, exit.
# Knobs: ASIC_ANTENNA_ATTACH_SRC (05_antenna_attach3_hold.enc), ASIC_ANTENNA_NET,
# ASIC_ANTENNA_DROP_INSTS (space list of instances to delete first).
set _here [file normalize [file dirname [info script]]]
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
set _src [config_env ASIC_ANTENNA_ATTACH_SRC 05_antenna_attach3_hold.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt antenna_attach4 io_vclk.txt]]
set io_vclk_applied 0
if {[catch {source [file join $_here io_vclk.tcl]} _m]} { puts "ATTACH4 io_vclk failed: $_m" }
proc ax {msg} { puts "ATTACH4 $msg"; pnr_note "ATTACH4 $msg" }
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
ax "src=$_src io_vclk=$io_vclk_applied"
wns "before"
set NET [config_env ASIC_ANTENNA_NET FE_OCPN309085_FE_OFN5269_alloc_tag_7]
foreach _i [config_env ASIC_ANTENNA_DROP_INSTS {}] {
    if {[catch {deleteInst $_i} m]} { ax "deleteInst $_i failed: $m" } else { ax "deleted $_i" }
}
if {[dbGet -p top.nets.name $NET] == 0} { ax "net $NET not found"; exit 5 }
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode false -routeAntennaCellName sky130_fd_sc_hd__diode_2
editDelete -net $NET
deselectAll; selectNet $NET
setNanoRouteMode -routeSelectedNetOnly true
routeDesign
setNanoRouteMode -routeSelectedNetOnly false
deselectAll
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_attach4 drc_final.rpt]
set d [llength [dbGet -e top.markers]]
set arpt [pnr_rpt antenna_attach4 antenna_final.rpt]
verifyProcessAntenna -report $arpt
set n [count_ant $arpt]
catch {checkPlace [pnr_rpt antenna_attach4 checkplace_final.rpt]}
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt antenna_attach4 x]] -prefix final}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt antenna_attach4 x]] -prefix final}
} { catch {eval $_r} }
wns "final"
ax "FINAL: verify_drc = $d, antenna = $n; checkpoint 05_antenna_final.enc"
saveDesign [pnr_ckpt 05_antenna_final.enc]
exit
