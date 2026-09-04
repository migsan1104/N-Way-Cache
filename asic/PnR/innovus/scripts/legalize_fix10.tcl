# legalize_fix10.tcl - fix9 left the old stub in place (editDelete -area did
# not remove a FIXED special wire) and added a second one on top. Delete
# the old {920.1 2859.97 922.1 2882.46} stub by object, keep the new one.
set fh [open [pnr_rpt legalize fix10.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
set _del 0
foreach o [dbQuery -area {919 2858 923 2896} -objType {sWire}] {
    catch { if {[dbGet $o.net.name] eq "VSS" && [dbGet $o.layer.name] eq "met4" && [lindex [dbGet $o.box] 0 1] < 2860.5} { lq "delete swire [dbGet $o.box]"; dbDeleteObj $o; incr _del } }
}
lq "deleted=$_del"
foreach o [dbQuery -area {919 2858 923 2896} -objType {sWire}] { catch { if {[dbGet $o.net.name] eq "VSS" && [dbGet $o.layer.name] eq "met4"} { lq "left swire [dbGet $o.box]" } } }
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fix10.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fix10: verify_drc = $n"
pnr_note "LEGAL after fix10: verify_drc = $n"
saveDesign [pnr_ckpt 05_legal_fix10.enc]
lq "FIX10 DONE"; close $fh
pnr_note "LEGAL FIX10 DONE"
