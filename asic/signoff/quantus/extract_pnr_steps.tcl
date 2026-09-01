# Steps of extract_pnr.tcl after the restore - sourceable into a live Innovus
# session that already has the design loaded (needs $out, $tch, config procs).
# 1. LEF-based extraction - the reference for step 3. effortLevel LOW: medium and
# above require a QRC techfile on every RC corner (IMPEXT-3491) - the rule that
# killed stage 09's extractRC on 08-29 and this script's first run on 08-30.
setExtractRCMode -engine postRoute -effortLevel low
extractRC
rcOut -spef [pnr_out ${RUN_TAG}_pnr_lef.spef] -rc_corner rc_slow
pnr_note "LEF-based SPEF written"

# 2. Quantus through the in-house techfile
update_rc_corner -name rc_slow -qx_tech_file $tch
update_rc_corner -name rc_fast -qx_tech_file $tch
setExtractRCMode -engine postRoute -effortLevel signoff
extractRC
rcOut -spef [pnr_out ${RUN_TAG}_pnr.spef]              -rc_corner rc_slow
rcOut -spef [pnr_out ${RUN_TAG}_pnr_rc_fast.spef]      -rc_corner rc_fast
pnr_note "Quantus SPEFs written"

set rdir [file dirname [pnr_rpt signoff_qrc x]]
file mkdir $rdir
timeDesign -signoff       -outDir $rdir -prefix signoff_qrc
timeDesign -signoff -hold -outDir $rdir -prefix signoff_qrc
report_timing -late  -max_paths 50 > $rdir/setup.rpt
report_timing -early -max_paths 50 > $rdir/hold.rpt
report_timing -late -max_paths 1000 -path_type summary > $rdir/census.rpt
pnr_note "QRC signoff timing in $rdir"
exit
