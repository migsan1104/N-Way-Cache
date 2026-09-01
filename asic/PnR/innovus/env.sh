# Pinned inputs for the staged Innovus flow.  Source this in the shell BEFORE
# launching innovus:
#     source /apps/settings
#     cd asic/PnR/innovus && source env.sh && innovus
#
# innovus_config.tcl otherwise picks the NEWEST Genus netlist, which changes
# under you as the RTL campaign runs (on 2026-08-26 it would have been the E39
# clk-inverted probe, not the frozen RTL).
_here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# RTL frozen for P&R at e35abcde (2026-08-25).
export ASIC_NETLIST=$_here/../../PPA/genus/assoc_4/runs/20260825_203024_e29ao_e35abcde_tb16_sram/netlist/Cache_16384B_assoc4_sram_mapped.v

# The netlist instantiates the 32x256 macro; project_config.tcl defaults to 0.
export ASIC_SRAM_MACRO=1

# PDK LEF names its layers m1..m4; the sky130_fd_sc_hd tech LEF calls them
# met1..met4 and init_design rejects the mismatch.  lef/ holds a copy with only
# those tokens renamed (sed 's/\bm\([1-4]\)\b/met\1/g' on the PDK file).
export ASIC_SRAM_MACRO_LEF=$_here/lef/sram_1rw1r_32_256_8_sky130.lef

# Core-to-die margin. The stage-02 ring stack needs 12um per side (2 offset +
# 4 VDD + 2 spacing + 4 VSS); the 10um default made addRing fail with IMPPP-220
# "outside the design boundary" (2026-08-27, first stage-02 run). 16 leaves
# slack for the ring plus pin access.
export ASIC_FP_CORE_MARGIN=16
unset _here

# GDS stream-out layer map (Innovus "layer purposes gdsLayer gdsDatatype" format;
# the PDK ships it under klayout/tech). Added 2026-08-28 for stage 09.
export ASIC_GDS_MAP=/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map
