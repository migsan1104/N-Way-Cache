# legalize_fix7.tcl - 2026-09-03 iter16b, from 05_legal_fix3.enc (7): full
# incremental routeDesign (NanoRoute free to rip up any net, DRC-fix
# iterations), the closure tool the targeted passes (fix4-6) could not be.
# Guidance: met4 blocked over all 16 macro bodies (452 PG straps there, no
# room for signal met4) - removed before verify so existing wires are not
# flagged. Unattended; saves 05_legal_fix7.enc.
set fh [open [pnr_rpt legalize fix7.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
freeDesign
pnr_restore_stage 05_legal_fix3.enc
lq "restored fix3: markers=[llength [dbGet -e top.markers]]"
deleteRouteBlk -all
foreach m [dbGet -p2 top.insts.cell.name *sram*] {
    lassign [lindex [dbGet $m.box] 0] x1 y1 x2 y2
    createRouteBlk -name g_m4_[dbGet $m.name] -box [list [expr {$x1+1.5}] [expr {$y1+2.0}] [expr {$x2-1.5}] [expr {$y2-2.0}]] -layer {met4} -exceptpgnet
}
lq "met4 guidance blockages=[llength [dbGet -e top.fplan.rBlkgs]]"
setNanoRouteMode -drouteEndIteration 40
setNanoRouteMode -routeWithTimingDriven true -routeWithSiDriven true
routeDesign
deleteRouteBlk -all
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix7.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fix7: verify_drc = $n"
pnr_note "LEGAL after fix7: verify_drc = $n"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt legalize hold_after_fix7.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_fix7.rpt]}
saveDesign [pnr_ckpt 05_legal_fix7.enc]
lq "FIX7 DONE"; close $fh
pnr_note "LEGAL FIX7 DONE"
