# OpenRAM PRODUCTION macro config - 16KB cache, ASSOC=4.
#
# Data store is banked per way per line-word, so one bank = (sets x 32b) and
# sets = 1024/ASSOC. This macro is that bank: 256 x 32, 1RW+1R, byte-masked,
# instantiated 16 times at ASSOC=4.
# same geometry as the vendored macro; generating our own removes the x2.0 derate
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

process_corners = ["SS"]
supply_voltages = [1.60]
temperatures = [100]
use_specified_corners = [("SS", 1.60, 100)]

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
# REVISED 2026-08-24 18:4x - the first attempt of THIS grid ran 31.5 h
# without leaving the delay sweep and was killed deliberately. The reason
# for the revision is NOT runtime, it is that the grid did not cover the
# design.
#
# THE OPERATING POINT, measured (not assumed): the Genus db for run
# 20260824_133232 reports the macro read arc as
#     u_sram/clk1 -> dout1[11]   fanout 1   load 3.6 fF   delay 1011 ps
# dout1 drives exactly ONE pin. So the cache reads this macro at ~3.6 fF,
# near the BOTTOM of any sensible load axis.
#
# The old grid's lowest row was 6.89 fF. A lib whose table starts above
# the operating point does not interpolate there - the timer clamps to
# the bottom row - so the generated lib could never have replaced the
# vendored one, whose own axis starts at 1.7225 fF and does interpolate
# 3.6 correctly. That is the defect being fixed.
#
# WHY 0.5 AND NOT 0.25. The load axis is scale x tech.spice
# ["dff_in_cap"] = 6.89 fF, so:
#     0.25 -> 1.7225 fF   the KNOWN-BAD point (see the note above:
#                         dout moves before s_en, OpenRAM substitutes
#                         delay_lh, the column comes out non-monotonic).
#                         Do not re-enable it.
#     0.5  -> 3.445  fF   just BELOW the 3.6 fF operating point.
#     1    -> 6.89   fF   just above it - and the point the SS_1p8V_25C
#                         calibration also carries, so the corner ratio
#                         gen/calib stays computable at a common load.
#     4    -> 27.56  fF   the top of the vendor's own axis.
# 3.445 and 6.89 BRACKET the real load, which is the whole point, and
# 0.25 is still avoided.
#
# SLEW AXIS UNCHANGED, deliberately. Our clock transition is ~150 ps
# against a top row of 40 ps, so that axis IS extrapolating - but the
# vendored lib for this exact macro is slew-FLAT (0.494 / 0.526 / 0.654
# repeated identically across all three slew rows), i.e. this part has no
# measurable slew dependence to capture. Adding a third slew would cost
# 50% more sims for a column we already know is constant.
#
# COST: 3 loads x 2 slews = 6 sweep points, up from 4. At this corner a
# single ngspice transient runs >=30 min wall, so budget accordingly -
# and the min-period search still follows the delay sweep.
# 2026-08-26 RETUNE after the 47 h run (killed, no lib): at SS/1.6V/100C the
# min-period search converges at the 10 ns initial guess (32x64: 9.53, 32x128:
# 10.0), so every transient is 150 ns (~25 min on this netlist). Setup/hold is
# (clock slews x data slews) x 4 bisections x ~11 sims = ~180 of the ~220 sims
# with two slews. One slew -> ~45. The vendored lib is slew-flat anyway (above),
# and Wall B needs clk->dout1 access (the sweep), not input setup/hold.
# 0.5x load dropped: neither Genus nor Innovus sees a load below dff_in_cap.
# Budget: ~2 feasible + ~12 min-period + 2 leakage + 2 sweep + ~45 S/H
# = ~65 sims x ~25 min = ~27 h. Launched with -v -v so progress is logged.
load_scales = [1, 4]
slew_scales = [1]

# Layout verification is a later phase (netgen not built on this server yet).
check_lvsdrc = False

output_path = "macros_out/32x256"
output_name = "openram_sram_1rw1r_32x256_8"
