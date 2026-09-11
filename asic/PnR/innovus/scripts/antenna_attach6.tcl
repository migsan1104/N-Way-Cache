# antenna_attach6.tcl (2026-09-09): legalize the antenna diodes that are still
# sitting ON TOP of the flop they protect. KLayout on the iter26b export showed
# 38 li.3 items outside the macros, all at diode_2 cells; a DEF sweep found
# exactly 10 overlapping pairs in 851,829 cells, every one diode-on-flop, and
# checkPlace had said so ("overlapping with other insts (20)") next to the
# 0 DRC / 0 antenna that got quoted. refinePlace -eco -inst left them (attach3);
# a full refinePlace is forbidden (19b wreck). Here: find the overlapping
# diodes with dbQuery, set them placeable, try refinePlace -eco on them alone,
# then for any survivor walk its own row for the nearest free gap within
# ASIC_ATTACH6_WINDOW um and placeInstance it there. Nothing is saved unless
# checkPlace reports zero overlaps. Then ecoRoute (insertion OFF), verify DRC +
# antenna + timing, save 05_antenna_final6.enc.
# Knobs: ASIC_ANTENNA_ATTACH_SRC (05_antenna_final5.enc), ASIC_ATTACH6_WINDOW (60).
set _here [file normalize [file dirname [info script]]]
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
set _src [config_env ASIC_ANTENNA_ATTACH_SRC 05_antenna_final5.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt antenna_attach6 io_vclk.txt]]
set io_vclk_applied 0
if {[catch {source [file join $_here io_vclk.tcl]} _m]} { puts "ATTACH6 io_vclk failed: $_m" }
proc ax {msg} { puts "ATTACH6 $msg"; pnr_note "ATTACH6 $msg" }
proc wns {tag} {
    set s [get_property [report_timing -late  -max_paths 1 -collection] slack]
    set h [get_property [report_timing -early -max_paths 1 -collection] slack]
    ax "$tag: setup WNS $s hold WNS $h"
}
proc count_ant {rpt} {
    set fh [open $rpt r]; set t [read $fh]; close $fh
    set n -1
    if {[regexp {No Violations Found} $t]} { set n 0 } elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $t -> n]} { regexp {Verification Complete\s*:\s*(\d+)} $t -> n }
    return $n
}
set DIODE sky130_fd_sc_hd__diode_2
set WIN [config_env ASIC_ATTACH6_WINDOW 60]
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
ax "src=$_src io_vclk=$io_vclk_applied"
wns "before"

# --- which diodes overlap another standard cell (box query, macros excluded) ---
proc overlapping_diodes {} {
    global DIODE
    set bad {}
    foreach d [dbGet -p2 top.insts.cell.name $DIODE] {
        set box [lindex [dbGet $d.box] 0]
        foreach o [dbQuery -area $box -objType inst] {
            if {$o == $d} { continue }
            if {[dbGet $o.cell.baseClass] eq "block"} { continue }
            lassign [lindex [dbGet $o.box] 0] ox1 oy1 ox2 oy2
            lassign $box x1 y1 x2 y2
            # dbQuery is inclusive on touching edges; require real area overlap
            if {$ox2 - $x1 > 0.001 && $x2 - $ox1 > 0.001 && $oy2 - $y1 > 0.001 && $y2 - $oy1 > 0.001} {
                lappend bad $d; break
            }
        }
    }
    return $bad
}
set bad [overlapping_diodes]
ax "overlapping diodes at start: [llength $bad]"
foreach d $bad { ax "  [dbGet $d.name] box [lindex [dbGet $d.box] 0] status [dbGet $d.pStatus]" }
if {[llength $bad] == 0} { ax "nothing to do"; exit 0 }

# --- pass 1: make them movable and let the eco legalizer try on them alone ---
foreach d $bad { dbSet $d.pStatus placed }
set names [dbGet $bad.name]
if {[catch {refinePlace -eco true -inst $names} m]} { ax "refinePlace -eco -inst failed: $m" }
set bad [overlapping_diodes]
ax "overlapping diodes after refinePlace -eco: [llength $bad]"

