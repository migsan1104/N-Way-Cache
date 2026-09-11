# pg_eastnorth_eco.tcl (2026-09-10): EM ECO #2 on top of 05_clkskew8 (pass-3 Voltus,
# voltus_em_lef_clkskew8). pg_westvia_eco.tcl fixed only the WEST edge; the same
# single-cut construction exists on the EAST edge (VDD strap x last met4 stripe at
# x=2869.24: 3 via4 at 1.03x; VSS strap -> 2 um met4 jumper under the VDD ring at
# x=2882.59: 36 via4 up to 3.31x; VSS ring -> jumper at x=2893.74: 21 via4) and on
# the NORTH edge (every VSS vertical met4 stripe ends at y=2882.46 under a 2 um
# vertical met5 jumper that starts at y=2880.46 -> 2x2 um overlap = 1 cut, 15 via4
# up to 1.8x at y=2881.46). The WEST VSS jumper->strap crossing kept 39 via4 at up
# to 1.43x (x=17.65): re-padded here with a taller pad (more via rows).
# Same recipe as pg_westvia_eco.tcl: pads grown away from the partner net, delete +
# re-add met4-met5 via arrays, verifyConnectivity, DRC, v7 reroute loop, antenna,
# timing; save ASIC_ECO_DST only when DRC = 0 and antenna = 0.
# Knobs: ASIC_ECO_SRC (05_clkskew8.enc) ASIC_ECO_DST (05_pgvia9.enc) ASIC_ECO_PASSES (4)
#        ASIC_ECO_WIN (6.0) ASIC_ECO_PAD (5.0) ASIC_ECO_XEXT (1.2) ASIC_ECO_WPAD (8.0, 0 = skip west)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 05_clkskew8.enc]
set _dst [config_env ASIC_ECO_DST 05_pgvia9.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
set _win [config_env ASIC_ECO_WIN 6.0]
set PAD  [config_env ASIC_ECO_PAD 5.0]
set XEXT [config_env ASIC_ECO_XEXT 1.2]
set WPAD [config_env ASIC_ECO_WPAD 8.0]
set RPT pg_eastnorth
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt $RPT io_vclk.txt]]
set io_vclk_applied 0
if {[catch {source [file join [file dirname [info script]] io_vclk.tcl]} _m]} { puts "PGENV io_vclk failed: $_m" }
set fh [open [pnr_rpt $RPT pg_eastnorth.txt] w]
proc lq {msg} { global fh; puts $fh "PGENV $msg"; flush $fh; puts "PGENV $msg" }
lq "src=$_src dst=$_dst pad=$PAD xext=$XEXT wpad=$WPAD"

