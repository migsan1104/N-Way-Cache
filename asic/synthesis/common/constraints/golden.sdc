# ============================================================================
# golden.sdc - the single source of timing constraints for the cache.
#
# This file is the ONLY place constraints are defined. Both the Genus and the
# Design Compiler flows read this exact file, so the two tools are guaranteed to
# be solving the same problem. Do not add constraints inline in any run script.
#
# Everything here is plain SDC. No tool-specific commands, no Tcl variables
# sourced from elsewhere - the numbers are written out literally so that the
# constraint set can be read and audited on its own.
#
# Target technology : SKY130, sky130_fd_sc_hd standard cells
# Setup corner      : sky130_fd_sc_hd__ss_100C_1v60
#                     Slow process, 1.60 V, 100 C. sky130_fd_sc_hd is a 1.8 V
#                     nominal library; 1.60 V is nominal minus roughly 10% for
#                     supply droop, which is this design's actual worst-case
#                     operating point. The lower-voltage ss corners in the PDK
#                     (down to 1.28 V) are deep-undervolt characterizations and
#                     are not a signoff point for this block.
#
#                     100 C rather than -40 C was confirmed by measurement, not
#                     assumed: interpolating inv_1 cell_fall at a 0.10 ns input
#                     slew and 0.05 pF load with the voltage held fixed at
#                     1.60 V gives 0.3782 ns at 100 C against 0.2973 ns at
#                     -40 C, so the hot corner is 1.272x slower. The same
#                     comparison at a fixed 1.40 V agrees (0.5050 ns hot vs
#                     0.4145 ns cold). There is no temperature inversion at
#                     these voltages - hot is slower, the conventional way
#                     round.
#
#                     A single corner is used at synthesis. Hold is not fixed
#                     before CTS, so a fast corner would add nothing here.
#                     Multi-corner analysis (setup at ss_100C_1v60, hold at
#                     ff_n40C_1v95) belongs in Innovus at CTS.
# ============================================================================

# ---------------------------------------------------------------------------
# Clock
# ---------------------------------------------------------------------------
# The real performance target for this block is 250 MHz, a 4.000 ns period.
#
# Synthesis is constrained to 3.500 ns instead. That 0.500 ns is a
# synthesis-stage guardband, not a target: it leaves headroom for the delay that
# place-and-route adds on top of a pre-layout estimate, and it keeps the
# optimizer working on the critical cone rather than stopping as soon as it
# scrapes past 4.000 ns.
#
# The 3.500 ns number is therefore an intermediate working constraint. It is NOT
# the signoff number. Signoff is whether the design meets the real 4.000 ns
# target post-route, with extracted parasitics and a propagated clock. Nothing
# measured at this stage settles that question.
create_clock -name clk -period 3.500 [get_ports clk]

# Pre-CTS setup margin. Stands in for the skew and jitter that a real clock tree
# will introduce but that does not exist yet at this stage of the flow. Removed
# and replaced with propagated-clock analysis once CTS has actually been run.
set_clock_uncertainty -setup 0.250 [get_clocks clk]

# Hold uncertainty is deliberately NOT set here. Hold is not fixed pre-CTS, and
# adding a hold margin now would only produce violations that the placement and
# CTS stages are responsible for closing. Add it when the flow reaches CTS.

# The clock is ideal at this stage, so it has no transition of its own. Give it
# a realistic value anyway - without one, every sequential cell is characterized
# at a zero input slew on its clock pin, which is optimistic.
set_clock_transition 0.150 [get_clocks clk]

# ---------------------------------------------------------------------------
# I/O timing
# ---------------------------------------------------------------------------
# The cache has no parent block yet, so these numbers cannot be extracted from
# a real neighbour. They are instead derived from a stated INTERFACE CONTRACT:
# every input arrives from a flop in the adjacent block, and every output is
# captured by a flop in the adjacent block, with no combinational logic on
# either side of the boundary. That contract is what the rest of the design
# already assumes - mem_resp_ready is hardwired to 1 because the surrounding
# memory hierarchy owns backpressure, and a memory controller or L2 bus
# interface registers its request inputs as a matter of course.
#
# The two directions are NOT symmetric, because they are made of different
# things. Do not "simplify" them back to one percentage.
#
# INPUT 0.700 = the CLK->Q of the driving flop. Measured, not assumed: across
# the worst-20 launch flops of the 16 KB ASSOC=4 run, CLK->Q ranges 725 ps
# (11.7 fF load) to 827 ps (34.5 fF) at this corner - essentially independent
# of load, because at ss_100C_1v60 a flop simply costs that much. 0.700 is
# therefore the tightest input assumption that can be defended, and is if
# anything slightly optimistic; set_driving_cell below adds ~113 ps on top,
# which restores the honesty. There is no headroom to recover here.
#
# OUTPUT 0.300 = the destination flop's SETUP plus wire and skew margin - NOT
# a mirror of CLK->Q, which is the launch cost and is already spent inside
# this block's own data paths. Setup measures 110-247 ps in this run's own
# reports, so 0.300 covers a registered destination with a little margin.
# The previous value here was 0.700, chosen as a flat 20% of the period; that
# silently assumed roughly half a nanosecond of combinational logic in the
# consumer, which the interface contract above says is not there. It cost
# ~400 ps on every output path and pulled port-bounded cones into a false tie
# with the design's real internal critical path.
#
# Both numbers are replaced by extracted budgets once the surrounding blocks
# exist. Note also that the FPGA out-of-context flow answers this question
# differently on purpose: openflex/rtl/Cache_timing.sv registers every port,
# so that meter sees a ZERO I/O budget and measures internal logic only. The
# two flows are deliberately not solving the same problem - signoff and
# RTL-comparison are different questions.
#
# Every port is constrained. The clock port is the only input excluded, because
# it is the timing reference rather than a data input. Note that rst IS given an
# input delay and IS timed: the reset in this design is synchronous (sampled
# inside always_ff blocks), so it is real timed logic, not an asynchronous
# control signal that could justify an exception.
set_input_delay 0.700 -clock [get_clocks clk] \
    [remove_from_collection [all_inputs] [get_ports clk]]

