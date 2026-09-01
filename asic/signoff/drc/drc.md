# DRC — design rule checking with Magic

Assume DRC has never been run here before. What it is, why Magic (and not a
Cadence tool), how the script works, and where the shakedown stands.

## What DRC is

Design Rule Checking verifies the final mask geometry (the GDS) against the
foundry's manufacturing rules: minimum widths, spacings, enclosures, density.
It knows nothing about logic or timing — a design can be DRC-clean and
functionally wrong, or timing-clean and unmanufacturable. It is a *geometry*
check, and it runs on the **merged** GDS (see the trap below).

Note the name collision: Innovus's `verify_drc` checks *routing* rules during
implementation (that is what the stage-05 gate counts). Signoff DRC checks
*mask* rules with the foundry's own deck. Different rule sets, different
severity — this one is the tapeout gate.

## Why Magic

The tool follows the deck, and only Magic / netgen / KLayout have sky130
decks (the PDK ships them in `libs.tech/`). The licensed Cadence engine for
this (Pegasus Verification) is not installed on this server — `/apps/cds/
pegasus231` is Pegasus **DFM** (litho/CMP analysis, no DRC/LVS binary) — and
no sky130 Pegasus deck exists anyway (`../README.md`). Magic's deck is the
one the sky130 open-source ecosystem signs off with; KLayout
(`sky130A.lydrc`) is the available second opinion.

## Mechanics and the Tcl 8.5 trap

`run_drc.sh` drives Magic in batch mode: read the GDS, load the top cell,
`drc euclidean on; drc style drc(full); drc check; drc catchup`, then write
`drc.rpt` (every violation) and `drc_count.txt` (by rule).

Magic at `/apps/magic` was built against Tcl/Tk 8.5, which the OS no longer
ships. The Synopsys FPGA tree carries a complete 8.5 runtime, so `env.sh`
wraps the invocation as `$MAGIC_RUN` with `LD_LIBRARY_PATH`/`TCL_LIBRARY`
scoped to that one command — never exported globally, so the Synopsys libs
cannot leak into Cadence tools.

```bash
bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
          <repo>/asic/signoff/drc/run_drc.sh [gds]'
# gds defaults to $SIGNOFF_PNR_DIR/outputs/<tag>.gds
# results in $SIGNOFF_RESULTS/drc/
```

## The merged-GDS trap (found 2026-08-30)

A GDS streamed out of Innovus **without `-merge` contains no cell layouts** —
only routing, vias, and empty references to cell structures. The v2 GDS is
exactly that (57 structures, zero `sky130_fd_sc_hd__*` cells), so DRC on it
checks routing-level geometry only; every cell-internal and cell-abutment
rule goes untested. Stage `06_export.tcl` now merges the std-cell and
SRAM-macro library GDS at stream-out, so the v3 winner's GDS will be real
mask geometry. Never quote a DRC result without saying which kind of GDS it
ran on.

## Status

- 2026-08-28 shakedown on the SRAM-macro GDS alone: contradictory output
  ("1,135,336 error tiles" yet "Total DRC errors found: 0") — the deck
  style/config in the driver script is not right yet; resolve before trusting
  any count.
- 2026-08-30: running on the v2 full-design GDS (abstract-only, see trap) as
  a script shakedown. v2 is a discarded design; the count is not a result.
- Real target: the v3 winner's **merged** GDS after stage 06.
