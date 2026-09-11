# antenna_fix3_reroute.tcl - 2026-09-06 (iter19b): after antenna_fix3 left a
# single li1 short between a regular wire and a freshly placed diode pin,
# rip up the nets named in ASIC_REROUTE_NETS and reroute only those (TD/SI/
# antenna-fix off, like legalize_targeted.tcl), verify, and overwrite
# 05_antenna_fixed.enc iff drc = 0 & antenna = 0. Exit 0 iff clean.
#   ASIC_REROUTE_SRC   checkpoint (05_antenna_fixed.enc)
#   ASIC_REROUTE_NETS  space-separated net names
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_REROUTE_SRC 05_antenna_fixed.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt antenna_fix3 reroute.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
set nets [config_env ASIC_REROUTE_NETS {}]
lq "src=$_src nets=$nets markers_before=[llength [dbGet -e top.markers]]"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false -drouteFixAntenna false
foreach n $nets { editDelete -net $n }
deselectAll
foreach n $nets { selectNet $n }
setNanoRouteMode -routeSelectedNetOnly true
routeDesign
setNanoRouteMode -routeSelectedNetOnly false
deselectAll
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_fix3 drc_reroute.rpt]
set d [llength [dbGet -e top.markers]]
set rpt [pnr_rpt antenna_fix3 antenna_reroute.rpt]
verifyProcessAntenna -report $rpt
set f [open $rpt r]; set t [read $f]; close $f
set a -1
if {[regexp {No Violations Found} $t]} { set a 0 } elseif {[regexp {Total number of process antenna violations:\s*(\d+)} $t -> _a]} { set a $_a }
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt antenna_fix3 hold_reroute.rpt]}
lq "REROUTE: verify_drc = $d antenna = $a"
pnr_note "ANTENNA FIX3 REROUTE: verify_drc = $d antenna = $a"
if {$d == 0 && $a == 0} { saveDesign [pnr_ckpt 05_antenna_fixed.enc]; close $fh; exit 0 }
saveDesign [pnr_ckpt 05_antenna_reroute_dirty.enc]
close $fh
exit 2
