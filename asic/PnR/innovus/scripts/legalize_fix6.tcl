# legalize_fix6.tcl - 2026-09-03 iter16b, restart from 05_legal_fix3.enc (7).
# Collective re-plan of the bank2/bank3 channel + the strip above bank3 (the
# stubborn net has no legal path with every other net frozen), plus the two
# recipes that worked in fix5 (left strip) and a widened W3B3 spot block.
set fh [open [pnr_rpt legalize fix6.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
freeDesign
pnr_restore_stage 05_legal_fix3.enc
lq "restored fix3: markers=[llength [dbGet -e top.markers]]"
proc route_sel {nets} {
    deselectAll
    foreach n $nets { selectNet $n }
    setNanoRouteMode -routeSelectedNetOnly true
    routeDesign
    setNanoRouteMode -routeSelectedNetOnly false
    deselectAll
}
# 1. left strip (fix5 recipe, cleared)
deleteRouteBlk -all
createRouteBlk -name g_w2b0 -box {41.5 639.0 484.5 1012.0} -layer {met1 met2 met3 met4} -exceptpgnet
createRouteBlk -name g_w2b0l -box {16.0 630.0 40.0 1020.0} -layer {met1 met2 met3 met4 met5} -exceptpgnet
editDelete -net FE_OFN314015_n_83884
route_sel {FE_OFN314015_n_83884}
lq "step1 left strip done"
# 2. W3B3: body guidance + the whole strip segment blocked on met4/met5
deleteRouteBlk -all
createRouteBlk -name g_w3b3 -box {2415.3 1888.0 2858.5 2261.5} -layer {met1 met2 met3 met4} -exceptpgnet
createRouteBlk -name g_w3b3s -box {2409.0 2188.0 2413.7 2215.0} -layer {met4 met5} -exceptpgnet
editDelete -net FE_OFN638137_n_243696
route_sel {FE_OFN638137_n_243696}
lq "step2 W3B3 done"
# 3. channel re-plan: met4 guidance over bank2/bank3 bodies only; rip up every
#    signal wire in the channel + the strip above bank3; the stubborn net fully
deleteRouteBlk -all
createRouteBlk -name g_b2m4 -box {1471.5 42.0 1845.0 484.5} -layer {met4} -exceptpgnet
createRouteBlk -name g_b3m4 -box {1888.0 42.0 2261.5 484.5} -layer {met4} -exceptpgnet
editDelete -net FE_OFN321786_n_244585
set cut {FE_OFN321786_n_244585}
foreach b {{1846.5 380.0 1888.0 510.0} {1846.5 486.5 2035.0 545.0}} {
    deselectAll
    editSelect -area $b -type Signal
    foreach o [dbGet -e selected] { set nn [dbGet -e $o.net.name]; if {$nn ne "" && [lsearch -exact $cut $nn] < 0} { lappend cut $nn } }
    lq "ripup box=$b selected=[llength [dbGet -e selected]] cut_nets_so_far=[llength $cut]"
    editDelete -selected
}
deselectAll
route_sel $cut
deleteRouteBlk -all
lq "step3 channel re-plan done, nets=[llength $cut]"
# 4. NSMet via
set _del 0
foreach o [dbQuery -area {921.5 2859.5 922.5 2860.5} -objType {via sVia}] {
    lq "nsmet obj [dbGet $o.objType] via=[dbGet -e $o.via.name] net=[dbGet -e $o.net.name] pt=[dbGet -e $o.pt]"
    if {[string match *Via* [dbGet $o.objType]] && [dbGet -e $o.net.name] eq "VSS"} { dbDeleteObj $o; incr _del }
}
lq "nsmet vias deleted=$_del"
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix6.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fix6: verify_drc = $n"
pnr_note "LEGAL after fix6: verify_drc = $n"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt legalize hold_after_fix6.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_fix6.rpt]}
saveDesign [pnr_ckpt 05_legal_fix6.enc]
lq "FIX6 DONE"; close $fh
pnr_note "LEGAL FIX6 DONE"
