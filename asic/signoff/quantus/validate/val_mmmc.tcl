# Single-corner MMMC for the extraction test structure. One timing lib (any),
# one RC corner: with -qx_tech_file in qrc mode, plain LEF-based otherwise.
set root $env(STDCELL_ROOT)
create_library_set -name libs -timing [list $root/lib/sky130_fd_sc_hd__ss_100C_1v60.lib]
if {$env(VAL_MODE) eq "qrc"} {
    create_rc_corner -name rc -T 25 -qx_tech_file $env(VAL_QRC)
} else {
    create_rc_corner -name rc -T 25
}
create_delay_corner -name dc -library_set libs -rc_corner rc
create_constraint_mode -name cm -sdc_files [list [file join [file dirname [file normalize [info script]]] empty.sdc]]
create_analysis_view -name av -constraint_mode cm -delay_corner dc
set_analysis_view -setup av -hold av
