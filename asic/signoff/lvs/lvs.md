# LVS — layout vs. schematic with Magic + netgen

Assume LVS has never been run here before. What it is, how the two-tool
pipeline works, and the two problems the shakedown already found.

## What LVS is

Layout-Versus-Schematic proves that the mask geometry implements the intended
circuit: extract a transistor/gate-level netlist *from the GDS*, then compare
it against the reference netlist (for us: the post-route Verilog from stage
06). DRC says "manufacturable"; LVS says "it is the circuit you meant". Both
must pass for a tapeout to mean anything.

## The pipeline

sky130 has no Cadence LVS deck (see `../README.md` on Pegasus), so the flow
is the open-source pair the PDK supports:

1. **Magic extract** — reads the GDS, extracts a SPICE netlist
   (`ext2spice`). Same Tcl 8.5 wrapper as DRC (`$MAGIC_RUN` in `env.sh`).
2. **netgen** — graph-isomorphism compare of that extracted SPICE against
   the reference netlist, using the PDK's `sky130A_setup.tcl` (which knows
   how to match `sky130_fd_sc_hd__*` cells to their SPICE subcircuits).
   netgen is built from source into `~/.local/bin` (2026-08-28).

```bash
bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
          <repo>/asic/signoff/lvs/run_lvs.sh [gds] [netlist.v]'
# defaults: $SIGNOFF_PNR_DIR/outputs/<tag>.gds and <tag>_pnr.v
# results in $SIGNOFF_RESULTS/lvs/: lvs.out, comp.out
```

The netlist must be the `*_pnr.v` **with** physical cells (fill/decap are in
the GDS, so they must be in the netlist side too), and the SRAM macros are
compared as **black boxes** — their GDS is the vendor cell, their transistor
netlist is not part of our standard-cell library.

## Problems found in the 2026-08-28 macro shakedown (both open)

1. **Macro name mismatch.** Our design instantiates the *rebadged* name
   `sram_1rw1r_32_256_8_sky130`, but the script pointed netgen at the PDK
   spice for `sky130_sram_1kbyte_1rw1r_32x256_8` — netgen found no cell of
   the instantiated name and gave up. Fix: the PDK also ships
   `gds/sram_1rw1r_32_256_8_sky130.gds` and matching views under the rebadged
   name; point the compare at consistent names (or add an equate in the
   netgen setup).
2. **`.ext` litter.** Magic's extraction writes one `.ext` file per subcell
   into the *current directory* — the shakedown scattered 154 of them into
   `signoff/`. They are scratch (now gitignored, `*.ext`); the script should
   `cd` into the results dir before extracting.

Also inherited from DRC: LVS on an **unmerged** GDS is meaningless below the
routing level — the cell layouts are not in the file to extract. Wait for a
stage-06 merged GDS (the export script merges since 2026-08-30).

## Status

Not yet run on a full design. Order of work: fix the name map → rerun the
macro-only shakedown until it passes → run on the v3 winner's merged GDS.

## 2026-09-04/05 — first full black-box run on iter16b, and why it could not match

Run: `run_lvs_bb.sh` inside the export chain, 18:24 magic extract (bb) ->
19:11 spice (88 MB) -> netgen 19:12-00:55 (killed by hand). comp.out at
22:55: "Circuit 1 contains 250939 devices, Circuit 2 contains 250938 devices"
(cells, hierarchical compare — within one), but "380,580 nets vs 1,417,182
nets" and `VPWR | (no matching pin)`, `VGND | (no matching pin)` on every
cell class. Cause: `06_export.tcl`'s `_pnr.v` is written by a plain
`saveNetlist`, which omits power/ground pins and physical instances; the
layout side has VPWR/VGND/VPB/VNB on every cell, so netgen sees each
implicit supply pin as its own unconnected net (250 k cells x 4). The
decap/fill/tap cells were "flattened as unmatched subcells" for the same
reason (absent from the Verilog). The 2026-08-28 "macro name mismatch" did
NOT recur: the layout spice carries `sram_1rw1r_32_256_8_sky130` with 9
devices inside the black box (expect ~0; look at those 9 next time).

