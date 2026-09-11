# setupopt_experiment.tcl (2026-09-09, user: "try setup opt and see if it works
# for this iteration"). A SECOND post-route setup opt on a legalized (0-DRC)
# checkpoint, then hold opt, DRC and timing - the stage-05 post-route section
# replayed on a later checkpoint, saved under its own names so the running
# chain is untouched. Knobs (env): ASIC_SETUPEXP_SRC (05_legal_fixup.enc),
# ASIC_QRC_TECH, ASIC_CTS_USEFUL_SKEW (0), ASIC_IO_MODEL_POSTCTS (1).
# Prints SETUPEXP lines; reports in reports/setupexp/; checkpoints
# 05_setupexp_setup.enc (after setup opt) and 05_setupexp.enc (after hold opt).
set _here [file normalize [file dirname [info script]]]
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
set _src [config_env ASIC_SETUPEXP_SRC 05_legal_fixup.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
proc sx {msg} { puts "SETUPEXP $msg"; pnr_note "SETUPEXP $msg" }
verify_drc -limit 100000 -report [pnr_rpt setupexp drc_before.rpt]
sx "src=$_src DRC before = [llength [dbGet -e top.markers]]"
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true
if {![config_env ASIC_CTS_USEFUL_SKEW 0]} {
    catch {setOptMode -usefulSkew false}
    catch {setOptMode -usefulSkewCCOpt none}
    catch {setAnalysisMode -usefulSkew false}
    sx "useful skew OFF"
}
optDesign -postRoute
saveDesign [pnr_ckpt 05_setupexp_setup.enc]
clearDrc
verify_drc -limit 100000 -report [pnr_rpt setupexp drc_after_setup.rpt]
sx "after setup opt: DRC = [llength [dbGet -e top.markers]]"
if {[config_env ASIC_IO_MODEL_POSTCTS 1]} {
    set _vclk_out [file dirname [pnr_rpt setupexp io_vclk.txt]]
    set io_vclk_applied 0
    if {[catch {source [file join $_here io_vclk.tcl]} _msg]} { sx "io_vclk.tcl failed: $_msg" }
    sx "I/O model applied = $io_vclk_applied"
}
optDesign -postRoute -hold
clearDrc
verify_drc -limit 100000 -report [pnr_rpt setupexp drc_after_hold.rpt]
sx "after hold opt: DRC = [llength [dbGet -e top.markers]]"
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt setupexp x]] -prefix setupexp}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt setupexp x]] -prefix setupexp}
    {report_timing -late -max_paths 1000 -path_type summary > [pnr_rpt setupexp census.rpt]}
    {summaryReport -noHtml -outfile [pnr_rpt setupexp summary.rpt]}
} { if {[catch {eval $_r} _msg]} { sx "REPORT FAILED: $_r -> $_msg" } }
saveDesign [pnr_ckpt 05_setupexp.enc]
sx "DONE: checkpoint 05_setupexp.enc"
