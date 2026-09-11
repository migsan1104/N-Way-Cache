# macro_clk_probe.tcl (2026-09-10, user: "can we invert the clock?"). READ-ONLY.
# A read-port-only inversion (clk1 = ~clk) moves the half cycle from the
# dout1 -> capture path onto the rindex_rep_r -> addr1 path (latency-neutral
# because addr1 is registered). Report, at the restored checkpoint's SDC:
#  (1) worst late path INTO every macro input pin class (addr1, addr0, din0, csb0/web0)
#  (2) worst late path FROM dout1 (the wall) and FROM dout0 (unused)
#  (3) their period-independent data-path delays, so the half/full-cycle trade can be
#      computed for any period.  Knob: ASIC_PROBE_SRC (05_clkskew8.enc). Output: reports/macro_clk/.
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_PROBE_SRC 05_clkskew8.enc]
pnr_restore_stage $_src
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne ""} { foreach _c {rc_slow rc_fast} { catch {update_rc_corner -name $_c -qx_tech_file $_qrc} } }
setAnalysisMode -analysisType onChipVariation -cppr both
proc pb {msg} { puts "MCLK $msg"; pnr_note "MCLK $msg" }
set D [file dirname [pnr_rpt macro_clk x]]
pb "src=$_src period=[get_property [get_clocks clk] period]"
foreach {tag pat} {addr1 *u_sram/addr1* addr0 *u_sram/addr0* din0 *u_sram/din0* csb0 *u_sram/csb0 web0 *u_sram/web0 clk1 *u_sram/clk1 clk0 *u_sram/clk0} {
    set pins [get_pins -quiet $pat]
    pb "$tag pins: [sizeof_collection $pins]"
    if {[sizeof_collection $pins] == 0} { continue }
    if {$tag eq "clk1" || $tag eq "clk0"} {
        # clock arrival at the macro clock pins (late view)
        set lat {}
        foreach_in_collection p $pins { if {[catch {lappend lat [format %.3f [get_property $p clock_arrival_time_max_rise]]}]} { break } }
        # fallback if property missing
        if {[llength $lat]} { pb "$tag arrival(max rise): min [lindex [lsort -real $lat] 0] max [lindex [lsort -real $lat] end]" } else { pb "$tag arrival: property unsupported" }
        continue
    }
    report_timing -late -to $pins -max_paths 5 -path_type full_clock -format {instance cell arc delay arrival required} > $D/to_${tag}_setup.rpt
    report_timing -early -to $pins -max_paths 3 -path_type full_clock > $D/to_${tag}_hold.rpt
}
foreach {tag pat} {dout1 *u_sram/dout1* dout0 *u_sram/dout0*} {
    set pins [get_pins -quiet $pat]
    pb "$tag pins: [sizeof_collection $pins]"
    if {[sizeof_collection $pins] == 0} { continue }
    report_timing -late -from $pins -max_paths 5 -path_type full_clock -format {instance cell arc delay arrival required} > $D/from_${tag}_setup.rpt
}
pb "DONE"
exit
