# legalize_fixup.tcl - 2026-09-06 (iter19b, 8 left after legalize_targeted).
# Works from a verify_drc REPORT (no marker attributes needed):
#  * MINWIDTH / NSMETAL markers on special wires: delete the special-wire /
#    via fragments inside the marker box that are themselves small (the
#    met5 VDD strap stubs 1.5 x 2.6 um; the met4 VSS stub + via at (922,2860)
#    that iter16b removed by hand in fix3/fix8-10).
#  * every other marker: cut ALL signal wires in a small window around it
#    (editDelete -area), so the nets crossing that spot are re-routed
#    together, with met4 guidance blockages over the macros the report names.
# Then routeDesign (ECO of the opened nets, TD/SI/antenna off), verify, save
# 05_legal_fixup.enc. Knobs: ASIC_LEGALIZE_SRC, ASIC_LEGALIZE_DRC_RPT,
# ASIC_LEGALIZE_WIN (half-window in um around a signal marker, 6).
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_LEGALIZE_SRC 05_legal_targeted.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt legalize fixup.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
set _rpt [config_env ASIC_LEGALIZE_DRC_RPT [pnr_rpt legalize drc_after_eco1.rpt]]
set _win [config_env ASIC_LEGALIZE_WIN 6.0]
# parse: type line then Bounds line
set items {}; set macros {}; set cur ""
set f [open $_rpt r]
while {[gets $f l] >= 0} {
    if {[regexp {^([A-Z]+):(.*)$} $l -> t rest]} { set cur [list $t $rest]; foreach {- m} [regexp -all -inline {(?:Pin|Blockage) of Cell (\S+)} $rest] { lappend macros $m }; continue }
    if {[regexp {^Bounds\s*:\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)} $l -> x1 y1 x2 y2] && $cur ne ""} {
        lappend items [list [lindex $cur 0] [lindex $cur 1] $x1 $y1 $x2 $y2]; set cur ""
    }
}
close $f
set macros [lsort -u $macros]
lq "src=$_src report=$_rpt items=[llength $items] macros=[llength $macros]"
# ---- PG fragments
set _pg 0
foreach it $items {
    lassign $it t rest x1 y1 x2 y2
    if {![string match *Special* $rest]} { continue }
    set box [list [expr {$x1-0.3}] [expr {$y1-0.3}] [expr {$x2+0.3}] [expr {$y2+0.3}]]
    foreach o [dbQuery -area $box -objType {sWire sVia}] {
        catch {
            lassign [lindex [dbGet $o.box] 0] a1 b1 a2 b2
            set w [expr {$a2-$a1}]; set h [expr {$b2-$b1}]
            set ot [dbGet $o.objType]
            set small [expr {($w <= 4.0 && $h <= 4.0) || ($t eq "NSMETAL" && $w <= 4.0 && $h <= 30.0 && [string match *Via* $ot] == 0)}]
            if {[string match *Via* $ot] || $small} {
                lq "PG delete $ot net=[dbGet -e $o.net.name] layer=[dbGet -e $o.layer.name] box=[dbGet $o.box] (marker $t at $x1 $y1)"
                dbDeleteObj $o; incr _pg
            } else { lq "PG keep $ot net=[dbGet -e $o.net.name] box=[dbGet $o.box] (too big; marker $t at $x1 $y1)" }
        }
    }
}
lq "PG fragments deleted: $_pg"
# ---- signal windows
deleteRouteBlk -all
foreach m $macros {
    set p [dbGet -p top.insts.name $m]
    if {$p == 0} { continue }
    lassign [lindex [dbGet $p.box] 0] x1 y1 x2 y2
    createRouteBlk -name g_m4_[string map {[ _ ] _ . _} $m] -box [list [expr {$x1+1.5}] [expr {$y1+2.0}] [expr {$x2-1.5}] [expr {$y2-2.0}]] -layer {met4} -exceptpgnet
}
lq "guidance rBlkgs=[llength [dbGet -e top.fplan.rBlkgs]]"
set _cut 0
foreach it $items {
    lassign $it t rest x1 y1 x2 y2
    if {[string match *Special* $rest]} { continue }
    set box [list [expr {$x1-$_win}] [expr {$y1-$_win}] [expr {$x2+$_win}] [expr {$y2+$_win}]]
    lq "cut signal wires in $box ($t)"
    editDelete -area $box -type Signal
    incr _cut
}
if {$_cut} {
    setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false -drouteFixAntenna false
    setNanoRouteMode -drouteEndIteration 40
    routeDesign
}
deleteRouteBlk -all
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_fixup.rpt]
set n [llength [dbGet -e top.markers]]
lq "after fixup (pg=$_pg, windows=$_cut): verify_drc = $n"
saveDesign [pnr_ckpt 05_legal_fixup.enc]
lq "LEGAL FINAL verify_drc = $n (fixup)"
close $fh
exit 0
