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

# Spice-based characterization (the whole point) via HSPICE
# (/apps/syn/hspice, license smoke-tested 2026-08-21).
analytical_delay = False
spice_name = "hspice"

# Match the vendored lib's corner exactly for the calibration diff.
process_corners = ["SS"]
supply_voltages = [1.8]
temperatures = [25]

# Timing calibration only: layout verification is a later phase
# (netgen not on server yet; DRC/LVS owed before any GDS-level claim).
check_lvsdrc = False

output_path = "calib_out"
output_name = "openram_sram_1rw1r_32x256_8_calib"
