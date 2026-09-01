# RETIRED 2026-08-30 - folded into 04_cts.tcl (CTS + post-CTS opt now one stage). Kept for reading; no longer
# in run_innovus.tcl's STAGES. Sourcing it now would double-optimise - guard:
pnr_fail "stage 06 is retired - see the combined stage"
# # Stage 06 - post-CTS optimisation: the first stage where hold is real.
# #
# # The clock is propagated and the tree's skew is measured, so both directions
# # now mean something. Setup first, then hold - hold fixes insert delay buffers
# # which can only hurt setup, so fixing setup afterwards would undo them. That
# # order holds at every optimisation stage in this flow and is not interchangeable.
# 
# set _here [file normalize [file dirname [info script]]]
# # Config first (idempotent), then restore the previous stage ONLY if no
# # design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# # failed after sourcing the config leaves the variable defined and a
# # re-source then skips the restore (floorPlan "unithd does not match any
# # object in design" - first shakedown 2026-08-26).
# if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
# if {[dbGet -e top] eq ""} { pnr_restore_stage 05_cts.enc }
# 
# setOptMode -reset
# setOptMode -fixCap true -fixTran true -fixFanout true
# 
# optDesign -postCTS
# optDesign -postCTS -hold
# 
# # ---------------------------------------------------------------------------
# # Reports
# # ---------------------------------------------------------------------------
# # Wrapped in catch so a report quirk cannot abort between the expensive
# # optDesign pair and the saveDesign (stage-05 lesson, 2026-08-28).
# foreach _r {
#     {timeDesign -postCTS       -outDir [file dirname [pnr_rpt postcts_opt x]] -prefix postcts_opt}
#     {timeDesign -postCTS -hold -outDir [file dirname [pnr_rpt postcts_opt x]] -prefix postcts_opt}
#     {report_timing -late  -max_paths 20 > [pnr_rpt postcts_opt setup.rpt]}
#     {report_timing -early -max_paths 20 > [pnr_rpt postcts_opt hold.rpt]}
#     {report_area                        > [pnr_rpt postcts_opt area.rpt]}
#     {report_power                       > [pnr_rpt postcts_opt power.rpt]}
#     {reportCongestion -overflow         > [pnr_rpt postcts_opt congestion.rpt]}
#     {summaryReport -noHtml -outfile [pnr_rpt postcts_opt summary.rpt]}
# } {
#     if {[catch {eval $_r} _msg]} { pnr_note "REPORT FAILED (fix cmd, rerun by hand): $_r -> $_msg" }
# }
# 
# saveDesign [pnr_ckpt 06_postcts_opt.enc]
# pnr_note "stage 06 (post-CTS opt) complete - check postcts_opt/hold.rpt: this is\
#           the first honest hold number in the whole flow"
