# antenna_fix2.tcl - 2026-09-04 iter16b, fresh session on 05_legal_fix10.enc.
# antenna_fix.tcl (interactive, 09-03) attached the 7 diodes correctly but its
# ecoRoute - with drouteFixAntenna/routeInsertAntennaDiode ON and a
# refinePlace before it - ripped up the whole route (2.85M violations at 10%
# after 2 h). This version: diodes on the 7 pins, antenna auto-fix OFF,
# no refinePlace, ecoRoute in explicit ECO mode for the new connections only,
# then verify. Exit 0 only if verify_drc = 0 AND antenna = 0.
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
pnr_restore_stage 05_legal_fix10.enc
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt antenna_fix2 antenna_fix2.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
lq "restored fix10: markers=[llength [dbGet -e top.markers]]"
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
set pins {
  {FE_RC_44261_0 A} {g2164693 C} {FE_RC_47655_0 A_N} {FE_OFC431258_n_132101 A}
  {FE_OFC642428_refill_line_53 A}
  {{GEN_WAYS[2].FLAG_TAG_DATA_ARRAY_refill_line_r_reg[116]} D}
  {{MSHR_FILE_REFILL_MUX_refill_set_id_reg[1]} D}
}
set _n 0
foreach p $pins {
    lassign $p inst pin
    if {[catch {attachDiode -diodeCell sky130_fd_sc_hd__diode_2 -pin $inst $pin -prefix ANTDIODE} m]} { lq "attachDiode $inst/$pin FAILED: $m" } else { incr _n }
}
lq "diodes attached: $_n"
checkPlace [pnr_rpt antenna_fix2 checkplace.rpt]
setNanoRouteMode -routeWithEco true
ecoRoute
setNanoRouteMode -routeWithEco false
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_fix2 drc_after.rpt]
set d [llength [dbGet -e top.markers]]
verifyProcessAntenna -report [pnr_rpt antenna_fix2 antenna_after.rpt]
set _f [open [pnr_rpt antenna_fix2 antenna_after.rpt] r]; set _t [read $_f]; close $_f
set a -1; if {[regexp {No Violations Found} $_t]} { set a 0 } else { regexp {Total number of process antenna violations:\s*(\d+)} $_t -> a }
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt antenna_fix2 hold_after.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt antenna_fix2 reg2reg_after.rpt]}
lq "after antenna_fix2: verify_drc = $d antenna = $a"
pnr_note "ANTENNA FIX2: verify_drc = $d antenna = $a"
saveDesign [pnr_ckpt 05_antenna_fixed.enc]
lq "ANTENNA FIX2 DONE"; close $fh
if {$d == 0 && $a == 0} { exit 0 } else { exit 2 }
