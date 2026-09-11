# legalize_reroute.tcl - 2026-09-03 iter16b, after legalize_fix.tcl (9 left).
# Rip up and reroute ONLY the nets carrying the residual verify_drc markers
# (4 met4 short/spacing vs GEN_WAYS[0] bank2/3 SRAM pins, 3 met1 wire shorts
# in the SW, 1 met2 short into the W3B3 macro OBS). The NSMet on VSS is a PG
# via overlap - inspected here, fixed separately.
set _nets {
 FE_OCPN359581_FE_OFN12056_GEN_WAYS_0__FLAG_TAG_DATA_ARRAY_refill_set_idx_r_7
 FE_OCPN437583_n FE_OFN321786_n_244585 FE_OFN770657_n_259144
 FE_OFN651614_n_184743 FE_OCPN329965_n_222620 FE_OFN314015_n_83884
 FE_OFN259889_n_253755 FE_OFN408030_n_186164 FE_OFN641240_n FE_OFN638137_n_243696
}
# what is under the NSMet marker and the two met4 macro-pin shorts
foreach b {{921.9 2859.8 922.2 2860.2} {1564.7 470.6 1565.0 471.9} {2011.9 470.6 2012.0 471.9}} {
    foreach o [dbQuery -area $b -objType {sWire sVia wire via}] {
        catch { puts "LEGALQ box=$b obj=[dbGet $o.objType] layer=[dbGet -e $o.layer.name] net=[dbGet -e $o.net.name] box=[dbGet -e $o.box] via=[dbGet -e $o.via.name]" }
    }
}
foreach n $_nets { if {[dbGet -p top.nets.name $n] == 0} { error "LEGAL FAIL: no net $n" } }
foreach n $_nets { editDelete -net $n }
deselectAll
foreach n $_nets { selectNet $n }
setNanoRouteMode -routeSelectedNetOnly true
routeDesign
setNanoRouteMode -routeSelectedNetOnly false
deselectAll
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_reroute.rpt]
pnr_note "LEGAL after reroute: verify_drc = [llength [dbGet -e top.markers]]"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt legalize hold_after_reroute.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_reroute.rpt]}
saveDesign [pnr_ckpt 05_legal_reroute.enc]
pnr_note "LEGAL REROUTE DONE"
