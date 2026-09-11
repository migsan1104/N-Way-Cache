# pgv_common.tcl - shared setup for Voltus power-grid-view generation
# (2026-09-04, first execution ever; voltus.md step 1). Values mirror the
# Innovus flow: same tech/cell LEF (project_config.tcl), same filler/decap
# lists (innovus_config.tcl), the Quantus techfile quantus.md validated.
set PDK      /apps/cds/IC618/local/opdk/share/pdk/sky130A
set SC       $PDK/libs.ref/sky130_fd_sc_hd
set TECH_LEF $SC/techlef/sky130_fd_sc_hd__nom.tlef
set CELL_LEF $SC/lef/sky130_fd_sc_hd.lef
set QRC_TCH  /ecel/UFAD/miguel.sanchez1/Cache/asic/signoff/quantus/techfiles/sky130A_nom.tch
set SPICE_SUBCKTS $SC/spice/sky130_fd_sc_hd.spice
set SPICE_MODELS  $PDK/libs.tech/ngspice/sky130.lib.spice
set SPICE_CORNER  tt
set VDD_V    1.76   ;# campaign corner supply (ss_n40C_1v76); nominal PDK is 1.8
set TEMP_C   25
set FILLER_CELLS {sky130_fd_sc_hd__fill_8 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_1}
set DECAP_CELLS  {sky130_fd_sc_hd__decap_12 sky130_fd_sc_hd__decap_8 sky130_fd_sc_hd__decap_6 sky130_fd_sc_hd__decap_4 sky130_fd_sc_hd__decap_3}
set OUT      /ecel/UFAD/miguel.sanchez1/Cache/asic/signoff/voltus/pgv
foreach f [list $TECH_LEF $CELL_LEF $QRC_TCH $SPICE_SUBCKTS $SPICE_MODELS] {
    if {![file readable $f]} { error "pgv: missing input $f" }
}
catch {setMultiCpuUsage -localCpu 16}
read_lib -lef [list $TECH_LEF $CELL_LEF]