# ---- 1. geometry from the database ------------------------------------------
lassign [lindex [dbGet top.fPlan.box] 0] dx1 dy1 dx2 dy2
set midx [expr {($dx1 + $dx2) / 2.0}]; set midy [expr {($dy1 + $dy2) / 2.0}]
set DW [expr {$dx2 - $dx1}]; set DH [expr {$dy2 - $dy1}]
array set G {}
foreach net {VDD VSS} {
    set n [dbGet -p top.nets.name $net]
    set straps {}; set vstripes {}; set ringL ""; set ringR ""; set ringT ""
    foreach w [dbGet $n.sWires] {
        set lay [dbGet $w.layer.name]
        lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
        set wd [expr {$x2 - $x1}]; set ht [expr {$y2 - $y1}]
        if {$lay eq "met5" && $wd > $DW * 0.5 && $ht < 3.0} { lappend straps [list $x1 $y1 $x2 $y2] }
        if {$lay eq "met5" && $ht > $DH * 0.5 && $x1 < $midx} { set ringL [list $x1 $x2] }
        if {$lay eq "met5" && $ht > $DH * 0.5 && $x1 > $midx} { set ringR [list $x1 $x2] }
        if {$lay eq "met4" && $wd > $DW * 0.5 && $y1 > $midy} { set ringT [list $y1 $y2] }
        # vertical met4 stripes: any segment (they are broken around the macros); keyed by x
        if {$lay eq "met4" && $ht > $wd && $wd < 3.0 && $ht > 5.0} { lappend vstripes [list $x1 $y1 $x2 $y2] }
    }
    set G($net,straps) [lsort -real -index 1 $straps]
    set G($net,vstripes) $vstripes; set G($net,ringL) $ringL; set G($net,ringR) $ringR; set G($net,ringT) $ringT
    # first (west) and last (east) vertical stripe x
    set xs {}; foreach v $vstripes { lappend xs [lindex $v 0] }
    set xs [lsort -real -unique $xs]
    set G($net,xs) $xs
    set G($net,vwest) ""; set G($net,veast) ""
    if {[llength $xs]} {
        set xw [lindex $xs 0]; set xe [lindex $xs end]
        foreach v $vstripes { if {[lindex $v 0] == $xw} { set G($net,vwest) [list $xw [lindex $v 2]] }; if {[lindex $v 0] == $xe} { set G($net,veast) [list $xe [lindex $v 2]] } }
    }
    lq "$net: [llength $straps] straps, vstripe x count [llength $xs] (west $G($net,vwest) east $G($net,veast)), met5 rings L=$ringL R=$ringR, met4 top ring y=$ringT"
}
if {$G(VDD,veast) eq "" || $G(VSS,veast) eq "" || $G(VSS,ringR) eq "" || $G(VDD,ringR) eq "" || ![llength $G(VDD,straps)] || ![llength $G(VSS,straps)]} { lq "ABORT: east geometry not found"; close $fh; exit 3 }
proc partner_dir {y otherstraps} {
    set best 1e9; set dir 1
    foreach s $otherstraps { set yc [expr {([lindex $s 1] + [lindex $s 3]) / 2.0}]
        if {abs($yc - $y) < $best} { set best [expr {abs($yc - $y)}]; set dir [expr {$yc > $y ? -1 : 1}] } }
    return $dir   ;# +1 = grow up, -1 = grow down
}
proc partner_dir_x {x otherxs} {
    set best 1e9; set dir 1
    foreach ox $otherxs { if {abs($ox - $x) < $best} { set best [expr {abs($ox - $x)}]; set dir [expr {$ox > $x ? -1 : 1}] } }
    return $dir   ;# +1 = grow right (+x), -1 = grow left
}

# ---- 2. pads ------------------------------------------------------------------
setAddStripeMode -ignore_DRC true
proc pad {net layer box} {
    lassign $box x1 y1 x2 y2
    set dir [expr {($x2 - $x1) >= ($y2 - $y1) ? "horizontal" : "vertical"}]
    set w [expr {$dir eq "horizontal" ? $y2 - $y1 : $x2 - $x1}]
    setAddStripeMode -stacked_via_top_layer $layer -stacked_via_bottom_layer $layer
    if {[catch {addStripe -nets $net -layer $layer -direction $dir -width $w -area $box \
            -start_from [expr {$dir eq "horizontal" ? "bottom" : "left"}] -start_offset 0 -number_of_sets 1 -set_to_set_distance 10000} m]} {
        return "FAIL $m" }
    return ok
}
set viaboxes {}; set npad 0; set nfail 0
proc addpad {net lay box} { global npad nfail; set r [pad $net $lay $box]; if {$r eq "ok"} { incr npad } else { incr nfail; lq "pad $net $lay $box: $r" } }
proc vb {net box} { global viaboxes; lassign $box x1 y1 x2 y2; lappend viaboxes [list $net [list [expr {$x1-0.3}] [expr {$y1-0.3}] [expr {$x2+0.3}] [expr {$y2+0.3}]]] }

