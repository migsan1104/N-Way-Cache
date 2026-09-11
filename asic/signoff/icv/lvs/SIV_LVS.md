# SIV_LVS.md -- IC Validator LVS groundwork for the sky130 cache (side project)

Dated log, documentation-first. Every claim is tagged:

* **[verified]** -- observed on this server on the date given (file contents, tool output).
* **[docs]** -- read in the ICV T-2022.03 manuals (`/apps/syn/icv/doc/icvlvsug.pdf`,
  `icvrefman.pdf`, `icvug1.pdf`, converted with pdftotext); function names are quoted
  from the reference manual, not invented.
* **[inferred]** -- my reading of docs + PDK files, not exercised on a layout.

Scope: only `asic/signoff/icv/lvs/`. The DRC side project (`../SIV.md`,
`../sky130_beol*.rs`, `../run_icv_drc.sh`) is untouched.

## 0. Status (2026-09-05, ~01:00)

* `sky130_lvs_min.rs` **compiles clean** with `icv -cache-only` (warnings only) [verified].
* It has **never been run on a layout**. The coordinator relayed that the installed ICV
  T-2022.03-SP3-4 asks for the `ICValidator-Manager` / `-Manager-2020` license features,
  while the server only carries `ICValidator-Manager-Apex` (+ `ICValidator2-GeometryEngine`,
  `ICValidator2-CompareEngine`), so every layout run dies with "License denied" (exit 67)
  after runset compile. icvug1.pdf ch.2 "Licensing" lists three key sets; the Apex set
  (`ICValidator-Manager-Apex` + the two engines) is the U-2022.12 scheme [docs].
  **Execution is blocked until IT installs ICV >= U-2022.12 (Apex licensing).**
  No license retries were made from this side project.
* The license-free pieces *were* exercised: `icv -cache-only` and the NetTran utility
  `icv_nettran` (netlist translation, no layout, no license checkout observed) [verified].

## 1. What an ICV LVS runset needs [docs]

