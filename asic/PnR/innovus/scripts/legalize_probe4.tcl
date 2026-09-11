set fh [open [pnr_rpt legalize probe4.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh }
foreach o [dbQuery -area {900 2850 945 2900} -objType {sWire}] { catch { if {[dbGet $o.net.name] in {VSS VDD}} { lq "swire [dbGet $o.layer.name] [dbGet $o.net.name] [dbGet $o.box] shape=[dbGet -e $o.shape]" } } }
foreach o [dbQuery -area {900 2850 945 2900} -objType {sVia}] { catch { lq "svia [dbGet $o.net.name] [dbGet $o.via.name] pt=[dbGet $o.pt]" } }
lq "all sVias in design: [llength [dbGet -e top.sVias]] ; sWires: [llength [dbGet -e top.sWires]]"
lq "markers: [llength [dbGet -e top.markers]] type=[dbGet -e top.markers.subType] box=[dbGet -e top.markers.box]"
lq "PROBE4 DONE"; close $fh
