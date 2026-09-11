# antenna_attach.tcl (2026-09-09). Explicit diode attach for the process-antenna
# violations the router's own insertion (antenna_eco.tcl, ecoRoute -fix_drc)
# plateaus on: iter26b 53 -> 53, 19b 122 -> 122, all with D.Area 0.0000 in the
# report, i.e. no diode ever landed on the pin. Parse the verifyProcessAntenna
# report, attachDiode on every listed (inst, pin), legalize, ecoRoute the
# touched nets, re-verify (up to 3 passes), then hold opt + DRC + timing.
# Knobs: ASIC_ANTENNA_ATTACH_SRC (05_route_opt.enc = the chain's HOLDCLEAN
# state), ASIC_ANTENNA_ATTACH_RPT (report to parse), ASIC_QRC_TECH.
# Saves 05_antenna_attach.enc; reports in reports/antenna_attach/.
set _here [file normalize [file dirname [info script]]]
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
set _src [config_env ASIC_ANTENNA_ATTACH_SRC 05_route_opt.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
set _vclk_out [file dirname [pnr_rpt antenna_attach io_vclk.txt]]
set io_vclk_applied 0
if {[catch {source [file join $_here io_vclk.tcl]} _m]} { pnr_note "ATTACH io_vclk failed: $_m" }
proc ax {msg} { puts "ATTACH $msg"; pnr_note "ATTACH $msg" }
ax "src=$_src io_vclk=$io_vclk_applied"
# sanity timing of the source BEFORE touching anything (the chain's antenna
# session printed setup -6.0 / hold -1.76 mid-opt; 19b's printed -52 / -25)
catch {timeDesign -postRoute       -outDir [file dirname [pnr_rpt antenna_attach x]] -prefix before}
catch {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt antenna_attach x]] -prefix before}
set DIODE sky130_fd_sc_hd__diode_2
proc parse_rpt {f} {
    set pins {}
    set fh [open $f r]
    while {[gets $fh l] >= 0} {
        if {[regexp {^  (\S+)\s+\((\S+)\)\s+(\S+)\s*$} $l -> inst cell pin]} { lappend pins [list $inst $pin] }
    }
    close $fh
    return [lsort -u $pins]
}
set rpt [config_env ASIC_ANTENNA_ATTACH_RPT [pnr_rpt antenna_eco antenna_pass2.rpt]]
setNanoRouteMode -drouteFixAntenna true -routeAntennaCellName $DIODE -routeInsertAntennaDiode true
set prev 999999
for {set p 1} {$p <= 3} {incr p} {
    set pins [parse_rpt $rpt]
    ax "pass $p: [llength $pins] pins to attach from [file tail $rpt]"
    if {![llength $pins]} break
    set ok 0; set bad 0
    foreach ip $pins {
        lassign $ip inst pin
        if {[catch {attachDiode -diodeCell $DIODE -pin $inst $pin} m]} { incr bad; if {$bad <= 3} { ax "attachDiode failed on $inst/$pin: $m" } } else { incr ok }
    }
    ax "pass $p: attached $ok, failed $bad"
    catch {refinePlace -preserveRouting true}
    catch {ecoRoute}
    set rpt [pnr_rpt antenna_attach antenna_pass${p}.rpt]
    verifyProcessAntenna -report $rpt
    set fh [open $rpt r]; set t [read $fh]; close $fh
    set n -1
    if {[regexp {No Violations Found} $t]} { set n 0 } elseif {![regexp {Total number of process antenna violations:\s*(\d+)} $t -> n]} { regexp {Verification Complete\s*:\s*(\d+)\s+Violation} $t -> n }
    ax "pass $p: antenna violations = $n"
    if {$n == 0} break
    if {$n >= $prev} { ax "PLATEAU $n >= $prev"; break }
    set prev $n
}
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true
if {![config_env ASIC_CTS_USEFUL_SKEW 0]} { catch {setOptMode -usefulSkew false}; catch {setOptMode -usefulSkewCCOpt none}; catch {setAnalysisMode -usefulSkew false} }
catch {optDesign -postRoute -hold}
clearDrc
verify_drc -limit 100000 -report [pnr_rpt antenna_attach drc_final.rpt]
set d [llength [dbGet -e top.markers]]
verifyProcessAntenna -report [pnr_rpt antenna_attach antenna_final.rpt]
foreach _r {
    {timeDesign -postRoute       -outDir [file dirname [pnr_rpt antenna_attach x]] -prefix after}
    {timeDesign -postRoute -hold -outDir [file dirname [pnr_rpt antenna_attach x]] -prefix after}
} { catch {eval $_r} }
ax "FINAL: verify_drc = $d, antenna = $n; checkpoint 05_antenna_attach.enc"
saveDesign [pnr_ckpt 05_antenna_attach.enc]
