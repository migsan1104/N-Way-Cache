# legalize_fix2.tcl - 2026-09-03 iter16b, after legalize_reroute.tcl (10 left).
# Findings: the SRAM LEF has OBS on met1-3 only (detailed shapes, with gaps)
# and exports its met4 power straps as pins; the design has NO routing
# blockages. NanoRoute threads signals through the macro bodies and lands
# vias next to the strap pins. Surgical version: blockages over the three
# hotspots inside macro bodies, rip up signal wires in five boxes, ecoRoute.
# Also deletes the one VSS via that overhangs a stripe end (NSMet).
proc lq {msg} { puts "LEGALQ $msg" }
# --- census (per macro, signal wires inside the body, by layer) -------------
foreach m [dbGet -p2 top.insts.cell.name *sram*] {
    lassign [lindex [dbGet $m.box] 0] x1 y1 x2 y2
    set in [list [expr {$x1+3}] [expr {$y1+3}] [expr {$x2-3}] [expr {$y2-3}]]
    unset -nocomplain cnt; array set cnt {met1 0 met2 0 met3 0 met4 0 met5 0}
    foreach w [dbQuery -area $in -objType wire] { set l [dbGet $w.layer.name]; if {[info exists cnt($l)]} { incr cnt($l) } }
    lq "census [dbGet $m.name] m1=$cnt(met1) m2=$cnt(met2) m3=$cnt(met3) m4=$cnt(met4) m5=$cnt(met5)"
}
# --- D: NSMet VSS via ---------------------------------------------------------
set _vs [dbQuery -area {921.5 2859.5 922.5 2860.5} -objType sVia]
foreach v $_vs { lq "delete sVia [dbGet $v.via.name] net=[dbGet $v.net.name] pt=[dbGet $v.pt]"; dbDeleteObj $v }
# --- A/C: blockages inside macro bodies over the hotspots ---------------------
set _blk {A1 {1540 458 1620 484} A2 {1960 458 2030 484} C {2640 2195 2660 2210}}
foreach {nm b} $_blk { createRouteBlk -name legal_$nm -box $b -layer {met1 met2 met3 met4} -exceptpgnet }
lq "rBlkgs now=[llength [dbGet -e top.fplan.rBlkgs]]"
# --- rip up signal wires in the hotspot boxes (+ the two SW shorts) ----------
set _rip {A1 {1540 458 1620 484} A2 {1960 458 2030 484} C {2640 2195 2660 2210} B1 {315 712 340 728} B2 {690 942 703 956}}
foreach {nm b} $_rip {
    deselectAll
    editSelect -area $b -type Signal
    set n [llength [dbGet -e selected]]
    lq "ripup $nm box=$b wires=$n"
    editDelete -selected
}
deselectAll
ecoRoute
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix2.rpt]
pnr_note "LEGAL after fix2: verify_drc = [llength [dbGet -e top.markers]]"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt legalize hold_after_fix2.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_fix2.rpt]}
saveDesign [pnr_ckpt 05_legal_fix2.enc]
pnr_note "LEGAL FIX2 DONE"
