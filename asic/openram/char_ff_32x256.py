# HOLD-CORNER characterization of the 32x256 macro: FF / 1.95 V / -40 C.
#
# Generated 2026-08-24 from gen_32x256.py by changing ONLY the corner and the
# output path - every other setting (ngspice-41, use_conda=False, the trimmed
# 2x2 load/slew grid and the reasons for it) is deliberately identical, so the
# two libs differ by corner alone and nothing else.
#
# WHY: Innovus MMMC needs a macro library on the HOLD side. The stdcell hold
# corner is sky130_fd_sc_hd__ff_n40C_1v95, and this matches it. Without it,
# hold analysis runs with the macros untimed, which reads as "hold is clean" -
# the failure mode that does not error, it just ships broken silicon.
# See asic/innovus/README.md, "Macro libs".
#
# SEPARATE output_path ON PURPOSE: the SS characterization of this same
# geometry is still running into macros_out/32x256. Sharing the directory would
# have the two runs overwrite each other's GDS/LEF mid-flight.
#
# OUT-OF-RANGE CORNER VALUES, same class as the SS run's 1.60 V: sky130 tech.py
# declares supply_voltages [1.7, 1.8, 1.9] and temperatures [0, 25, 100], so
# both 1.95 V and -40 C sit outside the declared lists. OpenRAM performs no
# validation on either (they are only ever read as lists), Vvdd is a plain
# voltage source and the temperature becomes a .temp card, and the "FF" corner
# IS a declared fet_library mapping to the ff model deck. Confirm the generated
# delay_stim.sp carries "Vvdd vdd 0 1.95" and a -40 .temp before trusting the
# output - the same check the SS run got.

word_size = 32
num_words = 256
num_rw_ports = 1
num_r_ports = 1
num_w_ports = 0
write_size = 8            # byte-maskable, matching the vendored macro

tech_name = "sky130"

# ngspice, NOT hspice: the open_pdks sky130 models are ngspice dialect.
analytical_delay = False
spice_name = "ngspice"

# SIMULATOR: ngspice-41 from ~/ngspice41env, NOT the revision-26 build bundled
# in OpenRAM's miniconda. Measured on the identical 150 ns stimulus:
#   ngspice-41  1482 s (24.7 min), rc=0, 15273 timepoints, 1 rejected, 48 measures
#   ngspice-26  7 h 19 m and never finished
# 26 predates the KLU solver and never engages the num_threads=3 that .spiceinit
# asks for (pinned at one core; 41 runs ~218%).
#
# use_conda=False is what makes the switch take effect. find_exe() searches
# CONDA_HOME/bin BEFORE $PATH while use_conda is true, so the bundled 26 wins
# no matter what PATH says; run_openram.sh puts ngspice41env first. Setting
# spice_exe here would NOT work - characterizer/__init__.py:25 assigns
# OPTS.spice_exe = "" and then find_exe(), overwriting any config value, the
# same inert-option trap as process_corners.
use_conda = False

process_corners = ["FF"]
supply_voltages = [1.95]
temperatures = [-40]
use_specified_corners = [("FF", 1.95, -40)]

# Load/slew grid: the 0.25 scales are DROPPED - 2x2 tables, the same grid as
# calib_32x256.py and gen_32x64.py. Two independent reasons, both found
# 2026-08-23 (full writeup in gen_32x64.py and asic/MACROS.md):
#   slew 0.25 (0.00125 ns): the s_en measure puts its TD exactly on the clock's
#     falling edge; at a 1.25 ps edge ngspice misses the crossing about half the
#     time per port (-inf -> parse failure -> assert at delay.py:1359). Killed
#     the 32x64 run and the calibration's first attempt; a coin flip, not a
#     circuit failure. No sky130 gate produces a 1.25 ps edge anyway.
#   load 0.25 (1.7 fF): dout moves before s_en ("captured precharge"), OpenRAM
#     substitutes delay_lh, and the column comes out non-monotonic
#     (32x128: 2.616 / 0.318 / 1.809 ns across 1.7 / 6.9 / 27.6 fF). Unlinkable.
# The first attempt of this job (2026-08-22 10:15, full grid) was killed after
# ~25 h in the min-period search, before either point was reached, once the
# 32x128 lib showed what the full grid produces.
load_scales = [1, 4]
slew_scales = [1, 8]

# Layout verification is a later phase (netgen not built on this server yet).
check_lvsdrc = False

output_path = "macros_out/32x256_FF"
output_name = "openram_sram_1rw1r_32x256_8"
