# pg_westvia_eco.tcl (2026-09-09): EM fix for the west-edge strap entries.
# Voltus on the iter26b export (voltus.md): IR passes (VDD 22 mV, VSS 25 mV vs
# 53 budget) but every horizontal met5 strap enters the grid through ONE via4
# cut: VDD strap x first vertical met4 stripe (x 21.1, 48 straps, 1.49x the
# LEF Jmax), VSS ring->jumper (x 6.1, 2 cuts), VSS jumper->strap (x 17.25,
# 1 cut, 3.95x), VSS strap->stripe (x 25.1, 1 cut). A 2 um strap over a 2 um
# stripe fits one 0.8 um cut - 19b lesson 3 ("EM violation by construction").
# Fix per strap: a ~5 um pad on the strap end (met5) and on the stripe under
# it (met4), grown AWAY from the partner strap (VDD/VSS straps are 4 um
# apart), the VSS jumper widened to 5 um and lengthened to just short of the
# VDD stripe, then editPowerVia delete+add met4-met5 over every crossing
# (-orthogonal_only false), verifyConnectivity, verify_drc, the v7 reroute
# loop for signal wires the pads collided with, antenna, timing. Saves
# ASIC_ECO_DST only when DRC = 0 and antenna = 0, else <dst>_dirty.
# Knobs: ASIC_ECO_SRC (05_antenna_final6.enc) ASIC_ECO_DST (05_pgvia7.enc)
#        ASIC_ECO_PASSES (4) ASIC_ECO_WIN (6.0) ASIC_ECO_PAD (5.0) ASIC_ECO_XEXT (1.2)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 05_antenna_final6.enc]
set _dst [config_env ASIC_ECO_DST 05_pgvia7.enc]
set _np  [config_env ASIC_ECO_PASSES 4]
set _win [config_env ASIC_ECO_WIN 6.0]
set PAD  [config_env ASIC_ECO_PAD 5.0]
set XEXT [config_env ASIC_ECO_XEXT 1.2]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt pg_westvia io_vclk.txt]]
set io_vclk_applied 0
if {[catch {source [file join [file dirname [info script]] io_vclk.tcl]} _m]} { puts "PGVIA io_vclk failed: $_m" }
set fh [open [pnr_rpt pg_westvia pg_westvia.txt] w]
proc lq {msg} { global fh; puts $fh "PGVIA $msg"; flush $fh; puts "PGVIA $msg" }
lq "src=$_src dst=$_dst pad=$PAD xext=$XEXT"

# ---- 1. geometry from the database ------------------------------------------
lassign [lindex [dbGet top.fPlan.box] 0] dx1 dy1 dx2 dy2
set midx [expr {($dx1 + $dx2) / 2.0}]
array set G {}
foreach net {VDD VSS} {
    set n [dbGet -p top.nets.name $net]
    set straps {}; set vstripe ""; set ringL ""; set jumpers {}
    foreach w [dbGet $n.sWires] {
        set lay [dbGet $w.layer.name]
        lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
        set wd [expr {$x2 - $x1}]; set ht [expr {$y2 - $y1}]
        if {$lay eq "met5" && $wd > ($dx2 - $dx1) * 0.5} { lappend straps [list $x1 $y1 $x2 $y2] }
        if {$lay eq "met5" && $ht > ($dy2 - $dy1) * 0.5 && $x1 < $midx} { set ringL [list $x1 $x2] }
        if {$lay eq "met4" && $ht > ($dy2 - $dy1) * 0.5 && $x2 < 45} {
            if {$vstripe eq "" || $x1 < [lindex $vstripe 0]} { set vstripe [list $x1 $x2] }
        }
        if {$lay eq "met4" && $wd > $ht && $x1 < 10 && $wd < 30} { lappend jumpers [list $x1 $y1 $x2 $y2] }
    }
    set G($net,straps) [lsort -real -index 1 $straps]
    set G($net,vstripe) $vstripe; set G($net,ringL) $ringL; set G($net,jumpers) $jumpers
    lq "$net: [llength $straps] straps, first met4 vstripe x=$vstripe, west met5 ring x=$ringL, west jumpers=[llength $jumpers]"
}
if {$G(VDD,vstripe) eq "" || $G(VSS,vstripe) eq "" || ![llength $G(VDD,straps)] || ![llength $G(VSS,straps)]} { lq "ABORT: geometry not found"; close $fh; exit 3 }
# partner direction: for each strap, is the other net's nearest strap above or below?
proc partner_dir {y otherstraps} {
    set best 1e9; set dir 1
    foreach s $otherstraps { set yc [expr {([lindex $s 1] + [lindex $s 3]) / 2.0}]
        if {abs($yc - $y) < $best} { set best [expr {abs($yc - $y)}]; set dir [expr {$yc > $y ? -1 : 1}] } }
    return $dir   ;# +1 = grow up, -1 = grow down
}

