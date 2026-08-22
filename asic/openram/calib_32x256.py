# OpenRAM Phase-0 CALIBRATION config (2026-08-21).
#
# Regenerates the exact geometry of the vendored macro we already trust
# (sram_1rw1r_32_256_8_sky130: 32b x 256, 1RW+1R, byte-masked) and
# characterizes it with HSPICE at the same corner as the vendored lib
# we link (SS, 1.8V, 25C). The generated .lib is then diffed against
#   .../sky130_sram_macros/lib/sram_1rw1r_32_256_8_sky130_SS_1p8V_25C.lib
# If the arcs track, self-generated libs earn the right to be trusted at
# geometries (32x128, 32x64) and corners (ss/1.60V/100C) the vendor
# never shipped. If they don't track, the OpenRAM sub-project stops here.

word_size = 32
num_words = 256
num_rw_ports = 1
num_r_ports = 1
num_w_ports = 0
write_size = 8            # byte-maskable, matching the vendored macro

tech_name = "sky130"

# Spice-based characterization (the whole point). NOT hspice: the
# open_pdks sky130 device models are written in ngspice syntax ({l}/{w}
# parameter braces on device lines) and HSPICE rejects them at parse
# (verified 2026-08-21 - first model file, syntax error). OpenRAM's
# self-provisioned conda env ships ngspice + Xyce for exactly this
# reason; ngspice + sky130 models is the pairing the vendored libs were
# characterized with. The calibration diff, not the simulator brand, is
# the credibility instrument.
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

# Corner selection. WARNING: process_corners/supply_voltages/temperatures
# are INERT unless a second gate is set - by default OpenRAM ignores them,
# builds its corner list from a hardcoded nominal "TT", and characterizes
# TT first. That is why attempt 1 emitted a TT-named lib despite asking for
# SS. Full mechanism (and why only_use_config_corners=True crashes with an
# UnboundLocalError instead of fixing it) in asic/MACROS.md,
# "Corner-selection finding". use_specified_corners is the reliable gate:
# it takes its own branch and characterizes exactly this list.
#
# ONE corner (user decision 2026-08-21). Measured cost is ~25 min per ngspice
# sim and ~15-30 sims per corner = 6-12 h EACH, so the three-corner diff the
# default path stumbles into (TT, FF, SS at 1p8V/25C) would be a 1-2 day job.
# SS_1p8V_25C is the corner to keep: it is the lib the ASIC flow actually
# links today, so the calibration diff measures the arc we depend on.
process_corners = ["SS"]          # kept for documentation; NOT what binds
supply_voltages = [1.8]
temperatures = [25]
use_specified_corners = [("SS", 1.8, 25)]

# Timing calibration only: layout verification is a later phase
# (netgen not on server yet; DRC/LVS owed before any GDS-level claim).
check_lvsdrc = False

output_path = "calib_out"
output_name = "openram_sram_1rw1r_32x256_8_calib"
