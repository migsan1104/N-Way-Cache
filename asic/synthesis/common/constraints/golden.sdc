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
# Budget 20% of the clock period at each boundary (0.20 * 3.500 = 0.700 ns).
# This is the standard block-level placeholder: it reserves a fifth of the cycle
# for whatever logic sits upstream and downstream of this cache in the RISC-V
# core, leaving 60% of the period for the cache itself. Replace with real
# numbers once the surrounding blocks have been budgeted.
#
# Every port is constrained. The clock port is the only input excluded, because
# it is the timing reference rather than a data input. Note that rst IS given an
# input delay and IS timed: the reset in this design is synchronous (sampled
# inside always_ff blocks), so it is real timed logic, not an asynchronous
# control signal that could justify an exception.
set_input_delay 0.700 -clock [get_clocks clk] \
    [remove_from_collection [all_inputs] [get_ports clk]]

set_output_delay 0.700 -clock [get_clocks clk] [all_outputs]

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
set_max_capacitance 0.100 [current_design]

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
set_max_fanout 20 [current_design]

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
