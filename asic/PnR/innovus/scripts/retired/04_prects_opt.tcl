# RETIRED 2026-08-30 - folded into 03_place.tcl (place_opt_design does
# placement and pre-CTS optimisation as one integrated step; v2 measured the
# split at -6.97 vs -3.8 integrated on the same floorplan). Kept for reading;
# no longer in run_innovus.tcl's STAGES and nothing restores 04_prects_opt.enc.
# Sourcing it now would double-optimise a stage-03 result - hence the guard.
pnr_fail "stage 04 is retired - pre-CTS opt happens inside 03_place.tcl"
# # Stage 04 - pre-CTS optimisation.
# #
# # Split out from placement so opt settings can be retuned without paying for
# # placement again. This is the stage to iterate on when setup is close.
# #
# # SETUP ONLY here, deliberately. The clock is still ideal - golden.sdc's 0.250 ns
# # uncertainty is standing in for a tree that does not exist yet - so any hold
# # "fix" made now is fixing a number that CTS is about to invalidate, at the cost
# # of buffers that stay in the design. Hold becomes real in stage 06.
# 
# set _here [file normalize [file dirname [info script]]]
# # Config first (idempotent), then restore the previous stage ONLY if no
# # design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# # failed after sourcing the config leaves the variable defined and a
# # re-source then skips the restore (floorPlan "unithd does not match any
# # object in design" - first shakedown 2026-08-26).
# if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
# if {[dbGet -e top] eq ""} { pnr_restore_stage 03_place.enc }
# 
# setOptMode -reset
# setOptMode -fixCap true -fixTran true -fixFanout true
# 
# optDesign -preCTS
# 
# # ---------------------------------------------------------------------------
# # Reports
# # ---------------------------------------------------------------------------
# # hold.rpt is written even though hold is not being fixed yet: it is the
# # baseline the post-CTS hold number gets compared against, and a wildly bad
# # pre-CTS hold usually means a constraint problem rather than a real violation.
# report_timing -late  -max_paths 20 > [pnr_rpt prects_opt setup.rpt]
# report_timing -early -max_paths 20 > [pnr_rpt prects_opt hold.rpt]
# report_area                        > [pnr_rpt prects_opt area.rpt]
# report_power                       > [pnr_rpt prects_opt power.rpt]
# # -overflow is mandatory in v21.16 (IMPSP-9110, shakedown 2026-08-27).
# reportCongestion -overflow         > [pnr_rpt prects_opt congestion.rpt]
# summaryReport -noHtml -outfile [pnr_rpt prects_opt summary.rpt]
# 
# saveDesign [pnr_ckpt 04_prects_opt.enc]
# pnr_note "stage 04 (pre-CTS opt) complete - setup only; hold is stage 06"
