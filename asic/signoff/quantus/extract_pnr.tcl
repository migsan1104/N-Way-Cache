# Design-level validation (quantus/quantus.md step 3) and the real use of the
# techfile: re-extract a finished P&R run with Quantus and re-time it.
#
#   bash -lc 'source /apps/settings && source <repo>/asic/PnR/innovus/env.sh && \
#             source <repo>/asic/signoff/env.sh && cd $SIGNOFF_RESULTS/quantus && \
#             innovus -no_gui -files <repo>/asic/signoff/quantus/extract_pnr.tcl -log innovus_qrc'
#
# Restores 09_final.enc, writes the LEF-based SPEF (what stage 09 tried to do
# before the -qx_tech_file bug), then hooks the techfile into both RC corners,
# extracts with the Quantus engine, writes per-corner SPEFs and re-times in
# signoff mode into reports/signoff_qrc/. Nothing is saved back to the checkpoint.
set pnr_scripts [file join $env(SIGNOFF_PNR_DIR) scripts]
source [file join $pnr_scripts innovus_config.tcl]
set out $env(SIGNOFF_RESULTS)/quantus
file mkdir $out
set tch $env(SKY130_QRC_TECH_DIR)/sky130A_nom.tch
if {![file readable $tch]} { error "no techfile at $tch" }

pnr_restore_stage 09_final.enc
pnr_note "restored 09_final.enc, RUN_TAG=$RUN_TAG"
source [file join [file dirname [file normalize [info script]]] extract_pnr_steps.tcl]

