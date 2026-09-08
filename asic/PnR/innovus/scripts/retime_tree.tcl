# retime_tree.tcl - re-time a saved post-CTS tree with given preRoute RC factors
# (2026-09-07, CTS.md 5b). Scratch session, nothing saved. Env:
#   RT_RUN   run directory (runs/<stamp>)      RT_CKPT  checkpoint name (default 04_cts.enc)
#   RT_RES / RT_CAP / RT_CLKRES / RT_CLKCAP  preRoute factors (default 1.1 1.1 1.1 1.1)
#   RT_OUT   output dir for reports
set R $env(RT_RUN); set ck [expr {[info exists env(RT_CKPT)] ? $env(RT_CKPT) : "04_cts.enc"}]
set out $env(RT_OUT); file mkdir $out
foreach {v d} {RT_RES 1.1 RT_CAP 1.1 RT_CLKRES 1.1 RT_CLKCAP 1.1} { set $v [expr {[info exists env($v)] ? $env($v) : $d}] }
restoreDesign $R/checkpoints/$ck.dat Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1
set _qrc /ecel/UFAD/miguel.sanchez1/Cache/asic/signoff/quantus/techfiles/sky130A_nom.tch
foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} }
foreach _c {rc_slow rc_fast} { update_rc_corner -name $_c -preRoute_res $RT_RES -preRoute_cap $RT_CAP -preRoute_clkres $RT_CLKRES -preRoute_clkcap $RT_CLKCAP }
set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
setExtractRCMode -engine preRoute
extractRC
timeDesign -postCTS -prefix retime -outDir $out
report_clock_timing -type summary > $out/clock_summary.rpt
report_clock_timing -type skew    > $out/skew.rpt
catch {report_ccopt_clock_tree_structure -file $out/tree_structure.rpt}
catch {report_ccopt_skew_groups -file $out/skew_groups.rpt}
catch {report_ccopt_clock_trees -file $out/clock_trees.rpt}
puts "RETIME ==== $R at preRoute res $RT_RES cap $RT_CAP clkres $RT_CLKRES clkcap $RT_CLKCAP"
set f [open $out/skew.rpt r]; set n 0; while {[gets $f l] >= 0 && $n < 14} { puts "RETIME $l"; incr n }; close $f
set f [open $out/tree_structure.rpt r]; set usk 0; set ml 0
while {[gets $f l] >= 0} { if {[string match *FE_USK* $l]} { incr usk }; regexp {Max Level: (\d+)} $l -> ml }; close $f
puts "RETIME tree Max Level $ml FE_USK cells $usk"
puts "RETIME DONE"
exit