Fix (2026-09-05 01:00): `06_export.tcl` gains a `netlist-lvs` step —
`saveNetlist -includePowerGround -includePhysicalInst` -> `*_pnr_lvs.v`;
`winner_chain.sh` and `run_lvs_bb.sh` prefer `*_pnr_lvs.v` when it exists.
The chain relaunched from `07_li1fix.enc` (li1 PG removed; tmux
`chain_16b_li1`, log `logs/chain_li1_sh.log`) produces the first netlist
that can match. Expected next failures, in order: the 9 in-macro devices,
supply-net naming (VDD/VSS vs VPWR/VGND at the top level), then real
opens/shorts if any.

## 2026-09-05 evening: first full black-box compare, two setup defects found and fixed

Run 2 on the li1-fixed export (`outputs/*_pnr_lvs.v`, saveNetlist
-includePowerGround -includePhysicalInst): magic extraction of the whole
design took **90 min** (not the 25 h of the armC attempt), netgen 30 min.
Result: `Circuit 1 contains 250940 devices, Circuit 2 contains 250944` and
**"Device classes ... are equivalent"**, then `Top level cell failed pin
matching` and 256,094 vs 267,867 nets. Two causes, neither a layout error:

1. **The GDS has no pin text.** `grep -a cpu_req_valid Cache_*.gds` = 0, so
   magic's top cell had an empty port list (`.subckt Cache_... ` with no
   ports) and every schematic port shows as "(no pin, node is <inst>)".
   Fix: `def_pins_to_magic.py` reads the DEF PINS section (216 pins, layers
   met1-met4, orientations N/E/S) and emits `box`/`label {name} center
   <layer>`/`port make` for each; `run_lvs_bb.sh` sources it after `select
   top cell`. Notes from the scratch test: bus names must be braced (Tcl
   sees `[31]` as a command), and `port makeall` converted only the label
   under the current box, so `port make` is issued per label. Verified on a
   painted scratch cell: all 216 names appear as subckt ports.
2. **Device-less physical cells.** The netlist instantiates fill_1 x4,
   fill_2 x196,802, tapvpwrvgnd_1 x153,805; magic extracts them as empty
   subcells and drops them, netgen keeps the Verilog stubs as classes ->
   the 4-device difference (fill_1, fill_2, tap, and one diode_2 group).
   Fix: `netgen_setup_bb.tcl` = PDK setup + `ignore class` for
   fill_1/2/4/8 and tapvpwrvgnd_1 in both circuits. Decaps have real MOS
   devices and matched (decap_12: 68,509 both sides).

Still to explain after run 3: the diode_2 class 6 vs 7 (7 instances both
sides; one layout pair parallel-merged?), and the net-count gap, which
netgen had not reached yet. Run 2 artefacts: `lvs_bb/run2_nopins_20260905/`;
the 19:42 misrun (top cell = first `module` = diode_2 stub):
`lvs_bb/misrun_diode_20260905/`. Run 3 launched 22:50 (tmux `lvs_16b_li1`).

### Run 3 (2026-09-06 01:50) - pins present, still "failed pin matching"; ROOT CAUSE = macro not black-boxed

Devices 250,940 vs 250,941 (the ignore-class fix closed the 4-gap; the last one
is a parallel-merged diode_2 pair), classes equivalent, nets 256,094 vs
267,867, `Top level cell failed pin matching`. The DEF labels were placed
correctly (KLayout probe: every label point sits on the pin's met and pin
shape; the GDS *does* carry pin-purpose shapes on datatype 16, just no text),
but the layout subckt had **200 ports, not 216**, 30 schematic ports showed
"(no pin, node is FE_OFN...)" and 28 mem_req_addr/wdata bits cross-matched.

