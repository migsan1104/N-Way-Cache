# legalize_fix9.tcl - 2026-09-03 iter16b (fix7/fix8 db, verify_drc = 1).
# The NSMet is the bare bottom end of the VSS met4 stripe stub
# {920.1 2859.97 922.1 2882.46} (no via there; its vias are at y 2869/2874/
# 2880 to the followpins and 2881.46 to met5). Delete the stub, redraw it
# from y 2861 up to the ring at 2883, regenerate its vias, verify.
set fh [open [pnr_rpt legalize fix9.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
proc dump {tag} {
    foreach o [dbQuery -area {919 2858 923 2896} -objType {sWire}] { catch { if {[dbGet $o.net.name] eq "VSS"} { lq "$tag swire [dbGet $o.layer.name] [dbGet $o.box] shape=[dbGet -e $o.shape]" } } }
    foreach o [dbQuery -area {919 2858 923 2896} -objType {sVia}] { catch { if {[dbGet $o.net.name] eq "VSS"} { lq "$tag svia [dbGet $o.via.name] pt=[dbGet $o.pt]" } } }
}
dump before
editDelete -area {920.0 2859.9 922.2 2860.5} -net VSS -type Special -layer met4
dump after_delete
setEdit -nets VSS -type Special -shape STRIPE -layer_vertical met4 -width_vertical 2.0 -status FIXED
editAddRoute 921.1 2861.0
editCommitRoute 921.1 2883.0
dump after_add
editPowerVia -add_vias true -area {919.0 2860.5 923.2 2896.0} -top_layer met5 -bottom_layer met1 -nets VSS
dump after_vias
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix9.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fix9: verify_drc = $n"
pnr_note "LEGAL after fix9: verify_drc = $n"
saveDesign [pnr_ckpt 05_legal_fix9.enc]
lq "FIX9 DONE"; close $fh
pnr_note "LEGAL FIX9 DONE"
