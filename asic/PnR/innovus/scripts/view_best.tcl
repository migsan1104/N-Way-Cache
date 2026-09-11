# Open ANY run's checkpoint in the Innovus GUI with DRC markers painted.
#   export ASIC_PNR_RUN_STAMP=<run>          # which run dir
#   export ASIC_VIEW_CKPT=05_route.enc       # which checkpoint (default below)
#   innovus -files scripts/view_best.tcl     # launch WITH gui (no -no_gui)
# Handy pairs:
#   20260901_iter14_e35_fp7_armE  + 05_route.enc      = iteration 14 (706)
#   20260901_iter14_e35_fp7_armE  + 05_route_opt.enc  = Arm A wreckage (4,811)
#   20260901_iter14c_e35_fp7_armC + 05_route_opt.enc  = Arm C best (571)
source [file join [file normalize [file dirname [info script]]] innovus_config.tcl]
set _ck [config_env ASIC_VIEW_CKPT 05_route.enc]
pnr_restore_stage $_ck
clearDrc
verify_drc -limit 100000
pnr_note "VIEW: $_ck of $PNR_RUN_STAMP loaded, [llength [dbGet -e top.markers]] markers painted"
