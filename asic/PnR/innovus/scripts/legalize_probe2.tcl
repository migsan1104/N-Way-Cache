# legalize_probe2.tcl - how much signal routing crosses the SRAM macros, per layer
proc lq {msg} { puts "LEGALQ $msg" }
foreach a {rBlkgs routeBlkgs} { catch { lq "$a total=[llength [dbGet -e top.fplan.$a]] layers=[lsort -u [dbGet -e top.fplan.$a.layers.name]]" } }
lq "pBlkgs=[llength [dbGet -e top.fplan.pBlkgs]] halos=[llength [dbGet -e top.fplan.halos]]"
foreach m [dbGet -p2 top.insts.cell.name *sram*] {
    set b [dbGet $m.box]
    lassign $b x1 y1 x2 y2
    set in [list [expr {$x1+3}] [expr {$y1+3}] [expr {$x2-3}] [expr {$y2-3}]]
    array unset c; array set c {met1 0 met2 0 met3 0 met4 0 met5 0}
    set other 0
    foreach w [dbQuery -area $in -objType wire] {
        set l [dbGet $w.layer.name]
        if {[info exists c($l)]} { incr c($l) } else { incr other }
    }
    lq "macro [dbGet $m.name] box=$b wires: m1=$c(met1) m2=$c(met2) m3=$c(met3) m4=$c(met4) m5=$c(met5)"
}
lq "PROBE2 DONE"
