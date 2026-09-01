# OpenRAM PRODUCTION macro config - 16KB cache, ASSOC=8.
#
# Data store is banked per way per line-word, so one bank = (sets x 32b) and
# sets = 1024/ASSOC. This macro is that bank: 128 x 32, 1RW+1R, byte-masked,
# instantiated 32 times at ASSOC=8.
# the configuration that motivated the whole custom-macro effort
#
# Corner: our ASIC signoff corner, ss / 1.60 V / 100 C. This is the whole point
# of generating rather than vendoring - the PDK macros exist only at 1.8 V, which
# is why the flow carries a x2.0 derate today. A macro characterized AT the
# signoff corner needs no derate, and all five associativities then share one
# characterization method (see asic/MACROS.md).
#
# use_specified_corners is the ONLY reliable corner gate: process_corners alone
# is inert, and only_use_config_corners=True crashes (UnboundLocalError on
# nom_corner). The three list options below are set anyway because lib.py takes
# min()/max() of them before it reaches the branch. See asic/MACROS.md,
# "Corner-selection finding".
#
# UNVERIFIED at write time: 1.60 V is outside sky130 tech's supply_voltages
# [1.7, 1.8, 1.9]. No validation exists in OpenRAM (checked: supply_voltages is
# only ever read as a list), and Vvdd is just a voltage source, so it should
# simulate - confirm "Vvdd vdd 0 1.6" in the generated delay_stim.sp.

word_size = 32
num_words = 128
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

process_corners = ["SS"]
supply_voltages = [1.60]
temperatures = [100]
use_specified_corners = [("SS", 1.60, 100)]

# Load/slew grid: the 0.25 scales are DROPPED - 2x2 tables, the same grid as
# the rest of the family (rationale in gen_32x64.py / asic/MACROS.md). This
# job's first attempt (2026-08-22, full 3x3 grid, 8 h) DID complete, and is the
# run that exposed the problem: its 1.7 fF column reads 2.616 / 0.318 / 1.809 ns
# across 1.7 / 6.9 / 27.6 fF (dout moved before s_en, OpenRAM substituted
# delay_lh). That lib is archived at macros_out/32x128_fullgrid_20260822/ and
# must not be linked.
load_scales = [1, 4]
slew_scales = [1, 8]

# Layout verification is a later phase (netgen not built on this server yet).
check_lvsdrc = False

output_path = "macros_out/32x128"
output_name = "openram_sram_1rw1r_32x128_8"
