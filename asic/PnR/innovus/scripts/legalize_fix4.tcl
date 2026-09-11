# legalize_fix4.tcl - 2026-09-03 iter16b (7 left after fix3). Three knots
# rerouted as groups under guidance blockages (removed afterwards), plus a
# met4 VSS patch over the via that overhangs a stripe end (NSMet).
set fh [open [pnr_rpt legalize fix4.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
deleteRouteBlk -all
set _guide {
  b3_all   {1888.0 42.0 2261.5 484.5}   {met1 met2 met3 met4 met5}
  w2b0     {41.5 639.0 484.5 1012.0}    {met1 met2 met3 met4}
  w2b0_l   {16.0 630.0 40.0 1020.0}     {met1 met2 met3 met4 met5}
  w3b3     {2415.3 1888.0 2858.5 2261.5} {met1 met2 met3 met4}
}
foreach {nm b l} $_guide { createRouteBlk -name guide_$nm -box $b -layer $l -exceptpgnet }
lq "guide rBlkgs=[llength [dbGet -e top.fplan.rBlkgs]]"
set _nets {
 FE_OFN321786_n_244585 FE_OCPN775860_n FE_OFN341307_n
 FE_OFN314015_n_83884
 FE_OFN638137_n_243696 FE_OCPN633666_FE_OFN639079 FE_OFN262365_n_268829
}
foreach n $_nets { if {[dbGet -p top.nets.name $n] == 0} { error "LEGAL FAIL: no net $n" } }
foreach n $_nets { editDelete -net $n }
deselectAll
foreach n $_nets { selectNet $n }
setNanoRouteMode -routeSelectedNetOnly true
routeDesign
setNanoRouteMode -routeSelectedNetOnly false
deselectAll
foreach n $_nets { set np [dbGet -p top.nets.name $n]; lq "rerouted $n wires=[llength [dbGet -e $np.wires]] layers=[lsort -u [dbGet -e $np.wires.layer.name]]" }
deleteRouteBlk -all
lq "rBlkgs final=[llength [dbGet -e top.fplan.rBlkgs]]"
# NSMet patch: 1.6-wide met4 VSS stripe piece covering the via + stripe end
set _before [llength [dbQuery -area {920 2859 923 2862} -objType sWire]]
setEdit -nets VSS -type Special -shape STRIPE -layer_vertical met4 -width_vertical 1.6
editAddRoute 921.8 2859.3
editCommitRoute 921.8 2861.5
lq "nsmet patch sWires in box before=$_before after=[llength [dbQuery -area {920 2859 923 2862} -objType sWire]]"
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix4.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fix4: verify_drc = $n"
pnr_note "LEGAL after fix4: verify_drc = $n"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt legalize hold_after_fix4.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_fix4.rpt]}
saveDesign [pnr_ckpt 05_legal_fix4.enc]
lq "FIX4 DONE"; close $fh
pnr_note "LEGAL FIX4 DONE"