# ---- 2. pads and jumper widening --------------------------------------------
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
foreach net {VDD VSS} {
    set other [expr {$net eq "VDD" ? "VSS" : "VDD"}]
    lassign $G($net,vstripe) vx1 vx2
    foreach s $G($net,straps) {
        lassign $s sx1 sy1 sx2 sy2
        set yc [expr {($sy1 + $sy2) / 2.0}]; set sw [expr {$sy2 - $sy1}]
        set dir [partner_dir $yc $G($other,straps)]
        if {$dir > 0} { set py1 $sy1; set py2 [expr {$sy1 + $PAD}] } else { set py1 [expr {$sy2 - $PAD}]; set py2 $sy2 }
        # (a) strap x own vertical stripe: met5 pad + met4 pad, square-ish
        set bx1 [expr {$vx1 - $XEXT}]; set bx2 [expr {$vx2 + $XEXT}]
        foreach {lay box} [list met5 [list $bx1 $py1 $bx2 $py2] met4 [list $bx1 $py1 $bx2 $py2]] {
            set r [pad $net $lay $box]; if {$r eq "ok"} { incr npad } else { incr nfail; lq "pad $net $lay $box: $r" }
        }
        lappend viaboxes [list $net [list [expr {$bx1 - 0.3}] [expr {$py1 - 0.3}] [expr {$bx2 + 0.3}] [expr {$py2 + 0.3}]]]
        # (b) VSS only: ring -> jumper -> strap. Widen the jumper to PAD, run it from
        #     the ring to just short of the VDD stripe; met5 pad on the strap start.
        if {$net eq "VSS" && $G(VSS,ringL) ne ""} {
            lassign $G(VSS,ringL) rx1 rx2
            lassign $G(VDD,vstripe) ox1 ox2
            set jx2 [expr {$ox1 - 0.8}]
            set jbox [list $rx1 $py1 $jx2 $py2]
            set r [pad VSS met4 $jbox]; if {$r eq "ok"} { incr npad } else { incr nfail; lq "jumper VSS $jbox: $r" }
            # met5 pad over the jumper end, clear of the VDD met5 ring
            set vddring $G(VDD,ringL)
            set px1 [expr {$vddring ne "" ? [lindex $vddring 1] + 1.7 : $sx1}]
            if {$px1 < $sx1} { set px1 $sx1 }
            set pbox [list $px1 $py1 $jx2 $py2]
            set r [pad VSS met5 $pbox]; if {$r eq "ok"} { incr npad } else { incr nfail; lq "strap pad VSS $pbox: $r" }
            lappend viaboxes [list VSS [list [expr {$px1 - 0.3}] [expr {$py1 - 0.3}] [expr {$jx2 + 0.3}] [expr {$py2 + 0.3}]]]
            lappend viaboxes [list VSS [list [expr {$rx1 - 0.3}] [expr {$py1 - 0.3}] [expr {$rx2 + 0.3}] [expr {$py2 + 0.3}]]]
        }
    }
}
setAddStripeMode -ignore_DRC false
setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met1
lq "pads added: $npad, failed: $nfail, via boxes: [llength $viaboxes]"

# ---- 3. via arrays ----------------------------------------------------------
set nv 0; set nvf 0
foreach vb $viaboxes {
    lassign $vb net box
    catch {editPowerVia -delete_vias 1 -nets $net -top_layer met5 -bottom_layer met4 -area $box}
    if {[catch {editPowerVia -add_vias 1 -nets $net -top_layer met5 -bottom_layer met4 -orthogonal_only false -area $box} m]} { incr nvf; if {$nvf <= 3} { lq "editPowerVia $net $box: $m" } } else { incr nv }
}
lq "via arrays regenerated: $nv (failed $nvf)"
# cut audit: count via4 cuts on each net inside x < 45 (dbGet on special vias)
foreach net {VDD VSS} {
    set cuts 0; set nvia 0
    if {[catch {
        foreach v [dbGet -e [dbGet -p top.nets.name $net].sVias] {
            lassign [lindex [dbGet $v.box] 0] x1 y1 x2 y2
            if {$x2 > 45} { continue }
            if {[dbGet $v.via.cutLayer.name] ne "via4"} { continue }
            incr nvia; incr cuts [llength [dbGet $v.via.cutRects]] }
    } m]} { lq "cut audit skipped: $m" }
    lq "$net west via4 stacks: $nvia, cuts: $cuts"
}
foreach net {VDD VSS} { catch {verifyConnectivity -type special -net $net -noAntenna -error 5000 -warning 50 -report [pnr_rpt pg_westvia conn_$net.rpt]} }

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
set drc_rpt [pnr_rpt pg_westvia drc_pass0.rpt]
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
    set drc_rpt [pnr_rpt pg_westvia drc_pass$pass.rpt]
    verify_drc -limit 100000 -report $drc_rpt
    set d [llength [dbGet -e top.markers]]
    lq "pass $pass: verify_drc = $d"
    if {$d == 0} { break }
}
set arpt [pnr_rpt pg_westvia antenna_final.rpt]
verifyProcessAntenna -report $arpt
set a [antenna_count $arpt]
catch {checkPlace [pnr_rpt pg_westvia checkplace_final.rpt]}
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt pg_westvia x]] -prefix final}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt pg_westvia x]] -prefix final}
} { catch {eval $_r} }
set s [get_property [report_timing -late  -max_paths 1 -collection] slack]
set h [get_property [report_timing -early -max_paths 1 -collection] slack]
lq "FINAL: verify_drc = $d, antenna = $a, setup WNS $s hold WNS $h"
if {$d == 0 && $a == 0} { saveDesign [pnr_ckpt $_dst]; lq "saved $_dst (clean)" } else { set dd [string map {.enc _dirty.enc} $_dst]; saveDesign [pnr_ckpt $dd]; lq "NOT CLEAN - saved $dd for inspection" }
close $fh
exit