# (A) EAST edge, per strap: strap x own last stripe; VSS: ring -> jumper -> strap
foreach net {VDD VSS} {
    set other [expr {$net eq "VDD" ? "VSS" : "VDD"}]
    lassign $G($net,veast) vx1 vx2
    set cnt 0
    foreach s $G($net,straps) {
        lassign $s sx1 sy1 sx2 sy2
        set yc [expr {($sy1 + $sy2) / 2.0}]
        set dir [partner_dir $yc $G($other,straps)]
        if {$dir > 0} { set py1 $sy1; set py2 [expr {$sy1 + $PAD}] } else { set py1 [expr {$sy2 - $PAD}]; set py2 $sy2 }
        set bx1 [expr {$vx1 - $XEXT}]; set bx2 [expr {$vx2 + $XEXT}]
        addpad $net met5 [list $bx1 $py1 $bx2 $py2]; addpad $net met4 [list $bx1 $py1 $bx2 $py2]
        vb $net [list $bx1 $py1 $bx2 $py2]
        if {$net eq "VSS"} {
            lassign $G(VSS,ringR) rx1 rx2
            lassign $G(VDD,veast) ox1 ox2
            lassign $G(VDD,ringR) vr1 vr2
            set jx1 [expr {$ox2 + 0.8}]            ;# jumper starts just east of the VDD stripe
            addpad VSS met4 [list $jx1 $py1 $rx2 $py2]               ;# widened jumper, VDD stripe -> VSS ring
            set px2 [expr {$vr1 - 1.7}]                                ;# met5 pad stops clear of the VDD met5 ring
            if {$px2 > $sx2} { set px2 $sx2 }
            addpad VSS met5 [list $jx1 $py1 $px2 $py2]
            vb VSS [list $jx1 $py1 $px2 $py2]
            vb VSS [list $rx1 $py1 $rx2 $py2]
        }
        incr cnt
    }
    lq "east $net: $cnt straps padded"
}
# (B) NORTH edge, VSS: every vertical met4 stripe end under its met5 jumper
set nnorth 0
if {$G(VSS,ringT) ne ""} {
    lassign $G(VSS,ringT) ty1 ty2
    foreach x $G(VSS,xs) {
        # top end of this stripe column
        set top -1; set sw 2.0
        foreach v $G(VSS,vstripes) { if {[lindex $v 0] == $x && [lindex $v 3] > $top} { set top [lindex $v 3]; set sw [expr {[lindex $v 2] - [lindex $v 0]}] } }
        if {$top < $midy} { continue }
        set dir [partner_dir_x $x $G(VDD,xs)]
        if {$dir > 0} { set px1 $x; set px2 [expr {$x + $PAD}] } else { set px1 [expr {$x + $sw - $PAD}]; set px2 [expr {$x + $sw}] }
        set box [list $px1 [expr {$top - $PAD}] $px2 $top]
        addpad VSS met4 $box; addpad VSS met5 $box
        vb VSS $box
        incr nnorth
    }
}
lq "north VSS: $nnorth stripe ends padded"
# (C) WEST VSS re-pad, taller (WPAD) jumper + met5 pad, same construction as pg_westvia
set nwest 0
if {$WPAD > 0 && $G(VSS,ringL) ne "" && $G(VDD,vwest) ne ""} {
    lassign $G(VSS,ringL) rx1 rx2
    lassign $G(VDD,vwest) ox1 ox2
    lassign $G(VDD,ringL) vr1 vr2
    set jx2 [expr {$ox1 - 0.8}]
    foreach s $G(VSS,straps) {
        lassign $s sx1 sy1 sx2 sy2
        set yc [expr {($sy1 + $sy2) / 2.0}]
        set dir [partner_dir $yc $G(VDD,straps)]
        if {$dir > 0} { set py1 $sy1; set py2 [expr {$sy1 + $WPAD}] } else { set py1 [expr {$sy2 - $WPAD}]; set py2 $sy2 }
        addpad VSS met4 [list $rx1 $py1 $jx2 $py2]
        set px1 [expr {$vr2 + 1.7}]; if {$px1 < $sx1} { set px1 $sx1 }
        addpad VSS met5 [list $px1 $py1 $jx2 $py2]
        vb VSS [list $px1 $py1 $jx2 $py2]
        vb VSS [list $rx1 $py1 $rx2 $py2]
        incr nwest
    }
}
lq "west VSS re-pad: $nwest straps"
setAddStripeMode -ignore_DRC false
setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met1
lq "pads added: $npad, failed: $nfail, via boxes: [llength $viaboxes]"

# ---- 3. via arrays ----------------------------------------------------------
set nv 0; set nvf 0
foreach vbx $viaboxes {
    lassign $vbx net box
    catch {editPowerVia -delete_vias 1 -nets $net -top_layer met5 -bottom_layer met4 -area $box}
    if {[catch {editPowerVia -add_vias 1 -nets $net -top_layer met5 -bottom_layer met4 -orthogonal_only false -area $box} m]} { incr nvf; if {$nvf <= 3} { lq "editPowerVia $net $box: $m" } } else { incr nv }
}
lq "via arrays regenerated: $nv (failed $nvf)"
foreach net {VDD VSS} {
    foreach {tag test} [list west {$x2 <= 45} east {$x1 >= $dx2 - 45} north {$y2 >= $dy2 - 30}] {
        set cuts 0; set nvia 0
        if {[catch {
            foreach v [dbGet -e [dbGet -p top.nets.name $net].sVias] {
                lassign [lindex [dbGet $v.box] 0] x1 y1 x2 y2
                if {![expr $test]} { continue }
                if {[dbGet $v.via.cutLayer.name] ne "via4"} { continue }
                incr nvia; incr cuts [llength [dbGet $v.via.cutRects]] }
        } m]} { lq "cut audit $tag skipped: $m" }
        lq "$net $tag via4 stacks: $nvia, cuts: $cuts"
    }
}
foreach net {VDD VSS} { catch {verifyConnectivity -type special -net $net -noAntenna -error 5000 -warning 50 -report [pnr_rpt $RPT conn_$net.rpt]} }

