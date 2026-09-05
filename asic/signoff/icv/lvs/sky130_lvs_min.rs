// sky130_lvs_min.rs -- minimal SKY130A LVS runset for Synopsys IC Validator (PXL).
//
// Scope (deliberately tiny): ONE standard cell (sky130_fd_sc_hd__inv_1 / nand2_1),
// FEOL + li1/met1 connectivity, two device types (nfet_01v8, pfet_01v8_hvt), and a
// compare against the PDK CDL for that cell.  Written 2026-09-05 from the ICV
// T-2022.03 manuals (icvlvsug.pdf ch.1,3,4,6; icvrefman.pdf function pages).
// Every function name below is quoted from icvrefman.pdf; see SIV_LVS.md for the
// page-by-page trail and for what is verified vs. inferred.
//
// Usage (see README.md):
//   cd runs/inv_1 && icv -c sky130_fd_sc_hd__inv_1 -i <sky130_fd_sc_hd.gds> -f GDSII \
//       -s sky130_fd_sc_hd__inv_1.cdl -sf SPICE ../../sky130_lvs_min.rs
// Results: <cell>.LVS_ERRORS (PASS/FAIL summary), run_details/compare/<sch>_<lay>/sum.*

#include <icv.rh>

// ------------------------------------------------------------------ SELECT
library(
    library_name = "sky130_fd_sc_hd.gds",     // overridden by -i
    format       = GDSII,
    cell         = "sky130_fd_sc_hd__inv_1"   // overridden by -c
);

// ------------------------------------------------------------------ OPTIONS
run_options(
    lvs_user_unit = MICRON     // default; layout coordinates are always microns
);
error_options(
    error_limit_per_check = 1000,
    report_error_details  = true
);

// Schematic (source) netlist.  Must precede the assign functions (schematic() page).
// -s / -sf on the command line override filename / format.
sch = schematic(
    schematic_file = {{filename = "sky130_fd_sc_hd__inv_1.cdl", format = SPICE}}
);

// ------------------------------------------------------------------ ASSIGN
// GDS layer/datatype from libs.tech/klayout/lvs/sky130.lvs (verified 2026-09-05).
nwell = assign({{layer_num_range = 64,  data_type_range = 20}});
diff  = assign({{layer_num_range = 65,  data_type_range = 20}});
tap   = assign({{layer_num_range = 65,  data_type_range = 44}});
poly  = assign({{layer_num_range = 66,  data_type_range = 20}});
licon = assign({{layer_num_range = 66,  data_type_range = 44}});
li1   = assign({{layer_num_range = 67,  data_type_range = 20}});
mcon  = assign({{layer_num_range = 67,  data_type_range = 44}});
met1  = assign({{layer_num_range = 68,  data_type_range = 20}});
nsdm  = assign({{layer_num_range = 93,  data_type_range = 44}});
psdm  = assign({{layer_num_range = 94,  data_type_range = 20}});
lvtn  = assign({{layer_num_range = 125, data_type_range = 44}});
hvtp  = assign({{layer_num_range = 78,  data_type_range = 44}});

// Text (port labels).  Where the PDK std-cell GDS puts them (klayout dump, 2026-09-05):
//   A/Y on 67/5 (li1 label), VPWR/VGND on 68/5 (met1 label),
//   VPB on 64/5 (nwell label), VNB on 64/59 (pwell/substrate label).
li1_txt   = assign_text({{layer_num_range = 67, data_type_range = 5}});
met1_txt  = assign_text({{layer_num_range = 68, data_type_range = 5}});
nwell_txt = assign_text({{layer_num_range = 64, data_type_range = 5}});
psub_txt  = assign_text({{layer_num_range = 64, data_type_range = 59}});

// ------------------------------------------------------------------ COMMAND
// Substrate: "cell_extent : not" method (icvlvsug.pdf ch.3, Example 5).
sub_ext = cell_extent(cell_list = {"*"});
psub    = sub_ext not nwell;

// Device recognition layers -- same booleans as the KLayout deck (sky130.lvs
// lines 963-1030) and Magic's "device mosfet" lines, reduced to the 1.8 V devices.
ndev  = (diff and nsdm) not nwell;        // n+ diffusion outside nwell
pdev  = (diff and psdm) and nwell;        // p+ diffusion inside nwell
ngate = poly and ndev;
pgate = poly and pdev;
nsd   = ndev not ngate;                   // n source/drain
psd   = pdev not pgate;                   // p source/drain
ptap  = (tap and psdm) not nwell;         // substrate tap (none inside inv_1 itself)
ntap  = (tap and nsdm) and nwell;         // nwell tap

ngate_01v8     = ngate not lvtn;          // sky130_fd_pr__nfet_01v8
pgate_01v8     = (pgate not hvtp) not lvtn; // sky130_fd_pr__pfet_01v8 (not used by HD cells)
pgate_01v8_hvt = pgate and hvtp;          // sky130_fd_pr__pfet_01v8_hvt (all HD PMOS)

// Connectivity (connect() page: layers connected through by_layer).
cdb = connect(
    connect_items = {
        {layers = {poly, li1},            by_layer = licon},
        {layers = {nsd, psd, li1},        by_layer = licon},
        {layers = {ptap, ntap, li1},      by_layer = licon},
        {layers = {li1, met1},            by_layer = mcon},
        {layers = {ntap, nwell}},
        {layers = {ptap, psub}}
    }
);

// Apply port text to nets (text_net() page).
cdb = text_net(
    connect_sequence = cdb,
    text_layer_items = {
        {layer = li1,   text_layer = li1_txt},
        {layer = met1,  text_layer = met1_txt},
        {layer = nwell, text_layer = nwell_txt},
        {layer = psub,  text_layer = psub_txt}
    }
);

// Device extraction (init_device_matrix(), nmos()/pmos(), extract_devices(), netlist()).
// device_name = the model name used by the PDK CDL (M-cards: nfet_01v8, pfet_01v8_hvt).
devs = init_device_matrix(cdb);

nmos(
    matrix        = devs,
    device_name   = "nfet_01v8",
    drain         = nsd,
    gate          = ngate_01v8,
    source        = nsd,
    optional_pins = {{device_layer = psub, pin_name = "B", pin_type = BULK}}
);
pmos(
    matrix        = devs,
    device_name   = "pfet_01v8",
    drain         = psd,
    gate          = pgate_01v8,
    source        = psd,
    optional_pins = {{device_layer = nwell, pin_name = "B", pin_type = BULK}}
);
pmos(
    matrix        = devs,
    device_name   = "pfet_01v8_hvt",
    drain         = psd,
    gate          = pgate_01v8_hvt,
    source        = psd,
    optional_pins = {{device_layer = nwell, pin_name = "B", pin_type = BULK}}
);

ddb = extract_devices(matrix = devs);
lay = netlist(device_db = ddb);

// Compare (init_compare_matrix(), check_property(), compare()).
cmp = init_compare_matrix();
check_property(cmp, NMOS, {"nfet_01v8"},                   {{"w"}, {"l"}});
check_property(cmp, PMOS, {"pfet_01v8", "pfet_01v8_hvt"},  {{"w"}, {"l"}});

compare(
    state     = cmp,
    schematic = sch,
    layout    = lay
);
