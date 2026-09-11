# legalize_fix5.tcl - 2026-09-03 iter16b, restart from 05_legal_fix3.enc (7).
# fix4 lesson: rerouting the offender ALONE under guidance clears its marker
# (left strip, W3B3 both cleared); rerouting long partner nets creates new
# knots. So: offenders only, one guidance set each, sequentially.
set fh [open [pnr_rpt legalize fix5.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
freeDesign
pnr_restore_stage 05_legal_fix3.enc
lq "restored fix3: markers=[llength [dbGet -e top.markers]]"
proc reroute_one {net guides} {
    global fh
    deleteRouteBlk -all
    foreach {nm b l} $guides { createRouteBlk -name guide_$nm -box $b -layer $l -exceptpgnet }
    editDelete -net $net
    deselectAll; selectNet $net
    setNanoRouteMode -routeSelectedNetOnly true
    routeDesign
    setNanoRouteMode -routeSelectedNetOnly false
    deselectAll
    deleteRouteBlk -all
    set np [dbGet -p top.nets.name $net]
    lq "rerouted $net wires=[llength [dbGet -e $np.wires]] layers=[lsort -u [dbGet -e $np.wires.layer.name]]"
}
# bank-3 top knot: keep the net off bank3 entirely (met1-5) and off the met5 track it shared
reroute_one FE_OFN321786_n_244585 {b3_all {1888.0 42.0 2261.5 484.5} {met1 met2 met3 met4 met5}}
# left strip: body + strip guidance (fix4 cleared it this way)
reroute_one FE_OFN314015_n_83884 {w2b0 {41.5 639.0 484.5 1012.0} {met1 met2 met3 met4} w2b0_l {16.0 630.0 40.0 1020.0} {met1 met2 met3 met4 met5}}
# W3B3: body guidance + block met4 at the exact collision spot in the left strip
reroute_one FE_OFN638137_n_243696 {w3b3 {2415.3 1888.0 2858.5 2261.5} {met1 met2 met3 met4} w3b3_spot {2410.5 2194.0 2413.0 2201.0} {met4 met5}}
# NSMet: delete the overhanging VSS via, then check VSS special connectivity
set _del 0
foreach o [dbQuery -area {921.5 2859.5 922.5 2860.5} -objType {sVia}] { lq "nsmet obj [dbGet $o.objType] via=[dbGet -e $o.via.name] net=[dbGet -e $o.net.name] pt=[dbGet -e $o.pt]"; if {[dbGet -e $o.net.name] eq "VSS"} { dbDeleteObj $o; incr _del } }
lq "nsmet vias deleted=$_del"
catch { verifyConnectivity -type special -net VSS -noAntenna -noWeakConnect -report [pnr_rpt legalize vss_conn_fix5.rpt] } _m
lq "VSS connectivity: $_m"
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix5.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fix5: verify_drc = $n"
pnr_note "LEGAL after fix5: verify_drc = $n"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt legalize hold_after_fix5.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_fix5.rpt]}
saveDesign [pnr_ckpt 05_legal_fix5.enc]
lq "FIX5 DONE"; close $fh
pnr_note "LEGAL FIX5 DONE"
