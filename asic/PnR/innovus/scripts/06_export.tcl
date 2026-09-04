# Stage 06 - export (old stage 09, renumbered 2026-08-30): fill, verify, extract, write out the deliverables.
#
# Nothing here changes timing except the filler insertion (which does not) - the
# purpose of this stage is to produce the files a signoff hand-off consists of,
# and to run the checks that say whether the result is real.

set _here [file normalize [file dirname [info script]]]
# Config first (idempotent), then restore the previous stage ONLY if no
# design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# failed after sourcing the config leaves the variable defined and a
# re-source then skips the restore (floorPlan "unithd does not match any
# object in design" - first shakedown 2026-08-26).
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
if {[dbGet -e top] eq ""} { pnr_restore_stage 05_route_opt.enc }

# ---------------------------------------------------------------------------
# Fill
# ---------------------------------------------------------------------------
# Decaps first (they do something), then plain fill for the leftovers. Both are
# needed for a manufacturable row: gaps in the row are gaps in the wells.
addFiller -cell $DECAP_CELLS  -prefix DECAP
addFiller -cell $FILLER_CELLS -prefix FILLER
pnr_note "fill inserted (decap + filler)"
saveDesign [pnr_ckpt 06_filled.enc]

# Every step from here is independent of the others, and each is a place a
# tool-version quirk can throw (stage-05 lesson, 2026-08-28). One failing
# check must not cost the deliverables that follow it, so each runs in catch
# and reports failures at the end.
set _failed {}
proc _step {label body} {
    global _failed
    pnr_note "export: $label"
    if {[catch {uplevel 1 $body} _msg]} {
        pnr_note "EXPORT STEP FAILED ($label): $_msg"
        lappend _failed $label
    }
}

# ---------------------------------------------------------------------------
# Global net connections, again
# ---------------------------------------------------------------------------
# 02_power.tcl's globalNetConnect ... -inst * only binds the instances that
# exist when it runs. Every cell created after it - hold-fix FE_PHC cells,
# resized cells, the fillers and decaps just inserted above - has no VPWR/
# VGND/VPB/VNB assignment, and verifyConnectivity lists each of them as an
# unconnected terminal (iter16b 2026-09-03: 1000+ VNB pins, all on FE_PHC*).
# Exported as-is that is an LVS open on every hold cell's well tie. Same
# block as 02_power.tcl; the variables come from innovus_config.tcl.
_step globalNetConnect {
    foreach pin $PG_CELL_POWER_PINS  { globalNetConnect $PG_POWER_NET  -type pgpin -pin $pin -inst * -override }
    foreach pin $PG_CELL_GROUND_PINS { globalNetConnect $PG_GROUND_NET -type pgpin -pin $pin -inst * -override }
    if {$SRAM_MACRO} {
        foreach pin $PG_MACRO_POWER_PINS  { globalNetConnect $PG_POWER_NET  -type pgpin -pin $pin -inst * -override }
        foreach pin $PG_MACRO_GROUND_PINS { globalNetConnect $PG_GROUND_NET -type pgpin -pin $pin -inst * -override }
    }
    globalNetConnect $PG_POWER_NET  -type tiehi -inst * -override
    globalNetConnect $PG_GROUND_NET -type tielo -inst * -override
    pnr_note "globalNetConnect re-applied to all instances (post-fill)"
}

# ---------------------------------------------------------------------------
# Verification - the checks that decide whether this run counts
# ---------------------------------------------------------------------------
_step connectivity {verifyConnectivity -type all -noAntenna > [pnr_rpt signoff connectivity.rpt]}
_step geometry     {verifyGeometry > [pnr_rpt signoff geometry.rpt]}
_step antenna      {verifyProcessAntenna > [pnr_rpt signoff antenna.rpt]}
_step welltap      {verifyWellTap -rule $TAP_DISTANCE -report [pnr_rpt signoff welltap.rpt]}

# ---------------------------------------------------------------------------
# Extraction and final timing
# ---------------------------------------------------------------------------
# LEF-based extraction: this PDK ships no QRC tech file and no captable, so
# there is no signoff-grade extraction available. Quote these numbers with that
# attached (README.md, "RC corners").
#
# 2026-08-31 ROOT CAUSE of the long-standing "stage 09 FAILED STEPS =
# extractRC, spef, netlist-sim" (v2, and again on the iteration-7 export):
# effortLevel medium/high/signoff REQUIRES a Quantus techfile on every active
# RC corner (IMPEXT-3491), and ASIC_QRC_TECH is opt-in and normally unset -
# so this step could never succeed in the default configuration, and both
# dependent steps (spef, and the signoff timing that reads the parasitics)
# fell over behind it. Effort now follows the techfile: medium when one is
# supplied, low otherwise. Low effort is LEF-based and perfectly adequate for
# what this flow quotes - it is what stage 05 already uses for its postRoute
# timing.
_step extractRC {
    if {[config_env ASIC_QRC_TECH {}] ne ""} {
        setExtractRCMode -engine postRoute -effortLevel medium
    } else {
        setExtractRCMode -engine postRoute -effortLevel low
        puts "INFO: no ASIC_QRC_TECH - postRoute extraction at effortLevel low (LEF-based)"
    }
    extractRC
}
_step spef {rcOut -spef [pnr_out ${RUN_TAG}_pnr.spef]}

