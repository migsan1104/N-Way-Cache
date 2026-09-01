# RETIRED 2026-08-30 - folded into 05_route.tcl (route -> verify_drc gate -> post-route opt). Kept for reading; no longer
# in run_innovus.tcl's STAGES. Sourcing it now would double-optimise - guard:
pnr_fail "stage 08 is retired - see the combined stage"
# # Stage 08 - post-route optimisation.
# #
# # The first numbers in this project worth quoting against the real 4.000 ns
# # target. Everything upstream used estimated parasitics: synthesis used
# # placement-based estimates (PLE), which asic/README.md is explicit are a FLOOR -
# # post-route slack is expected to be WORSE than the -729 ps / 236.5 MHz the
# # Genus baseline reports at 3.500 ns. That expectation gets tested here.
# #
# # Setup then hold, for the same reason as stage 06.
# 
# set _here [file normalize [file dirname [info script]]]
# # Config first (idempotent), then restore the previous stage ONLY if no
# # design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# # failed after sourcing the config leaves the variable defined and a
# # re-source then skips the restore (floorPlan "unithd does not match any
# # object in design" - first shakedown 2026-08-26).
# if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
# if {[dbGet -e top] eq ""} { pnr_restore_stage 07_route.enc }
# 
# # Post-route optDesign refuses to run in the default non-OCV analysis mode
# # (IMPOPT-6080 - this killed the discarded single-file flow's first route,
# # 2026-08-26). OCV here means each path is timed with its own early/late
# # clock arrivals instead of one global worst case; -cppr both removes the
# # pessimism of derating the SHARED part of launch/capture clock paths twice.
# # Timing reports from here on are OCV numbers - slightly different from the
# # pre-route non-OCV banners, expected.
# setAnalysisMode -analysisType onChipVariation -cppr both
# 
# setOptMode -reset
# setOptMode -fixCap true -fixTran true -fixFanout true
# 
# optDesign -postRoute
# saveDesign [pnr_ckpt 08_postroute_setup.enc]
# optDesign -postRoute -hold
# 
# # ---------------------------------------------------------------------------
# # Reports
# # ---------------------------------------------------------------------------
# # The deep census report is what asic/census.py parses. Grouping post-route
# # paths by startpoint->endpoint class is what makes this result comparable to
# # every synthesis census this campaign has run on - same tool, same grouping.
# # Wrapped in catch so a report quirk cannot abort before the save (stage-05
# # lesson, 2026-08-28).
# foreach _r {
#     {timeDesign -postRoute       -outDir [file dirname [pnr_rpt postroute_opt x]] -prefix postroute_opt}
#     {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt postroute_opt x]] -prefix postroute_opt}
#     {verify_drc -limit 100000 -report [pnr_rpt postroute_opt drc.rpt]}
#     {report_timing -late  -max_paths 50 > [pnr_rpt postroute_opt setup.rpt]}
#     {report_timing -early -max_paths 50 > [pnr_rpt postroute_opt hold.rpt]}
#     {report_timing -late -max_paths 1000 -path_type summary > [pnr_rpt postroute_opt census.rpt]}
#     {report_area      > [pnr_rpt postroute_opt area.rpt]}
#     {report_power     > [pnr_rpt postroute_opt power.rpt]}
#     {reportCongestion -overflow > [pnr_rpt postroute_opt congestion.rpt]}
#     {summaryReport -noHtml -outfile [pnr_rpt postroute_opt summary.rpt]}
# } {
#     if {[catch {eval $_r} _msg]} { pnr_note "REPORT FAILED (fix cmd, rerun by hand): $_r -> $_msg" }
# }
# 
# saveDesign [pnr_ckpt 08_postroute_opt.enc]
# pnr_note "stage 08 (post-route opt) complete - first quotable timing numbers"
