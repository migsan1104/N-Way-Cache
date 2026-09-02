# Respin plan: iter15 / iter16 (rewritten 2026-09-01 ~23:00 after reading the fp files)

**Correction to this file's first draft** (kept honest for the record): the
first version assumed the floorplan was the env-knob 4x4 grid from
`01_floorplan.tcl` defaults. It is not. iter14/armE runs on
`floorplans/fp_iter7.tcl` via `ASIC_FLOORPLAN`, which replaces all of that:
2700x2700 die, **16 macros in four rows of 4 along the die perimeter**
(rotated dout-inward), GAP 40, EDGE 40, HALO 8, way-wedge soft regions, and a
40% partial placement blockage over the central hub. "Move macros to the
perimeter" was this campaign's opening move, not a last resort. Floorplan
files are named for the P&R iteration that introduces them (`fp_iter7.tcl`,
`fp_iter8.tcl` = iter7 + corner damping, used by iteration 9) — so the next
one is **`fp_iter15.tcl`**, and new run stamps continue iter15, iter16, ...

## Trigger

Execute if surgery's final `verify_drc` != 0 (or launch a rung early in
parallel — 128 cores, load ~7, memory free; the only cost is machine time).

## Where the violations actually live (fp_iter7 coordinates)

Surgery/armB cluster boxes vs the macro ring:
- `{2102 497 2700 696}` — RIGHT macro row, way3 b0/b1 boundary, out to die edge
- `{192 2013 525 2212}` — LEFT macro row, way2 b3 region
- `{2134 2025 2429 2182}` + `{2036 2174 2166 2347}` — NE corner: top of the
  right row / right end of the top row, where two macro rows converge

Pattern: **ring-corner convergence zones + specific macro-to-macro seams**,
not the hub (the hub blockage did its job). Regenerate
`floorplans/armB_violation_pattern.png` (scratchpad plot script, see
optimization-campaign handoff) before finalizing any box.

## The menu (one variable per rung)

**iter15 — fp_iter15.tcl = fp_iter7 + measured-cluster damping.**
The exact move `fp_iter8.tcl` made for iter7's residue (25% blockages over
measured bins to spread displaced-buffer piles): add 40-50% partial
blockages over the four measured boxes, pre-placement. Same physics surgery
is testing on a routed DB, but applied where it belongs — before placement,
so no 46k-instance scramble. Cheapest to write (copy fp_iter7 + 4 lines),
strongest precedent.

**iter16 — geometry relief at the pinches.** If iter15 improves but the
NE-corner convergence zone persists, the corner needs actual space, not
density pressure: die 2700 → 2760-2800 (grows the ring-corner gaps), or
GAP 40 → 60 within the affected rows only (fp file edits per-row, unlike the
env knob). Choose the lever from the regenerated pattern plot: seams between
adjacent macros → GAP; corner convergence → die size.

**Recipe for every rung (frozen by the B/C evidence):** stages 00→05 with
`ASIC_DRC_GATE=0` (route, verify, NO opt), judge the raw route count vs
fp_iter7's 706 baseline; if promising, hold-only opt + eco passes
(armB/armC-style), then antenna ECO, export, signoff triplet. Setup opt never
runs on a respin (it manufactured 706 → 3,375 on iter14).

## Schedule vs 9/13 (~5-6 h to a raw-route verdict, ~1.5 d to full verdict)

| date | milestone |
|---|---|
| tonight/9/2 AM | (optional) iter15 launched in parallel; surgery verdict |
| 9/2-9/3 | iter15 raw-route + hold-only verdict |
| 9/4-9/6 | iter16 if needed |
| 9/8-9/9 | last safe launch window |
| 9/10-9/13 | signoff triplet on the winner, writeup, renders |

## Log

- **2026-09-01 ~23:15** — iter15 rung EXECUTED: `fp_iter15.tcl` written
  (fp_iter7 + 50% damping over the four measured boxes), launched as
  `20260901_iter15_e35_fp15_damp` (tmux `iter15`) with arm E's exact knobs,
  stages 00->05, ASIC_DRC_GATE=0. Raw-route verdict expected ~05:00.
  Full rationale + decision tree: DRC.md "Iteration 15 launched".
