# OpenRAM PRODUCTION macro config - 16KB cache, ASSOC=2.
#
# Data store is banked per way per line-word, so one bank = (sets x 32b) and
# sets = 1024/ASSOC. This macro is that bank: 512 x 32, 1RW+1R, byte-masked,
# instantiated 8 times at ASSOC=2.
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
num_words = 512
num_rw_ports = 1
num_r_ports = 1
num_w_ports = 0
write_size = 8            # byte-maskable, matching the vendored macro

tech_name = "sky130"

# ngspice, NOT hspice: the open_pdks sky130 models are ngspice dialect.
analytical_delay = False
spice_name = "ngspice"

process_corners = ["SS"]
supply_voltages = [1.60]
temperatures = [100]
use_specified_corners = [("SS", 1.60, 100)]

# Layout verification is a later phase (netgen not built on this server yet).
check_lvsdrc = False

output_path = "macros_out/32x512"
output_name = "openram_sram_1rw1r_32x512_8"
