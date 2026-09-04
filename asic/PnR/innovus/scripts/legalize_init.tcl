# legalize_init.tcl - 2026-09-03: open a route_opt checkpoint INTERACTIVELY
# (innovus -files legalize_init.tcl, no exit) so illegal placements found
# post-chain can be judged and fixed at the prompt without reloading 5 GB.
# Needs ASIC_PNR_RUN_STAMP + the chain's QRC/derate env (see winner_chain.sh).
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_LEGALIZE_SRC 05_route_opt.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
if {[catch {get_clocks vclk_io}]} {
    set _vclk_out [file dirname [pnr_rpt legalize io_vclk.txt]]
    set io_vclk_applied 0
    catch {source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/io_vclk.tcl}
    pnr_note "LEGAL io_vclk applied = $io_vclk_applied"
} else { pnr_note "LEGAL vclk_io already in the DB" }
checkPlace [pnr_rpt legalize checkplace_before.rpt]
# suspects: the 6 FE_USKC cells behind 24/35 DRC markers + the bufbuf_16s
# refinePlace could not legalize (IMPSP-2020) in the chain's hold opt
set suspects [config_env ASIC_LEGALIZE_SUSPECTS {}]
proc legal_show {i} {
    set p [dbGet -p top.insts.name $i]
    if {$p eq "" || $p == 0} { puts "LEGAL: $i NOT FOUND"; return }
    puts "LEGAL: $i cell=[dbGet $p.cell.name] pt=[dbGet $p.pt] box=[dbGet $p.box] orient=[dbGet $p.orient] status=[dbGet $p.pStatus] site=[dbGet $p.cell.site.name]"
}
foreach i $suspects { legal_show $i }
pnr_note "LEGAL INIT DONE - prompt is open"
