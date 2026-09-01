# Extract the validation test structure in Innovus, once with the native
# LEF-based extractor and once through Quantus with the in-house techfile.
#
#   innovus -no_gui -files extract.tcl   with env:
#     VAL_MODE    native | qrc
#     VAL_QRC     path to sky130A_<corner>.tch   (qrc mode)
#     VAL_OUT     output directory
#     STDCELL_ROOT  (from asic/signoff/env.sh)
set mode  $env(VAL_MODE)
set out   $env(VAL_OUT)
set here  [file dirname [file normalize [info script]]]
set root  $env(STDCELL_ROOT)

set init_lef_file  [list $root/techlef/sky130_fd_sc_hd__nom.tlef $root/lef/sky130_fd_sc_hd.lef]
set init_verilog   $here/teststruct.v
set init_top_cell  teststruct
set init_design_netlisttype Verilog
set init_design_settop 1
set init_mmmc_file $here/val_mmmc.tcl
init_design

defIn $here/teststruct.def

if {$mode eq "qrc"} {
    setExtractRCMode -engine postRoute -effortLevel signoff
} else {
    setExtractRCMode -engine postRoute -effortLevel low
}
extractRC
rcOut -spef $out/teststruct_$mode.spef
puts "VALIDATE: wrote $out/teststruct_$mode.spef"
exit
