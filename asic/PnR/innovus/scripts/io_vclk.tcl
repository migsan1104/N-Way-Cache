# Latency-matched virtual clock for I/O timing. Shared by the winner chain
# (before its post-route hold opt) and signoff/tempus/sta.tcl, so P&R and
# signoff see the SAME I/O model.
#
# WHY (armC, 2026-09-03): golden.sdc references the I/O budgets to the ideal
# clk edge at the port. Once the clock is propagated (~7.7 ns tree at ss),
# every input looks like it arrives ~7 ns before its capture clock, so
# optDesign -hold stuffed 715 delay cells (5.7-7.3 ns per path) into the
# input-fed flops. Under the latency-matched model those paths have +5 ns
# of hold margin; the padding cost 2.2 ns of reg2reg setup on the shared
# cpu_req_ready net (Innovus +0.699 -> Tempus -1.468) and manufactured all
# 1205 in2reg setup violations. The virtual clock carries the tree's own
# latency (the external agent is modeled as living at our clock depth),
# so hold fixing only inserts what the real requirement needs.
#
# Caller sets:
#   _vclk_out   directory for clock_latency.rpt / io_vclk.txt (must exist)
# Env knobs (same as sta.tcl documented):
#   ASIC_IO_VCLK_LATENCY   ns, or "auto" (default) = worst late network
#                          latency from report_clock_timing -type latency
#   ASIC_IO_VCLK_PERIOD    fallback period if the clock is not queryable
#   ASIC_IO_INPUT_DELAY / ASIC_IO_OUTPUT_DELAY   defaults mirror golden.sdc
# Sets io_vclk_applied to 1/0 for the caller.
#
# Latency must be CORNER-CONSISTENT (validation 2026-09-02): the external
# tree TRACKS ours, so early = late. Applying the measured ff-view early
# pits ss launch against ff capture inside one view (7.6 ns fiction); the
# measured ff early is only recorded in io_vclk.txt for the integrator.
# reg2out HOLD is deferred to integration (set_false_path -hold) because a
# single-mode SDC cannot express "same corner both sides" for it.

set io_vclk_applied 0
if {![info exists _vclk_out]} { set _vclk_out . }

set _vlat  [config_env ASIC_IO_VCLK_LATENCY auto]
set _vlate 0
set _vearly 0
set _vmeas_early 0
if {$_vlat eq "auto"} {
    report_clock_timing -type latency > $_vclk_out/clock_latency.rpt
    set _view ""
    set _f [open $_vclk_out/clock_latency.rpt r]
    # Only the data rows "<source> <network> <total> <r|f> <pin>" count. A
    # bare token scan also ate the "3" in the header's "Generated on: Thu
    # Sep 3" and won whenever the tree was shallower than the day of the
    # month (armC in Innovus: 2.961 -> "3", found 2026-09-03).
    while {[gets $_f _line] >= 0} {
        if {[regexp {Analysis View:\s+(\S+)} $_line -> _v]} { set _view $_v; continue }
        if {![regexp {^\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s} $_line -> _src _net _tot]} { continue }
        if {$_tot <= 0 || $_tot >= 50} { continue }
        if {[string match *hold* $_view]} {
            if {$_tot > $_vearly} { set _vearly $_tot }
        } else {
            if {$_tot > $_vlate}  { set _vlate  $_tot }
        }
    }
    close $_f
    if {$_vearly == 0} { set _vearly $_vlate }
    set _vmeas_early $_vearly
    set _vearly $_vlate
    set _vlat $_vlate
    if {$_vlat == 0} {
        puts "IO_VCLK WARN: could not auto-measure clock latency - I/O vclk NOT applied; port groups remain latency-skewed"
    }
} else {
    set _vlate  $_vlat
    set _vearly [config_env ASIC_IO_VCLK_LATENCY_EARLY $_vlat]
}
if {$_vlat > 0} {
    set_interactive_constraint_modes [all_constraint_modes -active]
    set _per ""
    # SIGNOFF_PERIOD (Tempus what-if, sta.tcl) must win: on 2026-09-04 the
    # queried period came back 4.0 after the SDC copies said 3.0, the
    # virtual clock stayed at 4 ns against a 3 ns core clock, and Tempus
    # timed the 3:4 edge pairing (a 1 ns window) - every I/O group "failed".
    if {[info exists ::env(SIGNOFF_PERIOD)] && $::env(SIGNOFF_PERIOD) ne ""} {
        set _per [expr {double($::env(SIGNOFF_PERIOD))}]
    } else {
        catch {set _per [get_property [get_clocks clk] period]}
    }
    if {$_per eq ""} { catch {set _per [get_attribute [get_clocks clk] period]} }
    if {$_per eq "" || ![string is double -strict $_per]} {
        set _per [config_env ASIC_IO_VCLK_PERIOD 4.000]
        puts "IO_VCLK WARN: clock period not queryable - using $_per from ASIC_IO_VCLK_PERIOD/default"
    }
    set _idly [config_env ASIC_IO_INPUT_DELAY  0.700]
    set _odly [config_env ASIC_IO_OUTPUT_DELAY 0.300]
    create_clock -name vclk_io -period $_per
    set_clock_latency -source -late  $_vlate  [get_clocks vclk_io]
    set_clock_latency -source -early $_vearly [get_clocks vclk_io]
    set _inports [remove_from_collection [all_inputs] [get_ports clk]]
    set_input_delay  $_idly -clock vclk_io $_inports
    set_output_delay $_odly -clock vclk_io [all_outputs]
    set_false_path -hold -to [all_outputs]
    set io_vclk_applied 1
    puts "IO_VCLK: vclk_io period $_per latency late $_vlate / early $_vearly (in $_idly / out $_odly); reg2out hold deferred to integration"
    set _vf [open $_vclk_out/io_vclk.txt w]
    puts $_vf "vclk_io latency_late=$_vlate latency_early=$_vearly (correlated model; measured ff-early $_vmeas_early) period=$_per input_delay=$_idly output_delay=$_odly reg2out_hold=deferred"
    close $_vf
}
