# legalize_fix3.tcl - 2026-09-03 iter16b (10 left after fix2). probe3 census:
# thousands of met1/met2 signal segments thread every SRAM body (the LEF OBS
# is shape-level, with gaps); all 10 residuals are threading artifacts.
# Guidance blockages over the four macros involved, rip up ONLY the seven
# offending nets, full route on them, then remove the blockages so the
# thousands of other threading wires are not flagged against them.
set fh [open [pnr_rpt legalize fix3.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
deleteRouteBlk -all
lq "rBlkgs after delete=[llength [dbGet -e top.fplan.rBlkgs]]"
set _guide {
  b2   {1471.5 42.0 1845.0 484.5}
  b3   {1888.0 42.0 2261.5 484.5}
  w3b3 {2415.3 1888.0 2858.5 2261.5}
  w2b0 {41.5 639.0 484.5 1012.0}
}
foreach {nm b} $_guide { createRouteBlk -name guide_$nm -box $b -layer {met1 met2 met3 met4} -exceptpgnet }
lq "guide rBlkgs=[llength [dbGet -e top.fplan.rBlkgs]]"
set _nets {
 FE_OFN16004_refill_line_56 FE_OFN360904_n FE_OFN321786_n_244585 FE_OFN728002_FE_OFN324829_n
 FE_OFN638137_n_243696
 FE_OFN333367_FE_OFN318246_FE_OFN241886_n_133541 FE_OFN314015_n_83884
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
# NSMet: the VSS via overhanging a stripe end - select specials in the box, delete only vias
deselectAll
editSelect -area {921.5 2859.5 922.5 2860.5} -type Special
foreach o [dbGet -e selected] { lq "nsmet selected objType=[dbGet $o.objType] net=[dbGet -e $o.net.name] via=[dbGet -e $o.via.name] layer=[dbGet -e $o.layer.name]" }
foreach o [dbGet -e selected] { if {[string match *Via* [dbGet $o.objType]]} { lq "nsmet DELETE [dbGet $o.objType] [dbGet -e $o.via.name]"; dbDeleteObj $o } }
deselectAll
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix3.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fix3: verify_drc = $n"
pnr_note "LEGAL after fix3: verify_drc = $n"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt legalize hold_after_fix3.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_fix3.rpt]}
saveDesign [pnr_ckpt 05_legal_fix3.enc]
lq "FIX3 DONE"; close $fh
pnr_note "LEGAL FIX3 DONE"
