# classify_vss.tcl - 2026-09-04 iter16b: the export's verifyConnectivity
# reported 1000+ (report cap) unconnected VSS terminals on the filled design,
# same count as armC, even though 06_export.tcl's globalNetConnect rerun
# executed. The .rpt carries only the total; this lists the terminals so
# they can be classified (SRAM wmask1[*] pins with no geometry? fill? hold
# cells?). Also writes the sim netlist 06_export's netlist-sim step failed on.
#   ASIC_PNR_RUN_STAMP=<stamp> innovus -no_gui -files scripts/classify_vss.tcl
source [file join [file normalize [file dirname [info script]]] innovus_config.tcl]
pnr_restore_stage 06_final.enc
set d [file dirname [pnr_rpt vss_classify x]]
verifyConnectivity -type special -net {VSS VDD} -error 200000 -warning 50 \
    -report [pnr_rpt vss_classify special_pg.rpt]
verifyConnectivity -type all -error 200000 -warning 50 \
    -report [pnr_rpt vss_classify all.rpt]
pnr_note "VSS CLASSIFY reports in $d"
saveNetlist -excludeLeafCell [pnr_out ${RUN_TAG}_pnr_sim.v]
pnr_note "VSS CLASSIFY sim netlist written"
exit