The tell was in the layout spice: **every standard cell had one node on all
four of VPWR/VGND/VPB/VNB, named `mem_resp_rdata[15]`** (981k instance
lines touch it). Power and ground are one net in magic's view, and the 16
missing ports (cpu_req_addr[2..6,17,26,27], cpu_req_valid, cpu_req_id[1],
cpu_req_wdata[29], cpu_resp_rdata[30], mem_resp_rdata[12,13,25,30]) plus
mem_resp_rdata[15] all sit on that blob. The macro subckt in the layout had
**918 ports and the OpenRAM internals** (Xbank_0, Xcontrol_logic_*, Xdata_dff,
...): `lef read` + `gds noduplicates true` did NOT keep the LEF abstract
(magic only warned "cell ... already existed before reading GDS!"), and
magic's extraction of the OpenRAM cells shorts vdd/gnd/signal terminals
(816 "Ports X and Y are electrically shorted" warnings: gnd-gnd, vdd-S,
D-vdd, A-G ...). Through 16 macros that merged VPWR+VGND and every net on
a macro pin - which includes the top-level pins wired straight into the SRAM
address/data ports (S0 drives `array_rindex` combinationally). Everything
else in the pin report is cascade from that.

Fix (run 4, launched 17:55 tmux `lvs_16b_bb4`): `blackbox_macros_gds.py`
(KLayout) rewrites the GDS before magic - the macro cell is emptied, its
old subcells pruned, and refilled with the LEF PIN rects on datatype 20 plus
a pin-name text on datatype 16 (the sky130A magic tech reads `METnPIN` text
as a *port*; datatype 5 would be a plain label). 123 pins, 5,331 rects, no
two pins touch on a layer (checked), 445k OBS rects dropped. `run_lvs_bb.sh`
now does this by default (`ASIC_LVS_BB_GDS=0` = old lef-read path) and no
longer `lef read`s. Run 3 artefacts: `lvs_bb/run3_pins_20260905/`.

## 2026-09-07 07:55 - first LVS bb on iter19b (v7 package, chain af19b8 run 5)

`results/<19b>/lvs_bb/comp.out`: **Netlists do not match.** Device classes
and cell pin lists equivalent; `wmask1[3:0]` "no matching pin" as before
(tied in both netlists). The mismatch is a NEW class, not the 16b pin-matching
one: layout 242,824 devices / 246,776 nets vs netlist 242,360 / 246,476, and
exactly 300 layout nets with no match, every one of them `<cell>_<n>/VPB`:

| instance class | count |
|---|---|
| sky130_fd_sc_hd__inv_8 | 79 |
| sky130_fd_sc_hd__fill_2 | 60 |
| sky130_fd_sc_hd__inv_2 | 15 |
| sky130_fd_sc_hd__mux2_2 | 14 |
| sky130_fd_sc_hd__inv_4 | 13 |
| sky130_fd_sc_hd__inv_6 | 11 |

Reading: magic extracted these instances' n-wells as nets of their own,
i.e. their wells do not touch the tap/VPB well network in the GDS. Router
antenna diodes are not the cause (167 `diode_2` in the LVS netlist, 166 in
the DEF, matched). inv_8/inv_2/inv_4/inv_6 are the CTS inverter sizes and
mux2_2 a datapath cell, so the suspects are instances that ended up in row
positions without well continuity: cells moved by the antenna legalizer, or
sitting at row ends / next to the ECO reroute areas. Next: take one instance
name from comp.out, find it in the DEF (`COMPONENTS`), look at its
neighbours and the nearest `tapvpwrvgnd` cell in the GDS, and check whether
`verifyWellTap` (0 violations at export) uses a larger distance than the
well continuity actually needs. Not attributable to the VSS ECOs without a
pre-ECO LVS on 19b (none was run; the af19b7 chain was killed before LVS).
