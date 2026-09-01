# Routing supply-vs-demand diagnostics on a routed database (DRC.md, G7-diag).
# Answers hypotheses 1 (layer supply over the hub) and 2 (pin/cell convergence)
# with numbers instead of inference.
#
#   ASIC_DIAG_DB  = path to a checkpoint .enc (its .enc.dat dir must exist)
#   ASIC_DIAG_OUT = directory for reports
#
# Every report is catch-wrapped: report-command names vary across Innovus
# builds, and one unknown command must not cost the batch. The session log
# captures everything the file redirects miss - keep it.
set DB  $env(ASIC_DIAG_DB)
set OUT $env(ASIC_DIAG_OUT)
file mkdir $OUT
restoreDesign ${DB}.dat Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1
puts "DIAG: restored $DB"
set _ok {} ; set _bad {}
foreach {name cmd} [list \
    congestion_overflow "reportCongestion -overflow > $OUT/congestion_overflow.rpt" \
    congestion_hotspot  "reportCongestion -hotSpot > $OUT/congestion_hotspot.rpt" \
    congest_area        "dumpCongestArea -all $OUT/congest_area.txt" \
    wire_per_layer      "reportWire $OUT/wire.rpt" \
    density_map         "reportDensityMap > $OUT/density_map.rpt" \
    pin_density         "reportPinDensity > $OUT/pin_density.rpt" \
    place_density       "queryPlaceDensity" \
    route_summary       "reportRoute > $OUT/route_summary.rpt" \
    track_usage         "verify_drc -limit 10 -report $OUT/drc_probe.rpt" \
] {
    if {[catch {eval $cmd} msg]} { lappend _bad "$name: $msg" } else { lappend _ok $name }
}
set f [open $OUT/DIAG_STATUS.txt w]
puts $f "worked: [join $_ok { }]"
puts $f "failed:\n  [join $_bad "\n  "]"
close $f
puts "DIAG: done. worked=[join $_ok { }]"
exit
