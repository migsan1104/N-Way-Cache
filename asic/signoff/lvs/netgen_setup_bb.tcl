# netgen_setup_bb.tcl - netgen setup for the black-box LVS (run_lvs_bb.sh).
#
# Loads the PDK setup, then ignores the physical-only std cells that have
# no devices: magic extracts them as empty subcells and drops them from the
# layout netlist, while the -includePhysicalInst Verilog from Innovus lists
# them as instances (2026-09-05 run: layout 0 vs schematic fill_1 x4,
# fill_2 x196,802, tapvpwrvgnd_1 x153,805 -> "Circuit 1 contains 250940
# devices, Circuit 2 contains 250944" and unmatched classes). Decap cells
# DO carry MOS devices and are compared normally.
source /apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.tech/netgen/sky130A_setup.tcl

foreach _c {sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4
            sky130_fd_sc_hd__fill_8 sky130_fd_sc_hd__tapvpwrvgnd_1} {
    catch {ignore class $_c -circuit1}
    catch {ignore class $_c -circuit2}
}
