# legalize_fix8.tcl - 2026-09-03 iter16b, after fix7 (verify_drc = 1: NSMet
# on VSS, a M3M4 via at the bottom end of a 22 um met4 stub, (922, 2860),
# whose met4 enclosure hangs past the stub end). Replace the via with
# editPowerVia in the stub/strap overlap so it is fully enclosed, then check
# special-net connectivity and re-verify. Runs on the fix7 database in-session.
set fh [open [pnr_rpt legalize fix8.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
lq "start markers=[llength [dbGet -e top.markers]]"
foreach o [dbQuery -area {919 2858 924 2863} -objType {sWire sVia wire via}] {
    catch { lq "before obj=[dbGet $o.objType] layer=[dbGet -e $o.layer.name] net=[dbGet -e $o.net.name] box=[dbGet -e $o.box] via=[dbGet -e $o.via.name] pt=[dbGet -e $o.pt]" }
}
editPowerVia -delete_vias true -area {921.0 2859.3 923.0 2861.0} -top_layer met4 -bottom_layer met3
lq "after delete: markers unchanged, objects:"
foreach o [dbQuery -area {919 2858 924 2863} -objType {sWire sVia wire via}] {
    catch { lq "  obj=[dbGet $o.objType] layer=[dbGet -e $o.layer.name] net=[dbGet -e $o.net.name] box=[dbGet -e $o.box] via=[dbGet -e $o.via.name] pt=[dbGet -e $o.pt]" }
}
editPowerVia -add_vias true -area {920.1 2860.5 922.1 2866.0} -top_layer met4 -bottom_layer met3 -nets VSS
foreach o [dbQuery -area {919 2858 924 2867} -objType {sVia via}] {
    catch { lq "after add obj=[dbGet $o.objType] net=[dbGet -e $o.net.name] via=[dbGet -e $o.via.name] pt=[dbGet -e $o.pt]" }
}
catch { verifyConnectivity -type special -net VSS -noAntenna -noWeakConnect -report [pnr_rpt legalize vss_conn_fix8.rpt] } _m
lq "VSS special connectivity rc: $_m"
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix8.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fix8: verify_drc = $n"
pnr_note "LEGAL after fix8: verify_drc = $n"
saveDesign [pnr_ckpt 05_legal_fix8.enc]
lq "FIX8 DONE"; close $fh
pnr_note "LEGAL FIX8 DONE"