set_output_delay 0.300 -clock [get_clocks clk] [all_outputs]

# ---------------------------------------------------------------------------
# Boundary drive and load
# ---------------------------------------------------------------------------
# Without these, input ports are driven by an ideal zero-resistance source and
# output ports see zero load, which makes boundary paths look faster than they
# can ever be. buf_4 is a mid-strength driver and 0.05 pF is roughly the input
# capacitance of a small fanout cone - both are placeholders to be replaced by
# the real driving cell and load once the parent block exists.
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_4 -pin X \
    [remove_from_collection [all_inputs] [get_ports clk]]

set_load 0.050 [all_outputs]

# ---------------------------------------------------------------------------
# Design rule constraints
#
# Three nets, all of them real limiters for this design.
# ---------------------------------------------------------------------------
# The sky130_fd_sc_hd liberty declares default_max_transition of 5.0 ns, which is
# meaningless against a 3.5 ns clock - it would allow a single net to consume the
# entire cycle. Constrain to roughly 20% of the period instead.
set_max_transition 0.750 [current_design]

# At ss_100C_1v60 the smallest inverter is characterized out to 0.4097 pF of
# output load, so 0.100 pF sits well inside the characterized range and no delay
# reported here comes from table extrapolation. It is deliberately conservative
# rather than tuned.
# ASIC_MAX_CAP knob (2026-09-08). Default keeps the campaign value above;
# "none" removes the blanket limit so the library's per-pin max_capacitance
# governs (ss_n40C_1v76: buf_4 0.35 pF, buf_12 0.87, clkinv_16 1.56); any other
# number is a different blanket. Why: post-route on iter24a the 0.100 blanket
# reported 4,369 real max_cap violators on nets whose drivers were rated 9-16x
# higher, and the DRV fix (+3,228 buffers) doubled TNS before setup opt began.
# Read through ::env so Genus, Innovus (via pnr.sdc) and Tempus all see the
# same value; export it in the run's knobs. (dc_shell read_sdc not verified.)
set _asic_max_cap 0.100
if {[info exists ::env(ASIC_MAX_CAP)]} { set _asic_max_cap $::env(ASIC_MAX_CAP) }
if {$_asic_max_cap ne "none"} {
    set_max_capacitance $_asic_max_cap [current_design]
}

# Fanout. The library sets default_fanout_load to 1.0 but declares NO
# default_max_fanout, so without this line fanout is completely unconstrained
# and a single driver could legally be left feeding an arbitrary number of
# loads. That matters here specifically: rst is synchronous and reaches roughly
# 50k flops, so it is physically impossible to drive from one cell. Constraining
# fanout is what forces the tool to build an actual buffer tree instead of
# reporting a single-driver net that place-and-route could never implement.
#
# 20 loads per driver is a starting value chosen against the drive strengths the
# library actually offers (sky130_fd_sc_hd tops out at _16 buffers). It is not
# tuned for QoR.
# ASIC_MAX_FANOUT knob (2026-09-08): default keeps 20; "none" removes the
# rule (max_transition and the library per-pin max_capacitance then bound
# every net); any other integer is a different blanket. Paired with
# ASIC_MAX_CAP for the DRV A/B (optimizations.md E35/E37 2x2x2).
set _asic_max_fanout 20
if {[info exists ::env(ASIC_MAX_FANOUT)]} { set _asic_max_fanout $::env(ASIC_MAX_FANOUT) }
if {$_asic_max_fanout ne "none"} {
    set_max_fanout $_asic_max_fanout [current_design]
}

# ---------------------------------------------------------------------------
# Timing exceptions
# ---------------------------------------------------------------------------
# NONE.
#
# There are deliberately no set_false_path, set_multicycle_path, set_max_delay
# or set_min_delay statements in this file, and none should be added to make a
# timing report look better.
#
# An earlier version of these constraints carried
#     set_false_path -from [get_ports rst]
# which has been removed. It was not justified: rst is a SYNCHRONOUS reset in
# this RTL - every use is `if (rst)` inside an always_ff block - so its paths are
# ordinary timed logic from an input port to a register data input. Cutting them
# hid the cost of the reset fanout across roughly 50k flops instead of measuring
# it.
#
# If an exception ever becomes genuinely necessary, it goes here with a comment
# stating what structural property of the design makes the path untimed or
# multi-cycle, and it must be reviewed before being committed.
