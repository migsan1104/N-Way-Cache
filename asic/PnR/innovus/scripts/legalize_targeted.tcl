# legalize_targeted.tcl - 2026-09-06 (iter19 attempt 4). The iter16b fix3
# recipe, unattended: from the stage-05 route, put met4 guidance blockages
# over the macros named in the DRC report, rip up ONLY the signal nets that
# appear in the markers, reroute them alone (others fixed), then up to
# ASIC_LEGALIZE_ECO_PASSES targeted ecoRoute passes with a plateau guard,
# then the PG-stub cleanup. Saves 05_legal_targeted.enc (best state).
#   ASIC_LEGALIZE_SRC (05_route.enc)  ASIC_LEGALIZE_DRC_RPT (reports/route/drc.rpt)
#   ASIC_LEGALIZE_ECO_PASSES (4)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_LEGALIZE_SRC 05_route.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set fh [open [pnr_rpt legalize targeted.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
set _rpt [config_env ASIC_LEGALIZE_DRC_RPT [pnr_rpt route drc.rpt]]
# parse nets + macro instances out of the verify_drc report
set nets {}; set macros {}
set f [open $_rpt r]
while {[gets $f l] >= 0} {
    foreach {- n} [regexp -all -inline {Regular Wire of Net (\S+)} $l] { if {$n ni {VDD VSS}} { lappend nets $n } }
    foreach {- m} [regexp -all -inline {(?:Pin|Blockage) of Cell (\S+)} $l] { lappend macros $m }
}
close $f
set nets [lsort -u $nets]; set macros [lsort -u $macros]
set ok {}
foreach n $nets { if {[dbGet -p top.nets.name $n] != 0} { lappend ok $n } else { lq "no net $n (skipped)" } }
set nets $ok
lq "src=$_src markers_in_db=[llength [dbGet -e top.markers]] nets=[llength $nets] macros=[llength $macros]"
deleteRouteBlk -all
foreach m $macros {
    set p [dbGet -p top.insts.name $m]
    if {$p == 0} { continue }
    lassign [lindex [dbGet $p.box] 0] x1 y1 x2 y2
    createRouteBlk -name g_m4_[string map {[ _ ] _ . _} $m] -box [list [expr {$x1+1.5}] [expr {$y1+2.0}] [expr {$x2-1.5}] [expr {$y2-2.0}]] -layer {met4} -exceptpgnet
}
lq "guidance rBlkgs=[llength [dbGet -e top.fplan.rBlkgs]]"
setNanoRouteMode -routeWithTimingDriven false -routeWithSiDriven false -drouteFixAntenna false
setNanoRouteMode -drouteEndIteration 40
foreach n $nets { editDelete -net $n }
deselectAll
foreach n $nets { selectNet $n }
setNanoRouteMode -routeSelectedNetOnly true
routeDesign
setNanoRouteMode -routeSelectedNetOnly false
deselectAll
deleteRouteBlk -all
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_targeted.rpt]
set n [llength [dbGet -e top.markers]]
lq "after targeted reroute: verify_drc = $n"
set best $n
saveDesign [pnr_ckpt 05_legal_targeted.enc]
set passes [config_env ASIC_LEGALIZE_ECO_PASSES 4]
for {set p 1} {$p <= $passes} {incr p} {
    if {$n == 0} { break }
    if {[catch {ecoRoute -target} m]} { lq "ecoRoute -target failed: $m"; break }
    clearDrc
    verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_eco${p}.rpt]
    set n [llength [dbGet -e top.markers]]
    lq "after ecoRoute pass $p: verify_drc = $n"
    if {$n < $best} { set best $n; saveDesign [pnr_ckpt 05_legal_targeted.enc] } elseif {$n >= $best} { lq "plateau ($n >= $best)"; break }
}
# PG stubs (see legalize_route.tcl) on the best state
if {$n != $best} { freeDesign; pnr_restore_stage 05_legal_targeted.enc; clearDrc; verify_drc -limit 100000 -report [pnr_rpt legalize drc_best.rpt]; set n [llength [dbGet -e top.markers]] }
set _pg 0
if {[catch {
foreach mk [dbGet -e top.markers] {
    set sub [dbGet $mk.subType]
    if {![string match -nocase *width* $sub] && ![string match -nocase *nsmet* $sub] && ![string match -nocase *overlap* $sub]} { continue }
    lassign [lindex [dbGet $mk.box] 0] x1 y1 x2 y2
    foreach o [dbQuery -area [list [expr {$x1-0.5}] [expr {$y1-0.5}] [expr {$x2+0.5}] [expr {$y2+0.5}]] -objType {sWire sVia}] {
        catch {
            lassign [lindex [dbGet $o.box] 0] a1 b1 a2 b2
            if {$a2-$a1 <= 4.0 && $b2-$b1 <= 4.0} {
                lq "PG stub delete [dbGet $o.objType] net=[dbGet -e $o.net.name] layer=[dbGet -e $o.layer.name] box=[dbGet $o.box] (marker $sub)"
                dbDeleteObj $o; incr _pg
            }
        }
    }
}
} _pgerr]} { lq "PG stub cleanup skipped: $_pgerr" }
if {$_pg} {
    clearDrc
    verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_pgfix.rpt]
    set n [llength [dbGet -e top.markers]]
    lq "after PG stub cleanup ($_pg deleted): verify_drc = $n"
    saveDesign [pnr_ckpt 05_legal_targeted.enc]
}
lq "LEGAL FINAL verify_drc = $n (targeted; best route state $best)"
close $fh
exit 0
