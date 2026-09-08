set R /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/runs/20260905_iter19b_e35_fp16_die2900_straps_p3333_1v76
restoreDesign $R/checkpoints/07_vssfix.enc.dat Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1
set _qrc /ecel/UFAD/miguel.sanchez1/Cache/asic/signoff/quantus/techfiles/sky130A_nom.tch
foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} }
puts "PREUNR ==== deleting signal routing (scratch session, nothing saved)"
if {[catch {editDelete -type Signal} _m]} { puts "PREUNR editDelete failed: $_m"; catch {deleteAllRoutes} }
puts "PREUNR routed signal wires left: [llength [dbGet -e top.nets.sWires]]"
puts "PREUNR ==== preRoute extraction on UNROUTED nets (the placement/CTS estimator, factors 1.1 as in 19b)"
puts "PREUNR ==== earlyGlobalRoute (the trial route placement/CTS timing uses)"
if {[catch {earlyGlobalRoute} _m]} { puts "PREUNR earlyGlobalRoute failed: $_m"; catch {trialRoute} }
setExtractRCMode -engine preRoute
extractRC
rcOut -spef /tmp/claude-531832690/-ecel-UFAD-miguel-sanchez1-Cache/9d1fefef-0502-4415-a174-46040a19238e/scratchpad/preunrouted19b_rc_slow.spef -rc_corner rc_slow
puts "PREUNR DONE"
exit
