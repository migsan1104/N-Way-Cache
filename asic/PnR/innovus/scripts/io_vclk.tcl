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

# ---------------------------------------------------------------------------
# REFERENCE-PIN MODE (iter21, 2026-09-07). The virtual-clock latency below was
# auto-measured from a report that prints ONE pin: on iter19b it returned the
# max-skew figure (2.282 / 4.714 ns), while the boundary registers actually sit
# anywhere from 2.35 ns (FIFO pointers, the reg2out launchers) to 11 ns (tag
# arrays) at ss_100C - so reg2out and in2reg were both optimistic by ns.
# Here the I/O budgets are referenced to the PROPAGATED clock arrival at one
# boundary register's CLK pin (set_input_delay/-output_delay -reference_pin):
# the external agent is modelled as clocked exactly like our boundary flops,
# per corner, per stage, with nothing to measure. Honest only if the boundary
# registers share one insertion delay - 04_cts.tcl's io_regs skew group.
#   ASIC_IO_REF_PIN   auto (default): first existing of rst_r_reg/CLK,
#                     inreg_valid_r_reg/CLK; a pin name; or "none" (= legacy
#                     virtual clock below).
#   ASIC_IO_REG2OUT_HOLD  1 = time reg2out hold too (default 0: deferred to
#                     integration as before; the false path is kept).
#
# TWO-PORT MODE (2026-09-08). Finding: the two DUT ports live at different
# clock depths (19b, n40C: response-side launchers 0.5..8.1 ns, memory-port
# flops ~7.6 ns), so one reference pin flatters one port and punishes the
# other. When ASIC_IO_REF_PIN_MEM is set, ports matching ASIC_IO_MEM_PORTS
# are referenced to THAT pin and every other port to ASIC_IO_REF_PIN. It
# only makes each port honest if that port's own boundary flops share one
# insertion delay - sta.tcl's io_boundary.rpt is the check. Default off:
# running flows keep the single-pin model.
#   ASIC_IO_REF_PIN_MEM  "" (default, off) | auto (first existing of
#                     *MSHR_REQ_ARBITER_mem_req_write_reg/CLK,
#                     *mem_req_write_reg/CLK, *mem_req_valid_reg/CLK) | a pin
#   ASIC_IO_MEM_PORTS   port glob for the memory side (default mem_*)
# ---------------------------------------------------------------------------
set _ref [config_env ASIC_IO_REF_PIN auto]
set _ref_pin ""
if {$_ref eq "auto"} {
    foreach _cand {rst_r_reg/CLK inreg_valid_r_reg/CLK} {
        if {[catch {set _n [sizeof_collection [get_pins -quiet $_cand]]}]} { set _n 0 }
        if {$_n > 0} { set _ref_pin $_cand; break }
    }
} elseif {$_ref ne "none" && $_ref ne ""} {
    if {[catch {set _n [sizeof_collection [get_pins -quiet $_ref]]}]} { set _n 0 }
    if {$_n > 0} { set _ref_pin $_ref } else { puts "IO_VCLK WARN: ASIC_IO_REF_PIN=$_ref not found - falling back to the virtual clock" }
}
# Second reference pin for the memory port (two-port mode, header above).
set _ref_pin_mem ""
set _ref_mem [config_env ASIC_IO_REF_PIN_MEM ""]
if {$_ref_pin ne "" && $_ref_mem ne "" && $_ref_mem ne "none"} {
    if {$_ref_mem eq "auto"} {
        set _cands {*MSHR_REQ_ARBITER_mem_req_write_reg/CLK *mem_req_write_reg/CLK *mem_req_valid_reg/CLK}
    } else {
        set _cands [list $_ref_mem]
    }
    foreach _cand $_cands {
        if {[catch {set _c [get_pins -quiet $_cand]}]} continue
        if {[catch {set _n [sizeof_collection $_c]}] || $_n == 0} continue
        set _ref_pin_mem [get_object_name [index_collection $_c 0]]
        break
    }
    if {$_ref_pin_mem eq ""} { puts "IO_VCLK WARN: ASIC_IO_REF_PIN_MEM=$_ref_mem matched nothing - memory port stays on $_ref_pin" }
}
if {$_ref_pin ne ""} {
    set_interactive_constraint_modes [all_constraint_modes -active]
    set _idly [config_env ASIC_IO_INPUT_DELAY  0.700]
    set _odly [config_env ASIC_IO_OUTPUT_DELAY 0.300]
    set _inports [remove_from_collection [all_inputs] [get_ports clk]]
    set _outports [all_outputs]
    # NOTE: the exported SDC's clk source latency (Innovus update_io_latency,
    # -7.33 ns on iter19b) is removed by sta.tcl from its SDC copies; in
    # Innovus this file runs before any such latency exists.
    set _ok 1
    set _mem_pat [config_env ASIC_IO_MEM_PORTS "mem_*"]
    set _memin ""; set _memout ""
    if {$_ref_pin_mem ne ""} {
        set _memports [get_ports -quiet $_mem_pat]
        set _memin  [remove_from_collection $_memports [all_outputs]]
        set _memout [remove_from_collection $_memports [all_inputs]]
        set _inports  [remove_from_collection $_inports  $_memports]
        set _outports [remove_from_collection $_outports $_memports]
        if {[catch {set_input_delay  $_idly -clock clk -reference_pin [get_pins $_ref_pin_mem] $_memin} _m]} { set _ok 0; puts "IO_VCLK WARN: set_input_delay -reference_pin (mem) failed ($_m)" }
        if {$_ok && [catch {set_output_delay $_odly -clock clk -reference_pin [get_pins $_ref_pin_mem] $_memout} _m]} { set _ok 0; puts "IO_VCLK WARN: set_output_delay -reference_pin (mem) failed ($_m)" }
    }
    if {$_ok && [catch {set_input_delay  $_idly -clock clk -reference_pin [get_pins $_ref_pin] $_inports} _m]} { set _ok 0; puts "IO_VCLK WARN: set_input_delay -reference_pin failed ($_m)" }
    if {$_ok && [catch {set_output_delay $_odly -clock clk -reference_pin [get_pins $_ref_pin] $_outports} _m]} { set _ok 0; puts "IO_VCLK WARN: set_output_delay -reference_pin failed ($_m)" }
    if {$_ok} {
        if {![config_env ASIC_IO_REG2OUT_HOLD 0]} { set_false_path -hold -to [all_outputs] }
        set io_vclk_applied 1
        set _arr "n/a"
        foreach _attr {clock_network_latency_max_rise latency_max_rise clock_arrival} {
            if {![catch {set _v [get_property [get_pins $_ref_pin] $_attr]}] && $_v ne ""} { set _arr "$_attr=$_v"; break }
        }
        set _memnote ""
        if {$_ref_pin_mem ne ""} { set _memnote " memory-port ($_mem_pat: [sizeof_collection $_memin] in / [sizeof_collection $_memout] out) referenced to $_ref_pin_mem;" }
        puts "IO_VCLK: reference-pin mode: I/O budgets (in $_idly / out $_odly) referenced to the propagated clk at $_ref_pin ($_arr);$_memnote reg2out hold [expr {[config_env ASIC_IO_REG2OUT_HOLD 0] ? "timed" : "deferred to integration"}]"
        set _vf [open $_vclk_out/io_vclk.txt w]
        puts $_vf "mode=reference_pin ref_pin=$_ref_pin ref_pin_mem=[expr {$_ref_pin_mem eq "" ? "none" : $_ref_pin_mem}] mem_ports=[expr {$_ref_pin_mem eq "" ? "-" : $_mem_pat}] arrival=$_arr input_delay=$_idly output_delay=$_odly reg2out_hold=[expr {[config_env ASIC_IO_REG2OUT_HOLD 0] ? "timed" : "deferred"}]"
        close $_vf
        return
    }
    puts "IO_VCLK WARN: reference-pin mode unavailable in this tool - falling back to the virtual clock"
}

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
