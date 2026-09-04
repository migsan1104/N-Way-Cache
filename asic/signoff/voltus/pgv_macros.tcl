# pgv_macros.tcl - macro power-grid view for the OpenRAM SRAM from LEF pin
# geometry only (-use_lefonly_for_detailedview_generation), because the
# Spectre path is blocked by ngspice-only sky130 models. Untested form;
# first run 2026-09-04. If it works, the 16 macros' ~157 mA joins the solve.
source [file join [file dirname [info script]] pgv_common.tcl]
set MACRO_LEF /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/lef/sram_1rw1r_32_256_8_sky130.lef
read_lib -lef [list $MACRO_LEF]
set fl [open $OUT/macros.list w]; puts $fl "sram_1rw1r_32_256_8_sky130"; close $fl
set_pg_library_mode -celltype macros \
    -cell_list_file $OUT/macros.list \
    -power_pins  [list vdd $VDD_V] \
    -ground_pins {gnd} \
    -extraction_tech_file $QRC_TCH \
    -use_lefonly_for_detailedview_generation true \
    -temperature $TEMP_C
generate_pg_library -output $OUT/macros
puts "PGV MACROS DONE -> $OUT/macros"
exit
