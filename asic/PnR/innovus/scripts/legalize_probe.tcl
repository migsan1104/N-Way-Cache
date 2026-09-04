# legalize_probe.tcl - read-only geometry queries around iter16b's last markers
proc lq {msg} { puts "LEGALQ $msg" }
lq "core=[dbGet top.fplan.coreBox] die=[dbGet top.fplan.box]"
foreach l {met3 met4 met5} { set p [dbGet -p head.layers.name $l]; lq "layer $l dir=[dbGet $p.direction] pitchX=[dbGet $p.pitchX] pitchY=[dbGet $p.pitchY] minW=[dbGet $p.minWidth] minSp=[dbGet $p.minSpacing]" }
foreach n {FE_OCPN359581_FE_OFN12056_GEN_WAYS_0__FLAG_TAG_DATA_ARRAY_refill_set_idx_r_7 FE_OCPN437583_n FE_OFN321786_n_244585 FE_OFN770657_n_259144 FE_OFN638137_n_243696} {
    set np [dbGet -p top.nets.name $n]
    lq "net $n terms=[dbGet $np.numTerms]"
    foreach t [dbGet $np.instTerms] {
        set c [dbGet $t.inst.cell.name]
        if {[string match *sram* $c]} { lq "  macro term [dbGet $t.name] pt=[dbGet $t.pt] layers=[lsort -u [dbGet -e $t.cellTerm.pins.allShapes.layer.name]] shapes=[dbGet -e $t.cellTerm.pins.allShapes.shapes.rect]" }
    }
}
foreach b {{1550 455 1610 492} {1970 455 2020 492} {2640 2195 2660 2210}} {
    lq "== area $b"
    foreach o [dbQuery -area $b -objType {sWire}] { catch { lq "  sWire [dbGet $o.layer.name] [dbGet $o.net.name] [dbGet $o.box]" } }
    foreach o [dbQuery -area $b -objType {inst}] { catch { if {[string match *sram* [dbGet $o.cell.name]]} { lq "  macro [dbGet $o.name] box=[dbGet $o.box]" } } }
    lq "  routeBlks=[llength [dbQuery -area $b -objType routeBlk]] wires=[llength [dbQuery -area $b -objType wire]]"
}
foreach o [dbQuery -area {921.5 2859.5 922.5 2860.5} -objType {sVia}] { catch { lq "nsmet via [dbGet $o.via.name] pt=[dbGet $o.pt] net=[dbGet $o.net.name] layers=[dbGet -e $o.via.botLayer.name]/[dbGet -e $o.via.topLayer.name]" } }
foreach o [dbQuery -area {915 2850 930 2890} -objType {sWire}] { catch { lq "nsmet swire [dbGet $o.layer.name] [dbGet $o.net.name] [dbGet $o.box]" } }
lq "PROBE DONE"
