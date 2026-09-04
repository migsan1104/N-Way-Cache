# Step 1a: technology-only power-grid library (wire/via RC model for the
# design-level PG network). Fast; needs only the Quantus techfile.
source [file join [file dirname [info script]] pgv_common.tcl]
set_pg_library_mode -celltype techonly \
    -extraction_tech_file $QRC_TCH \
    -temperature $TEMP_C \
    -default_power_voltage $VDD_V
generate_pg_library -output $OUT/techonly
puts "PGV TECHONLY DONE -> $OUT/techonly"
exit
