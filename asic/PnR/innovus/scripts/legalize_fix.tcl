# legalize_fix.tcl - 2026-09-03, iter16b. CTS useful-skew inserted six
# sky130_fd_sc_hd__probec_p_8 (DFT probe cells - Genus/DC exclude them, the
# Innovus dont_use list only had lpflow_*). Their met1 OBS overlaps the rails
# = 24 of the 35 residual verify_drc markers. Swap for buf_8, block the
# family, reroute the touched nets, re-verify. Source at the legalize prompt.
set _probe_cells [dbGet -e [dbGet -p head.libCells.name *__probe*].name]
foreach c $_probe_cells { setDontUse $c true }
pnr_note "LEGAL dontUse set on [llength $_probe_cells] probe lib cells"
set _insts [dbGet -e [dbGet -p2 top.insts.cell.name *__probec_*].name]
pnr_note "LEGAL probec insts to swap: [llength $_insts] -> $_insts"
foreach i $_insts { if {[dbGet -p top.insts.name $i] == 0} { error "LEGAL FAIL: $i is not an instance" } }
set _nets {}
foreach i $_insts {
    set p [dbGet -p top.insts.name $i]
    foreach n [dbGet -e $p.instTerms.net.name] { if {[lsearch -exact $_nets $n] < 0} { lappend _nets $n } }
    ecoChangeCell -inst $i -cell sky130_fd_sc_hd__buf_8
    legal_show $i
}
pnr_note "LEGAL nets touched: [llength $_nets] -> $_nets"
checkPlace [pnr_rpt legalize checkplace_after_swap.rpt]
ecoRoute
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_swap.rpt]
pnr_note "LEGAL after swap: verify_drc = [llength [dbGet -e top.markers]]"
catch {report_timing -early -max_paths 1 -path_type summary > [pnr_rpt legalize hold_after_swap.rpt]}
catch {report_timing -late -from [all_registers] -to [all_registers] -max_paths 1 -path_type summary > [pnr_rpt legalize reg2reg_after_swap.rpt]}
saveDesign [pnr_ckpt 05_legal_swap.enc]
pnr_note "LEGAL SWAP DONE"
