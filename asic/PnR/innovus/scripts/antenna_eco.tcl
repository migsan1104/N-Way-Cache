# Antenna ECO (winner-day toolkit, drafted 2026-09-01): dedicated pass to
# drive verifyProcessAntenna to zero on a DRC-clean database. The arms gate
# on verify_drc only - antenna is NOT in that gate - so a "clean" winner
# still owes this pass before the GDS is honestly manufacturable.
#
#   ASIC_PNR_RUN_STAMP=<winner> innovus -no_gui -files scripts/antenna_eco.tcl
#   (optional ASIC_ANTENNA_SRC=<ckpt name>, default 05_route_opt.enc)
#
# Fix mechanics: NanoRoute layer-hopping first, antenna diodes
# (sky130_fd_sc_hd__diode_2) where hopping cannot work. Diodes are new cells:
# legality + hold must be re-verified afterwards, and verify_drc must STILL
# be zero or this pass is a regression, not a fix. UNTESTED until first run.
source [file join [file normalize [file dirname [info script]]] innovus_config.tcl]
if {[dbGet -e top] eq ""} {
    pnr_restore_stage [config_env ASIC_ANTENNA_SRC 05_route_opt.enc]
}
setAnalysisMode -analysisType onChipVariation -cppr both

verifyProcessAntenna -report [pnr_rpt antenna_eco antenna_base.rpt]
# Parse the baseline the same way the passes are parsed below. A clean
# baseline means NO ecoRoute, NO refinePlace, NO optDesign: on iter16b
# (2026-09-04) the unconditional refinePlace after a 0-violation pass moved
# 46,888 instances (mean 235 um) and the following optDesign -postRoute
# escalated into a full reroute of a scrambled design.
proc _antenna_count {rpt} {
    set _f [open $rpt r]; set _t [read $_f]; close $_f
    set n -1
    if {[regexp {No Violations Found} $_t]} { set n 0 } \
    elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $_t -> n]} {
        regexp {Verification Complete\s*:\s*(\d+)\s+Violation} $_t -> n
    }
    return $n
}
set base [_antenna_count [pnr_rpt antenna_eco antenna_base.rpt]]
pnr_note "ANTENNA baseline: $base violations"

setNanoRouteMode -drouteFixAntenna true \
                 -routeAntennaCellName sky130_fd_sc_hd__diode_2 \
                 -routeInsertAntennaDiode true

set prev 999999999
for {set p 1} {$p <= 3 && $base != 0} {incr p} {
    ecoRoute -fix_drc
    verifyProcessAntenna -report [pnr_rpt antenna_eco antenna_pass${p}.rpt]
    # verifyProcessAntenna leaves its total in the report; parse it back.
    set _f [open [pnr_rpt antenna_eco antenna_pass${p}.rpt] r]
    set _t [read $_f]; close $_f
    set n -1
    # The report file ends with "Total number of process antenna violations: N";
    # the "Verification Complete: N Violations" line is log-only (found
    # 2026-09-03 on iter16b: every pass read -1). Accept both.
    if {[regexp {No Violations Found} $_t]} { set n 0 } \
    elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $_t -> n]} {
        regexp {Verification Complete\s*:\s*(\d+)\s+Violation} $_t -> n
    }
    pnr_note "ANTENNA pass $p: $n violations"
    if {$n == 0} { break }
    if {$n >= $prev} { pnr_note "ANTENNA PLATEAU: $n >= $prev"; break }
    set prev $n
    saveDesign [pnr_ckpt 05_antenna_pass${p}.enc]
}

# Diodes are new placed cells: re-check legality, hold, and geometry DRC.
# Only when something was actually inserted (baseline != 0); see note above.
if {$base != 0} {
    catch {refinePlace -preserveRouting true}
    catch {optDesign -postRoute -hold}
    catch {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt antenna_eco x]] -prefix antenna_eco}
} else {
    pnr_note "ANTENNA baseline clean - ecoRoute/refinePlace/optDesign skipped, database untouched"
}
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_eco drc_final.rpt]
set d [llength [dbGet -e top.markers]]
verifyProcessAntenna -report [pnr_rpt antenna_eco antenna_final.rpt]
pnr_note "ANTENNA ECO FINAL: verify_drc = $d (must be 0); see antenna_final.rpt"
saveDesign [pnr_ckpt 05_antenna_clean.enc]
pnr_note "ANTENNA ECO done - rerun 06_export.tcl by hand after judging both counts"
exit