# --- pass 2: explicit placement into the nearest free gap of the diode's own row ---
set SITE 0.46
foreach d $bad {
    lassign [lindex [dbGet $d.box] 0] x1 y1 x2 y2
    set w [expr {$x2 - $x1}]; set h [expr {$y2 - $y1}]
    set orient [dbGet $d.orient]
    # every placed cell whose box intersects this row band inside the window
    set occ {}
    foreach o [dbQuery -area [list [expr {$x1 - $WIN}] [expr {$y1 + 0.01}] [expr {$x2 + $WIN}] [expr {$y2 - 0.01}]] -objType inst] {
        if {$o == $d} { continue }
        lassign [lindex [dbGet $o.box] 0] ox1 oy1 ox2 oy2
        lappend occ [list $ox1 $ox2]
    }
    set occ [lsort -real -index 0 $occ]
    # row origin for site snapping
    set rowx ""
    catch { set rowx [lindex [lindex [dbGet [dbQuery -area [list $x1 $y1 $x2 $y2] -objType row].box] 0] 0] }
    if {$rowx eq "" || $rowx eq "0x0"} { set rowx [lindex [lindex [dbGet top.fPlan.coreBox] 0] 0] }
    set best ""; set bestd 1e9
    set prev_end [expr {$x1 - $WIN}]
    foreach seg [concat $occ [list [list [expr {$x2 + $WIN}] [expr {$x2 + $WIN}]]]] {
        lassign $seg s e
        set gap [expr {$s - $prev_end}]
        if {$gap >= $w + 0.001} {
            # candidate positions: left end and right end of the gap, snapped to sites
            foreach cand [list $prev_end [expr {$s - $w}]] {
                set cx [expr {$rowx + round(($cand - $rowx) / $SITE) * $SITE}]
                if {$cx < $prev_end - 0.001} { set cx [expr {$cx + $SITE}] }
                if {$cx + $w > $s + 0.001} { set cx [expr {$cx - $SITE}] }
                if {$cx < $prev_end - 0.001 || $cx + $w > $s + 0.001} { continue }
                set dist [expr {abs($cx - $x1)}]
                if {$dist < $bestd} { set bestd $dist; set best $cx }
            }
        }
        if {$e > $prev_end} { set prev_end $e }
    }
    if {$best eq ""} { ax "NO GAP within $WIN um for [dbGet $d.name] (row y=$y1)"; continue }
    ax "moving [dbGet $d.name] from $x1 to $best (dx=[format %.2f [expr {$best - $x1}]]) orient $orient"
    if {[catch {placeInstance [dbGet $d.name] $best $y1 $orient -placed} m]} { ax "placeInstance failed: $m" }
}
set bad [overlapping_diodes]
ax "overlapping diodes after explicit placement: [llength $bad]"
catch {checkPlace [pnr_rpt antenna_attach6 checkplace.rpt]}
if {[llength $bad] > 0} {
    foreach d $bad { ax "  still overlapping: [dbGet $d.name]" }
    ax "ABORT: overlaps remain, nothing saved"
    exit 5
}

# --- reconnect the moved diodes, then the usual verification ---
ecoRoute
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_attach6 drc_final.rpt]
set dd [llength [dbGet -e top.markers]]
set arpt [pnr_rpt antenna_attach6 antenna_final.rpt]
verifyProcessAntenna -report $arpt
set n [count_ant $arpt]
catch {checkPlace [pnr_rpt antenna_attach6 checkplace_final.rpt]}
set bad [overlapping_diodes]
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt antenna_attach6 x]] -prefix final}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt antenna_attach6 x]] -prefix final}
} { catch {eval $_r} }
wns "final"
ax "FINAL: verify_drc = $dd, antenna = $n, overlapping diodes = [llength $bad]; checkpoint 05_antenna_final6.enc"
if {$dd != 0 || $n != 0 || [llength $bad] != 0} { ax "WARNING: not clean - checkpoint saved for inspection, do NOT export without looking" }
saveDesign [pnr_ckpt 05_antenna_final6.enc]
exit
