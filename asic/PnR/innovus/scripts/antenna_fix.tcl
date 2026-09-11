# antenna_fix.tcl - 2026-09-03 iter16b: explicit diode insertion on the seven
# pins verifyProcessAntenna lists after the DRC-clean route (ecoRoute
# -fix_drc with diode insertion enabled changed nothing, 7 -> 7). Runs at
# the legalize prompt on the 05_legal_fix10 database; saves 05_antenna_fixed.enc.
set fh [open [pnr_rpt antenna_fix antenna_fix.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
set pins {
  {FE_RC_44261_0 A}
  {g2164693 C}
  {FE_RC_47655_0 A_N}
  {FE_OFC431258_n_132101 A}
  {FE_OFC642428_refill_line_53 A}
  {{GEN_WAYS[2].FLAG_TAG_DATA_ARRAY_refill_line_r_reg[116]} D}
  {{MSHR_FILE_REFILL_MUX_refill_set_id_reg[1]} D}
}
verifyProcessAntenna -report [pnr_rpt antenna_fix antenna_before.rpt]
set _n 0
foreach p $pins {
    lassign $p inst pin
    if {[dbGet -p top.insts.name $inst] == 0} { lq "NO SUCH INST $inst"; continue }
    if {[catch {attachDiode -diodeCell sky130_fd_sc_hd__diode_2 -pin $inst $pin -prefix ANTDIODE} m]} { lq "attachDiode $inst/$pin FAILED: $m" } else { incr _n; lq "diode attached: $inst/$pin" }
}
lq "diodes attached: $_n ; ANTDIODE insts=[llength [dbGet -e [dbGet -p top.insts.name ANTDIODE*].name]]"
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode true -routeAntennaCellName sky130_fd_sc_hd__diode_2
catch {refinePlace -preserveRouting true}
ecoRoute
catch {optDesign -postRoute -hold}
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_fix drc_after.rpt]
set d [llength [dbGet -e top.markers]]
verifyProcessAntenna -report [pnr_rpt antenna_fix antenna_after.rpt]
set _f [open [pnr_rpt antenna_fix antenna_after.rpt] r]; set _t [read $_f]; close $_f
set a -1; regexp {Total number of process antenna violations:\s*(\d+)} $_t -> a
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt antenna_fix hold_after.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt antenna_fix reg2reg_after.rpt]}
lq "after antenna_fix: verify_drc = $d antenna = $a"
pnr_note "ANTENNA FIX: verify_drc = $d antenna = $a"
saveDesign [pnr_ckpt 05_antenna_fixed.enc]
lq "ANTENNA FIX DONE"; close $fh
pnr_note "ANTENNA FIX DONE"
