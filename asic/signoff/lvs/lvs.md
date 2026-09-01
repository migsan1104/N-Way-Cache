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