_step timing-setup  {timeDesign -signoff       -outDir [file dirname [pnr_rpt signoff x]] -prefix signoff}
_step timing-hold   {timeDesign -signoff -hold -outDir [file dirname [pnr_rpt signoff x]] -prefix signoff}
_step report-setup  {report_timing -late  -max_paths 50 > [pnr_rpt signoff setup.rpt]}
_step report-hold   {report_timing -early -max_paths 50 > [pnr_rpt signoff hold.rpt]}
_step report-census {report_timing -late -max_paths 1000 -path_type summary > [pnr_rpt signoff census.rpt]}
_step report-power  {report_power  > [pnr_rpt signoff power.rpt]}
_step report-area   {report_area   > [pnr_rpt signoff area.rpt]}
_step report-summary {summaryReport -noHtml -outfile [pnr_rpt signoff summary.rpt]}

# ---------------------------------------------------------------------------
# Deliverables
# ---------------------------------------------------------------------------
_step netlist {saveNetlist [pnr_out ${RUN_TAG}_pnr.v]}

# Netlist for gate-level simulation. saveNetlist already omits physical-only
# instances (filler/decap/tap) by default - verified on iter16b's export
# (0 FILLER/DECAP/TAP in _pnr.v) - so the only difference from _pnr.v is the
# absence of leaf-cell definitions (the sim binds the PDK's Verilog models).
# "-physicalInsts" was never a saveNetlist option (IMPTCM-48 on every export
# since armC); fixed 2026-09-04.
_step netlist-sim {saveNetlist -excludeLeafCell [pnr_out ${RUN_TAG}_pnr_sim.v]}

_step sdf {write_sdf [pnr_out ${RUN_TAG}_pnr.sdf]}

# Constraints AS IMPLEMENTED, one per analysis view (2026-09-01). This is the
# standard signoff handoff artifact: it captures everything the flow changed
# interactively after the source SDC was read - the 4.000 ns clock, the
# propagated-clock switch, the post-CTS uncertainties - so signoff can either
# consume it directly or diff it against the source-constraint replay
# (signoff/tempus/sta.tcl does the latter; the first Tempus run signed off
# ideal-clock precisely because this handoff did not exist).
_step sdc-setup {write_sdc -view setup_view [pnr_out ${RUN_TAG}_setup.sdc]}
_step sdc-hold  {write_sdc -view hold_view  [pnr_out ${RUN_TAG}_hold.sdc]}

_step def {defOut -floorplan -netlist -routing [pnr_out ${RUN_TAG}_pnr.def]}

# GDS. The stream-out map file is PDK-specific; if this errors, that is the
# thing to go find - it is not a design problem.
set GDS_MAP [config_env ASIC_GDS_MAP {}]
# -merge: without it streamOut writes ABSTRACT geometry only - routing, vias,
# and empty references to cell structures that are not in the file. The v2 GDS
# (2026-08-29) was written that way: 57 structures, zero sky130_fd_sc_hd cells,
# no macro layout - fine as a routing snapshot, useless for DRC/LVS/tapeout.
# Merging the std-cell and SRAM-macro library GDS makes the file the real mask
# geometry. Override the list with ASIC_GDS_MERGE (space-separated paths).
set GDS_MERGE [config_env ASIC_GDS_MERGE ""]
if {$GDS_MERGE eq ""} {
    set GDS_MERGE {}
    foreach _g [list \
        /apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds \
        /apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_sram_macros/gds/sram_1rw1r_32_256_8_sky130.gds] {
        if {[file readable $_g]} { lappend GDS_MERGE $_g } else { pnr_note "GDS merge source missing (skipped): $_g" }
    }
}
_step gds {
    set _opts [list -libName $TOP -mode ALL]
    if {$GDS_MAP ne "" && [file readable $GDS_MAP]} { lappend _opts -mapFile $GDS_MAP }
    if {[llength $GDS_MERGE]} { lappend _opts -merge $GDS_MERGE }
    streamOut [pnr_out ${RUN_TAG}.gds] {*}$_opts
    pnr_note "GDS written (map: [expr {$GDS_MAP ne "" ? $GDS_MAP : "NONE"}],\
              merged: [llength $GDS_MERGE] library GDS files)"
}

saveDesign [pnr_ckpt 06_final.enc]
if {[llength $_failed]} {
    pnr_note "stage 06: FAILED STEPS = $_failed (rerun by hand from 06_final.enc)"
}
pnr_note "stage 06 (export) complete - deliverables in $PNR_OUT_DIR"
