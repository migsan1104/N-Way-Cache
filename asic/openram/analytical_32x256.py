# OpenRAM CONTROL experiment for the Phase-0 calibration gate (2026-08-23).
#
# Question it answers: the vendored lib
#   .../sky130_sram_macros/lib/sram_1rw1r_32_256_8_sky130_SS_1p8V_25C.lib
# reports output transitions of 2/5/18 ps into 1.7/6.9/27.6 fF, IDENTICAL to
# three decimals across all three input-slew rows, while our SPICE-characterized
# calib_out lib measures 1.1-2.4 ns on the SAME geometry at the SAME corner.
# Both netlists take dout straight out of Xbank0 with NO output buffer, so 18 ps
# into 27.6 fF (~2.2 mA) is not physically available - the suspicion is that the
# vendored lib was produced by OpenRAM's ANALYTICAL model, not by simulation.
#
# This run reproduces the same macro with analytical_delay = True and no layout.
# If its .lib carries the vendor's slew-flat tables and tiny transitions, the
# vendor lib is analytical, our SPICE numbers are the physical ones, and the
# calibration diff must be judged on the delay arcs alone.
#
# Everything else is copied verbatim from calib_32x256.py so the only variable
# is the delay model.

word_size = 32
num_words = 256
num_rw_ports = 1
num_r_ports = 1
num_w_ports = 0
write_size = 8

tech_name = "sky130"

analytical_delay = True    # THE VARIABLE UNDER TEST
netlist_only = True        # no layout: this is a model comparison, minutes not hours
use_conda = False

process_corners = ["SS"]
supply_voltages = [1.8]
temperatures = [25]
use_specified_corners = [("SS", 1.8, 25)]

# Full 3x3 grid (OpenRAM defaults) so all nine vendor table entries can be
# compared - the SPICE calibration could only afford 2x2.
load_scales = [0.25, 1, 4]
slew_scales = [0.25, 1, 8]

check_lvsdrc = False

output_path = "analytical_out"
output_name = "openram_sram_1rw1r_32x256_8_analytical"
