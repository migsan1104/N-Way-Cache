# legalize_probe3.tcl - read-only; writes to reports/legalize/probe3.txt
set fh [open [pnr_rpt legalize probe3.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh }
foreach m [dbGet -p2 top.insts.cell.name *sram*] {
    lassign [lindex [dbGet $m.box] 0] x1 y1 x2 y2
    set in [list [expr {$x1+3}] [expr {$y1+3}] [expr {$x2-3}] [expr {$y2-3}]]
    unset -nocomplain cnt; array set cnt {met1 0 met2 0 met3 0 met4 0 met5 0}
    set nets {}
    foreach w [dbQuery -area $in -objType wire] { set l [dbGet $w.layer.name]; if {[info exists cnt($l)]} { incr cnt($l); if {$l ne "met5" && $l ne "met4"} { lappend nets [dbGet $w.net.name] } } }
    lq "census [dbGet $m.name] box=[dbGet $m.box] m1=$cnt(met1) m2=$cnt(met2) m3=$cnt(met3) m4=$cnt(met4) m5=$cnt(met5) nets_m123=[llength [lsort -u $nets]]"
}
lq "rBlkgs=[llength [dbGet -e top.fplan.rBlkgs]] names=[dbGet -e top.fplan.rBlkgs.name]"
foreach n {FE_OFN16004_refill_line_56 FE_OFN360904_n FE_OFN321786_n_244585 FE_OFN638137_n_243696 FE_OFN333367_FE_OFN318246_FE_OFN241886_n_133541 FE_OFN314015_n_83884} {
    set np [dbGet -p top.nets.name $n]
    lq "net $n numTerms=[dbGet $np.numTerms] wires=[llength [dbGet -e $np.wires]] layers=[lsort -u [dbGet -e $np.wires.layer.name]] bbox=[dbGet -e $np.box]"
    foreach t [dbGet $np.instTerms] { lq "   term [dbGet $t.name] pt=[dbGet $t.pt] cell=[dbGet $t.inst.cell.name] isOut=[dbGet $t.isOutput]" }
    foreach t [dbGet -e $np.terms] { lq "   ioterm [dbGet $t.name] pt=[dbGet $t.pt]" }
}
foreach b {{921.5 2859.5 922.5 2860.5}} { foreach ot {sVia pWire} { catch { foreach o [dbQuery -area $b -objType $ot] { lq "nsmet $ot objType=[dbGet $o.objType] via=[dbGet -e $o.via.name] layer=[dbGet -e $o.layer.name] net=[dbGet -e $o.net.name] pt=[dbGet -e $o.pt] box=[dbGet -e $o.box]" } } } }
lq "PROBE3 DONE"; close $fh
puts "INFO: LEGAL PROBE3 DONE"
