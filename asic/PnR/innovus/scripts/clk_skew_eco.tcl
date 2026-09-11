# clk_skew_eco.tcl (2026-09-09): hand-placed useful skew on the compare-stage
# capture registers (out_rdata[31:0], out_victim_line[127:0]) - the endpoints
# of the SRAM half-cycle read path that limits iter26b (Tempus: 6.0 +0.017,
# 5.88 +0.002, 5.5 -0.179). One clock delay cell per register clock pin
# (ecoAddRepeater on the leaf), so nothing else in the tree moves; the path
# INTO them gains the cell delay, the paths OUT of them lose it. Gate was the
# clk_borrow_probe (downstream room / hold room). Verify DRC + antenna +
# hold, checkPlace, save ASIC_ECO_DST only if clean.
# Knobs: ASIC_ECO_SRC (05_pgvia7.enc) ASIC_ECO_DST (05_clkskew8.enc)
#        ASIC_SKEW_CELL (sky130_fd_sc_hd__clkdlybuf4s15_1)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 05_pgvia7.enc]
set _dst [config_env ASIC_ECO_DST 05_clkskew8.enc]
set CELL [config_env ASIC_SKEW_CELL sky130_fd_sc_hd__clkdlybuf4s15_1]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt clk_skew io_vclk.txt]]
set io_vclk_applied 0
catch {source [file join [file dirname [info script]] io_vclk.tcl]}
proc sk {msg} { puts "SKEW $msg"; pnr_note "SKEW $msg" }
set D [file dirname [pnr_rpt clk_skew x]]
set regs [get_cells -quiet [config_env ASIC_SKEW_REGS {COMPARE_SELECT_REPLACE_out_rdata_reg* COMPARE_SELECT_REPLACE_out_victim_line_reg*}]]
sk "src=$_src cell=$CELL registers=[sizeof_collection $regs]"
proc worst {args} { set c [eval report_timing $args -max_paths 1 -collection]; if {[sizeof_collection $c]} { return [format %.3f [get_property [index_collection $c 0] slack]] } else { return "n/a" } }
sk "BEFORE: to_regs setup [worst -late -to $regs] | from_regs setup [worst -late -from $regs] | to_regs hold [worst -early -to $regs] | design setup [worst -late] hold [worst -early]"
# --- the ECO ---
setDontUse $CELL false
setEcoMode -refinePlace true -updateTiming false -honorDontUse false
setNanoRouteMode -drouteFixAntenna false -routeInsertAntennaDiode false
set nadd 0; set nfail 0; set added {}
foreach_in_collection c $regs {
    set n [get_object_name $c]
    set inst "USK_${nadd}_[string map {[ _ ] _ . _} $n]"
    if {[catch {ecoAddRepeater -term "$n/CLK" -cell $CELL -name $inst} m]} { incr nfail; if {$nfail <= 3} { sk "ecoAddRepeater $n/CLK failed: $m" } } else { incr nadd; lappend added $inst }
}
sk "delay cells added: $nadd, failed: $nfail"
if {$nadd == 0} { sk "ABORT: nothing added"; exit 5 }
catch {refinePlace -eco true -inst $added}
ecoRoute
clearDrc
verify_drc -limit 100000 -report [pnr_rpt clk_skew drc_final.rpt]
set d [llength [dbGet -e top.markers]]
set arpt [pnr_rpt clk_skew antenna_final.rpt]
verifyProcessAntenna -report $arpt
set fh [open $arpt r]; set t [read $fh]; close $fh
set a -1
if {[regexp {No Violations Found} $t]} { set a 0 } elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $t -> a]} { regexp {Verification Complete\s*:\s*(\d+)} $t -> a }
catch {checkPlace [pnr_rpt clk_skew checkplace_final.rpt]}
# overlap audit of the new cells
set ov 0
foreach i $added {
    set p [dbGet -p top.insts.name $i]; if {$p eq "0x0" || $p eq ""} { continue }
    set box [lindex [dbGet $p.box] 0]
    foreach o [dbQuery -area $box -objType inst] {
        if {$o == $p || [dbGet $o.cell.baseClass] eq "block"} { continue }
        lassign [lindex [dbGet $o.box] 0] ox1 oy1 ox2 oy2; lassign $box x1 y1 x2 y2
        if {$ox2 - $x1 > 0.001 && $x2 - $ox1 > 0.001 && $oy2 - $y1 > 0.001 && $y2 - $oy1 > 0.001} { incr ov; break }
    }
}
foreach _r {
    {timeDesign -postRoute       -outDir $D -prefix final}
    {timeDesign -postRoute -hold -outDir $D -prefix final}
} { catch {eval $_r} }
report_timing -late -to $regs -max_paths 10 -path_type full_clock > $D/to_regs_setup_after.rpt
report_timing -late -from $regs -max_paths 10 -path_type full_clock > $D/from_regs_setup_after.rpt
report_timing -early -to $regs -max_paths 10 -path_type full_clock > $D/to_regs_hold_after.rpt
sk "AFTER: to_regs setup [worst -late -to $regs] | from_regs setup [worst -late -from $regs] | to_regs hold [worst -early -to $regs] | design setup [worst -late] hold [worst -early]"
sk "FINAL: verify_drc = $d, antenna = $a, overlapping new cells = $ov"
if {$d == 0 && $a == 0 && $ov == 0} { saveDesign [pnr_ckpt $_dst]; sk "saved $_dst (clean)" } else { set dd [string map {.enc _dirty.enc} $_dst]; saveDesign [pnr_ckpt $dd]; sk "NOT CLEAN - saved $dd" }
exit
