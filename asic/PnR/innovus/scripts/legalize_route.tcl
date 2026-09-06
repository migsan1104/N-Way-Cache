# legalize_route.tcl - 2026-09-06 (iter19). Unattended version of the iter16b
# closure recipe (legalize_fix7.tcl): a stage-05 route that failed the DRC
# gate by tens of markers - all met4 shorts against SRAM macro pins/bodies -
# is re-routed incrementally with met4 guidance blockages over the 16 macro
# bodies (452 PG straps live there; no room for signal met4), then the
# post-route setup opt the gate skipped is run. Driven by legalize_route.sh.
#   ASIC_LEGALIZE_SRC      checkpoint to start from      (05_route.enc)
#   ASIC_LEGALIZE_OPT_MAX  run optDesign only if markers <= this (20)
# ASIC_LEGALIZE_BLK/_TD/_SI/_ANT  macro met4 blockages / timing- / SI-driven /
#                        antenna-fix routing (all default 0)
# ASIC_LEGALIZE_FULL=1   full routeDesign (use with ASIC_LEGALIZE_SRC=04_cts.enc)
# Saves 05_legal_route.enc (after the route fix) and 05_legal_opt.enc (after
# opt); reports in reports/legalize/. Prints "LEGAL FINAL verify_drc = N".
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_LEGALIZE_SRC 05_route.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
# Same I/O model as the chain and Tempus (armC lesson: raw SDC -> 715 hold
# delay cells on the input flops) - apply BEFORE any optimisation.
if {[catch {get_clocks vclk_io}]} {
    set _vclk_out [file dirname [pnr_rpt legalize io_vclk.txt]]
    set io_vclk_applied 0
    catch {source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/io_vclk.tcl}
    pnr_note "LEGAL io_vclk applied = $io_vclk_applied"
} else { pnr_note "LEGAL vclk_io already in the DB" }
set fh [open [pnr_rpt legalize route_fix.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
lq "src=$_src markers_in_db=[llength [dbGet -e top.markers]]"

proc legal_macro_blk {} {
    deleteRouteBlk -all
    foreach m [dbGet -p2 top.insts.cell.name *sram*] {
        lassign [lindex [dbGet $m.box] 0] x1 y1 x2 y2
        createRouteBlk -name g_m4_[dbGet $m.name] -box [list [expr {$x1+1.5}] [expr {$y1+2.0}] [expr {$x2-1.5}] [expr {$y2-2.0}]] -layer {met4} -exceptpgnet
    }
    return [llength [dbGet -e top.fplan.rBlkgs]]
}
# iter19 lesson (2026-09-06): the stage-05 detail route ends at 0 violations
# and NanoRoute's *timing-driven prevention* pass then manufactures the 50;
# with SI-driven on top the incremental route went 22 -> 54 -> 176 -> 63.
# Defaults are therefore DRC-only routing (opt handles timing afterwards)
# and NO macro blockages (they push the met4 threads into the ring-corner
# channel). ASIC_LEGALIZE_BLK=1 / _TD=1 / _SI=1 restore the fix7 settings.
set _blk [config_env ASIC_LEGALIZE_BLK 0]
set _td  [config_env ASIC_LEGALIZE_TD 0]
set _si  [config_env ASIC_LEGALIZE_SI 0]
if {$_blk} { lq "met4 guidance blockages=[legal_macro_blk]" } else { deleteRouteBlk -all; lq "no guidance blockages" }
lq "routeWithTimingDriven=$_td routeWithSiDriven=$_si"
# Attempt 2 (2026-09-06): the incremental detail route stalls at 22 and the
# antenna-fix routing phase (drouteFixAntenna, inherited from stage 05) then
# climbs it to 46 while "fixing" 205 antenna violations. Antennas belong to
# the chain's diode ECO (antenna_eco.tcl), so the default here is off.
set _ant [config_env ASIC_LEGALIZE_ANT 0]
lq "drouteFixAntenna=$_ant"
setNanoRouteMode -drouteFixAntenna [expr {$_ant ? "true" : "false"}]
# ASIC_LEGALIZE_FULL=1 (attempt 3): the incremental route only rips up the
# violating nets and stalls at ~22 with everything else fixed, while the
# original stage-05 detail route reached 0 before its timing-driven pass.
# So re-route the whole design from the post-CTS checkpoint
# (ASIC_LEGALIZE_SRC=04_cts.enc) with the stage-05 modes minus TD/SI/antenna.
set _full [config_env ASIC_LEGALIZE_FULL 0]
set _skip [config_env ASIC_LEGALIZE_SKIP_ROUTE 0]   ;# 1 = no routeDesign, go straight to verify + opt
if {$_full && !$_skip} {
    setNanoRouteMode -reset
    setNanoRouteMode -routeBottomRoutingLayer 2 -routeTopRoutingLayer 6
    setNanoRouteMode -drouteFixAntenna [expr {$_ant ? "true" : "false"}] -routeAntennaCellName sky130_fd_sc_hd__diode_2
    lq "FULL route from $_src (stage-05 modes, TD=$_td SI=$_si antenna=$_ant)"
}
setNanoRouteMode -drouteEndIteration 40
setNanoRouteMode -routeWithTimingDriven [expr {$_td ? "true" : "false"}] -routeWithSiDriven [expr {$_si ? "true" : "false"}]
if {!$_skip} { routeDesign } else { lq "routeDesign skipped (ASIC_LEGALIZE_SKIP_ROUTE=1)" }
deleteRouteBlk -all
if {$_full && !$_skip} { saveDesign [pnr_ckpt 05_legal_route_raw.enc] }
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_route_fix.rpt]
set n [llength [dbGet -e top.markers]]
lq "after route fix: verify_drc = $n"
# PG stubs (iter19): 4 x MINWIDTH met5 VDD fragments (1.5 x 2.6 um at the
# top strap, x = 810/1226/1643/2059) and the NSMETAL VSS via at (922,2860)
# that 16b fixed by hand (fix8-10). Delete only special-wire objects that
# are themselves tiny (<= 4 um in both directions) inside such a marker.
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
}
pnr_note "LEGAL after route fix: verify_drc = $n"
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_route_fix.rpt]}
saveDesign [pnr_ckpt 05_legal_route.enc]

set _max [config_env ASIC_LEGALIZE_OPT_MAX 20]
if {$n > $_max} {
    lq "LEGAL FINAL verify_drc = $n (route fix only; > $_max so opt skipped)"
    close $fh; exit 0
}
# Post-route setup opt the gate skipped (stage 05 tail), blockages back on so
# ecoRoute cannot re-enter the macro bodies on met4.
if {$_blk} { lq "opt: met4 guidance blockages=[legal_macro_blk]" }
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true
optDesign -postRoute
deleteRouteBlk -all
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_opt.rpt]
set n2 [llength [dbGet -e top.markers]]
lq "after opt: verify_drc = $n2"
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt legalize x]] -prefix legal_opt}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt legalize x]] -prefix legal_opt}
    {report_timing -late -max_paths 50 > [pnr_rpt legalize setup_after_opt.rpt]}
    {report_timing -late -max_paths 1000 -path_type summary > [pnr_rpt legalize census_after_opt.rpt]}
} { if {[catch {eval $_r} _m]} { pnr_note "REPORT FAILED: $_r -> $_m" } }
saveDesign [pnr_ckpt 05_legal_opt.enc]
lq "LEGAL FINAL verify_drc = $n2 (after opt; route fix had $n)"
pnr_note "LEGAL FINAL verify_drc = $n2"
close $fh
exit 0