# ---- 4. DRC + reroute loop (vss_jumper_eco7 recipe) --------------------------
proc nets_from_drc {rpt} {
    set out {}; if {![file readable $rpt]} { return $out }
    set f [open $rpt r]
    while {[gets $f l] >= 0} { foreach {_ n} [regexp -all -inline {Wire of Net (\S+)} $l] { if {$n ne "VDD" && $n ne "VSS"} { lappend out $n } } }
    close $f; return $out
}
proc antenna_count {rpt} {
    set f [open $rpt r]; set t [read $f]; close $f
    if {[regexp {No Violations Found} $t]} { return 0 }
    if {[regexp {Total number of process antenna violations:\s*(\d+)} $t -> a]} { return $a }
    if {[regexp {Verification Complete\s*:\s*(\d+)} $t -> a]} { return $a }
    return -1
}
clearDrc
set drc_rpt [pnr_rpt $RPT drc_pass0.rpt]
verify_drc -limit 100000 -report $drc_rpt
set d [llength [dbGet -e top.markers]]
lq "pass 0 (after pads+vias): verify_drc = $d"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false
setNanoRouteMode -drouteFixAntenna true -routeInsertAntennaDiode false
for {set pass 1} {$pass <= $_np} {incr pass} {
    set nets [lsort -u [nets_from_drc $drc_rpt]]
    if {![llength $nets] && $d == 0} { lq "pass $pass: nothing to reroute"; break }
    if {![llength $nets]} { lq "pass $pass: $d markers but no signal net named - stop"; break }
    lq "pass $pass: [llength $nets] nets"
    if {$pass >= 3} {
        set items {}; set cur ""
        set f [open $drc_rpt r]
        while {[gets $f l] >= 0} {
            if {[regexp {^([A-Z]+):(.*)$} $l -> t rest]} { set cur [list $t $rest] }
            if {[regexp {^Bounds\s*:\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)} $l -> x1 y1 x2 y2] && $cur ne ""} {
                lappend items [list [lindex $cur 0] [lindex $cur 1] $x1 $y1 $x2 $y2]; set cur "" } }
        close $f
        set nc 0
        foreach it $items { lassign $it t rest x1 y1 x2 y2
            if {[string match *Special* $rest]} { continue }
            editDelete -area [list [expr {$x1-$_win}] [expr {$y1-$_win}] [expr {$x2+$_win}] [expr {$y2+$_win}]] -type Signal; incr nc }
        lq "pass $pass: windowed rip-up on $nc markers"
    }
    foreach nn $nets { catch {editDelete -net $nn} }
    deselectAll
    if {$pass >= 3} {
        routeDesign
    } else {
        foreach nn $nets { catch {selectNet $nn} }
        setNanoRouteMode -routeSelectedNetOnly true
        routeDesign
        setNanoRouteMode -routeSelectedNetOnly false
    }
    deselectAll
    clearDrc
    set drc_rpt [pnr_rpt $RPT drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    lq "pass $pass: verify_drc = $d"
    if {$d == 0} { break }
}
set arpt [pnr_rpt $RPT antenna_final.rpt]
verifyProcessAntenna -report $arpt
set a [antenna_count $arpt]
catch {checkPlace [pnr_rpt $RPT checkplace_final.rpt]}
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt $RPT x]] -prefix final}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt $RPT x]] -prefix final}
} { catch {eval $_r} }
set s [get_property [report_timing -late  -max_paths 1 -collection] slack]
set h [get_property [report_timing -early -max_paths 1 -collection] slack]
lq "FINAL: verify_drc = $d, antenna = $a, setup WNS $s hold WNS $h"
if {$d == 0 && $a == 0} { saveDesign [pnr_ckpt $_dst]; lq "saved $_dst (clean)" } else { set dd [string map {.enc _dirty.enc} $_dst]; saveDesign [pnr_ckpt $dd]; lq "NOT CLEAN - saved $dd for inspection" }
close $fh
exit