Runset = PXL file, `#include <icv.rh>` mandatory (`$ICV_HOME/include/icv.rh`). Four
sections in order: SELECT, OPTIONS, ASSIGN, COMMAND (icvrefman.pdf "Function Order in
Runsets"). The functions, in the order a minimal LVS runset uses them:

| Purpose | Function (icvrefman.pdf) | Notes |
|---|---|---|
| layout in | `library(library_name=, format=GDSII, cell=)` | `-i/-f/-c` override |
| options | `run_options(lvs_netlist_flow = ICV \| SPICE, lvs_user_unit = MICRON \| METER)` | defaults ICV, MICRON |
| source netlist | `schematic(schematic_file = {{filename=, format = SPICE \| VERILOG \| ICV}}, schematic_library_file=, cell=, global_nets=, spice_settings={scale=, device_map_file=, ...}, verilog_settings={global_power=, global_ground=, ...})` | **must be called before the assign functions**, once per runset; runs NetTran internally; `-s file -sf SPICE\|VERILOG\|ICV`, `-stc cell` override |
| layers | `assign({{layer_num_range=, data_type_range=}})`, `assign_text({{...}})` | text = port labels |
| connectivity | `connect(connect_items = {{layers = {a,b,...}, by_layer = via}, ...})` | "for each entry, connectivity is established from each layer in layers to by_layer"; no by_layer = layers connect directly. Also `incremental_connect()`, `stamp()` |
| port text | `text_net(connect_sequence = cdb, text_layer_items = {{layer=, text_layer=}}, opens=, shorts=, ...)` | returns a new, texted connect database |
| substrate | `cell_extent(cell_list={"*"}) not NWELL`, or `buildsub(NWELL)` | icvlvsug.pdf ch.3 |
| device matrix | `init_device_matrix(connect_sequence = cdb)` | |
| devices | `nmos(matrix, device_name, drain, gate, source, optional_pins={{device_layer=, pin_name=, pin_type=TERMINAL\|BULK}}, schematic_devices=, ...)`, `pmos(...)`; also `resistor()`, `capacitor()`, `np()/pn()` (diodes), `npn()/pnp()`, `gendev()` | default properties `w`, `l` (icvlvsug.pdf ch.5 Table 19). The gate layer **must be in the connect database** (verified: compile error otherwise) |
| extract | `extract_devices(matrix = devs)` -> device db; `netlist(device_db = ddb)` -> `cell.net` | Elite/Base license |
| compare | `init_compare_matrix()`, `check_property(state, NMOS\|PMOS\|..., {"dev",...}, property_tolerances = {{"w"},{"l"}})`, `compare(state=, schematic=, layout=, schematic_top_cell=, layout_top_cell=, ...)` | `check_property()` "should be in any typical LVS runset" and precede `compare()`; `compare()` once per runset |
| equivalences | `lvs_options(generate_user_equivs = FULL_NAME_CASE_SENSITIVE \| ..., generate_system_equivs=, extract_devices_in_black_box_cells = true\|false)`, `equiv_options({{schematic_cell=, layout_cell=}})` | default `generate_user_equivs = NONE` |
| black box | `lvs_black_box_options(equiv_cells = {{schematic_cell=, layout_cell=}}, equate_ports=, remove_schematic_ports=, remove_layout_ports=, schematic_swappable_ports=)` | icvlvsug.pdf ch.6; can also be passed as a file with `icv -e black_box_file runset.rs`. Black-box ports are matched **by name** (text on the layout cell) |
| netlist tweaks | `merge_parallel()`, `merge_series()`, `filter()`, `short_equivalent_nodes()` | icvlvsug.pdf ch.8 |
| netlist-vs-netlist | `read_layout_netlist({{file, SPICE}})`, `map_nmos()/map_pmos()`, `init_compare_matrix(netlist_vs_netlist = FULL_RUNSET \| PARTIAL_RUNSET)` | ch.6 "Netlist-Versus-Netlist Flow" -- lets a Magic-extracted SPICE be compared by ICV without geometry |

Command line (icvug1.pdf Table 2): `icv -c <cell> -i <gds> -f GDSII -s <netlist> -sf SPICE runset.rs`;
`-C` reruns compare only, `-ex` extraction only, `-cache-only` compile only, `-host_init N` local CPUs (no `-dp` in this ICV - review 2026-09-05)
(extra licenses), `-vue` VUE output.

Where results land [docs]: `<cell>.LVS_ERRORS` in the run directory (final PASS/FAIL,
failed/passed equivalence counts, diagnostics); `<cell>.RESULTS`, `<cell>.sum`;
`run_details/<cell>_lvs.log`; `run_details/compare/<sch>_<lay>/sum.<sch_cell>.<lay_cell>`
(per-equivalence PASS/FAIL, "N potential shorted/open nets", "N missing/extra devices",
"N device(s) have mismatch property"); the layout netlist is `<cell>.net`, the translated
schematic `<cell>.sch_out`. NetTran's `-equiv` writes a skeletal equivalence file
(`equiv_options(...)` in PXL) [verified for the utility, see 3.4].

SPICE input rules that matter here [docs]: MOSFET = `Mxxx drn gate src [bulk] mname W= L= M=`;
**a SPICE netlist without `*.SCALE micron` is meter-based**; `.OPTION SCALE` is honoured;
X-cards must reference a defined `.SUBCKT` (or be mapped with `spice_settings.device_map_file` /
`icv_nettran -sp-devMap`); string parameters must be double-quoted (`topography=normal` is
only a warning, see 3.4); Verilog input: structural only, `-verilog file... -sp lib.cdl`
mixes formats in one translation (verified 3.4); supply nets via
`verilog_settings.global_power/global_ground`.

## 2. What sky130 provides to derive a deck from

### 2.1 Layer numbers [verified 2026-09-05, `libs.tech/klayout/lvs/sky130.lvs` lines 714-795; agrees with `libs.tech/klayout/tech/sky130A.map` for the BEOL]

nwell 64/20, nwell.pin 64/16, nwell.label 64/5, pwell.label **64/59** (substrate text),
pwell.pin 122/16, dnwell 64/18, diff 65/20, tap 65/44, poly 66/20, licon1 66/44, npc 95/20,
li1 67/20 (label 67/5, pin 67/16), mcon 67/44, met1 68/20 (label 68/5, pin 68/16), via 68/44,
met2 69/20, via2 69/44, met3 70/20, via3 70/44, met4 71/20, via4 71/44, met5 72/20,
nsdm 93/44, psdm 94/20, lvtn 125/44, hvtp 78/44, hvi 75/20, hvntm 125/20, capm 89/44,
capm2 97/44, areaid.sc/stdcell 81/4, coreid 81/2, diode marker 81/23, prBoundary 235/4.
All numbers the task statement listed check out.

### 2.2 Device types the PDK's machine-readable decks know [verified]

* **Magic** `sky130A.tech` `extract` section (`device mosfet ...` lines 1082-1088 and
  `device msubcircuit ...` 919-1013): `sky130_fd_pr__nfet_01v8` (magic types nfet, scnfet),
  `nfet_01v8_lvt`, `pfet_01v8` (pfet, scpfet), `pfet_01v8_lvt`, `_mvt`, `pfet_01v8_hvt`
  (pfethvt, scpfethvt), `special_nfet_01v8`, `special_pfet_01v8_hvt`, `special_nfet_latch`,
  `special_nfet_pass`, `special_pfet_latch`, `nfet_g5v0d10v5`, `pfet_g5v0d10v5`,
  `nfet_03v3_nvt`, `nfet_05v0_nvt`, `nfet_20v0*`, `pfet_20v0`, `esd_*`, `cap_var*`,
  resistors (`res_generic_po/nd/pd/l1/m1..m5`, `res_high_po*`, `res_xhigh_po*`,
  `res_iso_pw`), diodes (`diode_pw2nd_05v5*`, `diode_pd2nw_05v5*`, `_11v0`), `npn_05v5*`,
  `pnp_05v5*`, `cap_mim_m3_1/2`. Recognition for the plain devices:
  `nfet = DIFF and POLY and NSDM and-not PSDM` (cifinput l.2639), pfet analogous with PSDM,
  `pfethvt = pfetarea and HVTP and-not STDCELL`, `scpfethvt = ... and HVTP and STDCELL`
  (l.2554-2580) -- i.e. Magic tells *special/std-cell* variants apart by the `STDCELL`
  marker 81/4, not by a device layer.
* **netgen** `sky130A_setup.tcl` (`lappend devices` 155-175, 267-274, ...): same names,
  plus property rules (permute source/drain, parallel merge, `w`/`l` tolerance 0.01,
  `mult` deleted). `special_nfet_01v8` / `special_pfet_01v8_hvt` are separate device
  names (l.171-172) -- they are **not** equated to the plain ones.
* **KLayout** `sky130.lvs` (l.963-1042, 1859-1897): `ngate = nsdm & (poly & diff) - nwell -
  hvtp - psdm`; `pgate = psdm & (poly & diff) & nwell - nsdm`; `nfet_01v8 = ngate - hvi -
  lvtn (- pass/model markers)`, `nfet_01v8_lvt = ... & lvtn`, `pfet_01v8 = pgate - hvi - hvtp -
  lvtn`, `pfet_01v8_hvt = ... & hvtp`, `pfet_01v8_lvt = ... & lvtn`, 5 V devices `& hvi`.
  `extract_devices(mos4(...), {SD, G, tS, tD, tG, W})` with W = nwell for PMOS, substrate
  for NMOS. Connectivity l.1632-1679: sub-ptap, nwell-ntap, taps/psd/nsd-licon,
  poly-licon (via npc), licon-li, li-mcon, mcon-met1, met1-via1 ... met5;
  `connect_global(sub, "sky130_gnd")`. The KLayout deck has **no** `special_*` devices:
  it maps every 1.8 V std-cell NMOS to `nfet_01v8`.

### 2.3 Standard-cell source netlists [verified]

* `libs.ref/sky130_fd_sc_hd/cdl/sky130_fd_sc_hd.cdl` (1.0 MB, 437 `.SUBCKT`): one subckt
  per cell, pins alphabetical (`inv_1: A VGND VNB VPB VPWR Y`), `*.PININFO`, **M-cards**
  with short model names `nfet_01v8` (2518), `pfet_01v8_hvt` (2678), `special_nfet_01v8`
  (209, in the flop/latch cells: dfxtp, sdfxtp, dfxbp, dfstp, dfsbp, ... 67 cells),
  `special_pfet_01v8_hvt` (2); parameters `m w l mult sa sb sd topography=normal area perim`,
  **microns, but no `*.SCALE` statement**. A few cells (probe/conb wrappers) use X-cards
  of other std cells. No R/D/C cards at all: the diode cell has no device in the CDL, the
  decap cells have M-cards.
* `spice/sky130_fd_sc_hd.spice`: same cells as **X-cards** on `sky130_fd_pr__*` subckts
  (`w=650000u l=150000u`, expects `.option scale=1u`), plus `sky130_fd_pr__res_generic_po`
  (2) and `diode_pw2nd_05v5` (1). Not usable by NetTran as-is (undefined subckts).
  The `sky130_ef_sc_hd__decap_*` / `fill_*` cells exist **only** as `.spice` X-card files.
  Neither format lists `lvt` devices: **the HD library uses exactly nfet_01v8 +
  pfet_01v8_hvt (+ special_ variants)**, no lvt/hvi.
* SPICE model cards: `libs.tech/ngspice/` (not needed for LVS).

### 2.4 SRAM macro `sram_1rw1r_32_256_8_sky130` [verified]

`libs.ref/sky130_sram_macros/`: `gds/` (12.8 MB), `lef/`, `lib/`, `verilog/` (behavioral),
`spice/sram_1rw1r_32_256_8_sky130.spice` (1.0 MB, 14178 lines) = **OpenRAM transistor
netlist**, hierarchical (`dff`, `bitcell_array`, `sky130_fd_bd_sram__openram_dp_cell`, ...),
X-cards on `sky130_fd_pr__pfet_01v8` (89 lines), `nfet_01v8` (81), `special_nfet_latch` (30),
`special_nfet_01v8` (9), `special_pfet_pass/latch` (4+4), `W=3 L=0.15` in microns.
Top `.SUBCKT` at line 14045: 32 din0, 8 addr0, 4 wmask0, csb0/1, web0, clk0/1, addr1, dout0,
dout1, vdd, gnd. NetTran on it **fails** (rc=33, `Cell 'sky130_fd_pr__pfet_01v8' is not
defined`) unless the X-card models are mapped to devices [verified 3.4]. The bitcells use
layers 22/21, 22/22, 33/42, 33/43, 66/83 that no PDK deck assigns [verified in the merged GDS].
In the merged signoff GDS the macro's pin **texts sit on 70/16 (met3 pin: vdd/gnd, 4600) and
71/16 (met4 pin: dout1[24] ..., 733)**, i.e. on the *pin* datatype, not on the `/5` label
datatype the std cells use; 5 internal texts on 69/20.

## 3. The smallest experiment: sky130_fd_sc_hd__inv_1

### 3.1 The cell [verified with klayout 0.30.12, `~/.local/bin/klayout -b`]

`libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds` holds the whole library in one file
(4.2 MB); ICV selects the cell with `-c sky130_fd_sc_hd__inv_1`. Layers in inv_1:
nwell 64/20, diff 65/20 (2), poly 66/20 (2), licon 66/44 (11), li1 67/20 (6), mcon 67/44 (6),
met1 68/20 (2), nsdm, psdm, hvtp, npc, stdcell 81/4, pin shapes 67/16 68/16 64/16 122/16.
**Texts: A, Y on 67/5; VGND, VPWR on 68/5; VPB on 64/5; VNB on 64/59.** No tap (65/44)
inside the cell -- the bulk pins are only labels on nwell / substrate. nand2_1 is identical
in kind (B added). CDL: `MMIN1 Y A VGND VNB nfet_01v8 w=0.65 l=0.15`,
`MMIP1 Y A VPWR VPB pfet_01v8_hvt w=1.0 l=0.15` -- so even the simplest cell needs the
**hvtp** recognition, not plain `pfet_01v8`.

### 3.2 `sky130_lvs_min.rs` (this directory)

Layer assigns for nwell/diff/tap/poly/licon/li1/mcon/met1/nsdm/psdm/lvtn/hvtp and the four
text layers; `psub = cell_extent({"*"}) not nwell`; device layers as in 2.2 (`ndev = diff &
nsdm - nwell`, `pdev = diff & psdm & nwell`, gates, sd, taps, `ngate_01v8 = ngate - lvtn`,
`pgate_01v8_hvt = pgate & hvtp`, `pgate_01v8 = pgate - hvtp - lvtn`); `connect()` with
poly/gates direct, poly-li1 and sd/taps-li1 by licon, li1-met1 by mcon, ntap-nwell,
ptap-psub; `text_net()` on li1/met1/nwell/psub; `nmos("nfet_01v8")`,
`pmos("pfet_01v8")`, `pmos("pfet_01v8_hvt")` with bulk pins psub/nwell (device names =
CDL model names so no `schematic_devices` mapping is needed); `extract_devices()`,
`netlist()`, `init_compare_matrix()`, `check_property(... {{"w"},{"l"}})`, `compare()`.

Compile history [verified]:
1. First compile: 3 errors `nmos(layers must be connected). Layer(s) not found in specified
   connect_sequence` -- the derived gate layers were not in `connect()`. Fixed by adding
   `{layers = {poly, ngate_01v8, pgate_01v8, pgate_01v8_hvt}}` (matches icvlvsug.pdf ch.4
   "The gate layer must be connected by using the connect() ... function").
2. Second compile: clean. Only two generic warnings at the `nmos()` line ("device settings
   use overwrite mode", "LVS reports changed since 2019.12"). Compile time 8 s, 0.63 GB.
   `run_details/` from `-cache-only` holds only `licmsg`, `run_info`, `dp_work`.

Not verifiable without a run [inferred]: that `cell_extent` includes the text-only
64/59 label so that `VNB` lands on `psub`; that untexted 67/16 / 68/16 pin polygons do no
harm (they are not assigned, so they are ignored); that `check_property` names `w`/`l` are
case-insensitive as the manual's examples suggest (`{"l"},{"w"}` vs `{"W"},{"L"}`);
that `compare()` pairs the top cells with no `lvs_options`/`equiv_options` (the manual's
NVN example relies on `schematic_top_cell`/`layout_top_cell`, which `-c`/`-stc` also set --
add `equiv_options({{"sky130_fd_sc_hd__inv_1","sky130_fd_sc_hd__inv_1"}})` if the first
real run reports "no equivalence").

### 3.3 The source netlist `runs/inv_1/sky130_fd_sc_hd__inv_1.cdl` [verified]

Verbatim `.SUBCKT ... .ENDS` cut from the PDK CDL with **`*.SCALE micron` prepended**
(without it NetTran/ICV read `w=0.65` as 0.65 m -- icvlvsug.pdf "*.SCALE"). NetTran accepts
it: `icv_nettran -sp sky130_fd_sc_hd__inv_1.cdl -outName inv_1.nt -equiv inv_1.equiv`
-> `{inst MMIN1=nfet_01v8 {TYPE MOS} {prop W=0.65 L=0.15 M=1 ...} {pin Y=DRN A=GATE VGND=SRC
VNB=BULK}}`, warnings only: duplicate multiplier `m`/`mult` ("MULT will be retired"), and
`Attribute "TOPOGRAPHY" ... Undefined parameter "normal"` (kept as string, harmless).

### 3.4 License-free NetTran probes (`runs/nettran_probe/`) [verified 2026-09-05]

| Input | Result |
|---|---|
| whole `sky130_fd_sc_hd.cdl` + `*.SCALE micron` | rc 0, 437+1 cells, 18369-line ICV netlist, same 3 warning kinds x 5295 |
| `sram_1rw1r_32_256_8_sky130.spice` | **rc 33**: every X-card `Cell 'sky130_fd_pr__*' is not defined` |
| iter16b `Cache_16384B_assoc4_sram_pnr.v` (993,795 lines, 250,938 instances, 226 cell types) `-verilog` + CDL `-sp` | rc 0, 67 MB ICV netlist; SRAM module undefined (only bus-index warnings); all 225 std-cell types found in the CDL; **every instance got 4 dummy pins** (`Dummy pin 'icv_floatnet_N' connected to the port 'VPWR'/'VGND'/'VPB'/'VNB'`, 27507 x 4 for inv_2 alone): the P&R Verilog connects no supply pins at all |
| same + `sram_bb_stub.cdl` (port-only `.SUBCKT` cut from the OpenRAM spice header) | rc 0, macro defined with its 110 ports, 443 equivalence lines |

So the **source netlist for full-chip ICV LVS is one NetTran call**:
`icv_nettran -verilog <pnr.v> -sp sky130_fd_sc_hd_micron.cdl sram_bb_stub.cdl -outName design.nt`
(or the same three files in `schematic()`), provided the Verilog carries the physical cells
(see 4.6). The big `.nt` outputs were deleted after the probe (67 MB each); rerun the
commands in `nettran_*.log` to regenerate.

### 3.5 Did the cell match?

**Not run** (license, section 0). The runset is compile-clean; the first real run is
`README.md` step 3.

## 4. Sizing the real job (16 KB 4-way cache, iter16b GDS = 404 MB, 3.04 M top-level instances)

| # | Item | What is missing | Effort (once ICV runs) |
|---|---|---|---|
| 4.1 | **Tool** | ICV with Apex-compatible licensing (>= U-2022.12). Nothing below can be tested before that. | IT ticket; unknown |
| 4.2 | Device families | HD library needs only `nfet_01v8`, `pfet_01v8_hvt`, `special_nfet_01v8`, `special_pfet_01v8_hvt`. The runset already covers the first two. The `special_*` ones are not geometrically distinct (KLayout maps them to the plain devices; Magic uses the STDCELL marker); easiest is `schematic(remove_devices)`-free renaming: `nmos(..., schematic_devices = {{device_name="nfet_01v8"},{device_name="special_nfet_01v8"}})` [inferred from the `schematic_devices` argument], or a CDL `sed`. No lvt/hvi/5 V devices, no R/C/BJT in the std cells. `sky130_fd_sc_hd__diode_2` has **no** device in the CDL but has diode marker 81/23 in GDS -- extract nothing on 81/23 (matches CDL) | 0.5 day |
| 4.3 | Taps / wells / substrate | tapvpwrvgnd_1 (153,806 in GDS) is device-less; ptap-psub and ntap-nwell are in the runset. Substrate method: `cell_extent : not` is fine for a std-cell die; `buildsub` if the macros isolate substrate regions. Verify power texts: **the top cell of the signoff GDS has no text at all** (pin polygons on 68/16..71/16, 0 texts) -> Innovus streamOut must write pin names (the PDK `sky130A.map` has `NAME met1/LABEL,met1/LEFPIN 68 5` rows; the export map used did not). Without text, ICV can still compare the top cell topologically but power/ground and top ports are unnamed | 0.5 day + a GDS re-export |
| 4.4 | Full BEOL connectivity | add via/met2 ... via4/met5 to `connect()` (the DRC runset already assigns them); `M1M2_PR`/`L1M1_PR` etc. are Innovus via cells (944k + 772k instances) -- pure geometry, no special handling | 0.25 day |
| 4.5 | **SRAM black box** | Layout: `lvs_black_box_options(equiv_cells = {{"sram_1rw1r_32_256_8_sky130"}})` + `lvs_options(extract_devices_in_black_box_cells = false)` so the 16 x ~156k-instance macro hierarchies are not extracted; ports come from text, so `assign_text` **70/16 and 71/16** and `text_net` on met3/met4 (2.4). Schematic: `sram_bb_stub.cdl` (3.4). Bus names `din0[31]` vs Verilog `din0[31]` -- same string, but check `*.BUSDELIMITER` if NetTran renames. The bitcell layers 22/33/66-83 are ignored by not assigning them. Alternative full-macro compare would need a device map for the OpenRAM X-cards (`spice_settings.device_map_file`) and the `special_nfet_latch/pass` recognition (Magic: `npd`, `npass` types) -- not worth it, the vendor GDS is golden | 1 day |
| 4.6 | Source netlist | `*_pnr.v` **has no supply connections** (3.4: 4 floating pins per instance) -> either `schematic(global_nets = {"VPWR","VGND","VPB","VNB"})` / `verilog_settings = {global_power="VPWR", global_ground="VGND"}` [docs, icvlvsug.pdf "Defining Global Supply Nets"] plus a `.GLOBAL` line in the CDL wrapper, or re-export with `saveNetlist -includePowerGround`. It also **lacks the physical cells**: the GDS has 252k decap_3/6/12 (they have M-cards in the CDL -> would be "extra devices in layout"), 197k fill_2, 154k taps, 8 diode_2. Re-export with `saveNetlist -includePhysicalCells` (or accept decaps via `filter()` on floating-gate devices -- risky). Translation itself is proven (3.4): Verilog + micron CDL + macro stub; set `verilog_settings.global_power/global_ground` if VPWR/VGND are not module ports | 0.25 day + P&R re-export |
| 4.7 | Runtime / capacity | 404 MB GDS, 3 M placements, ~250k std cells (~2 M transistors) is small for ICV; single-core is allowed by the license set; expect < 1 h per pass [inferred] | -- |
| 4.8 | Debug loop | first runs will show text shorts/opens (`text_net(report_errors)`), bulk-pin issues (VNB/VPB on label-only nets, see the NetTran dummy-pin warnings), and property tolerances (`check_property` defaults are exact) | 1-2 days |

**Feasible in a week?** The runset work (4.2-4.6) is about 3-4 days for someone at the
keyboard, and the std-cell library CDL, the P&R Verilog and the macro stub are all proven
to translate. But the answer is **no** as things stand, for one non-technical reason:
the installed ICV cannot start a layout run on this server. If IT installs a U-2022.12+
ICV in the first day or two, single-cell LVS the same day and a first full-chip PASS/FAIL
by the end of the week are realistic; a clean PASS also needs the two upstream fixes
(GDS pin text, netlist with physical cells), which are P&R export settings, not LVS work.
Until then, the Magic+netgen flow in `../../lvs/` remains the only executable LVS.

## 5. Log

* 2026-09-05 00:40 -- created `icv/lvs/`; converted the three ICV manuals to text in the
  scratchpad; read lvs.md / run_lvs_bb.sh / the DRC agent's runset for the command style.
* 00:45 -- PDK inventory (2.x); klayout dump of inv_1 / nand2_1 layers and texts (3.1).
* 00:55 -- first `icv -cache-only`: 3 "layers must be connected" errors (3.2).
* 00:56 -- fixed; compile clean. `icv_nettran` on the one-cell CDL OK (3.3).
* 00:57-01:00 -- NetTran probes on full CDL, SRAM spice, P&R Verilog (+stub) (3.4);
  klayout scan of the iter16b GDS: no top-level text, macro texts on /16, physical cells
  present in GDS but not in the Verilog (4.3, 4.5, 4.6).
* 01:00 -- coordinator: ICV layout runs are license-blocked (exit 67); no run attempted.
* 01:07 -- condensed the three 218 MB NetTran logs (one warning per instance) to unique-message
  summaries; tree is 4 MB. The condensed log shows all supply pins floating in the P&R Verilog (4.6).


Review 2026-09-05 (../review/REVIEW_2026-09-05.md, item A7): the Magic tech-file line numbers quoted above are off (device mosfet lines are 6005-6033, device msubcircuit 5842-5997), the antenna diodes are 7 (not 8) and ARE in the Verilog, and the SRAM X-card counts 89/81/9 are substring counts (true X-cards 68/59/8). Also: the GDS holds 29,103 inv_2 placements vs 27,507 in the P&R Verilog - to be understood before any LVS is trusted.
