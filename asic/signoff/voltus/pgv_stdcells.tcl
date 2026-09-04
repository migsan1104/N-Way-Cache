# Step 1b: standard-cell power-grid views (Early/IR/EM), one Spectre
# simulation per cell (437 cells in sky130_fd_sc_hd). Hours.
source [file join [file dirname [info script]] pgv_common.tcl]
set_pg_library_mode -celltype stdcells \
    -power_pins  [list VPWR $VDD_V] \
    -ground_pins {VGND} \
    -bulk_power_pins  [list VPB $VDD_V] \
    -bulk_ground_pins {VNB} \
    -spice_subckts [list $SPICE_SUBCKTS] \
    -spice_models  [list $SPICE_MODELS] \
    -spice_corners [list $SPICE_CORNER] \
    -extraction_tech_file $QRC_TCH \
    -filler_cells $FILLER_CELLS \
    -decap_cells  $DECAP_CELLS \
    -temperature $TEMP_C
generate_pg_library -output $OUT/stdcells
puts "PGV STDCELLS DONE -> $OUT/stdcells"
exit
