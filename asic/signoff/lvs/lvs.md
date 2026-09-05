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
