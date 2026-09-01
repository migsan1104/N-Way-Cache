# ECO — Engineering Change Orders

A learning document, in the same spirit as `Innovus.md`: what an ECO is, why
every real tapeout flow ends in one, and how the Innovus/Tempus ECO loop will
be used in *this* project. Nothing here has been exercised yet — the "Status"
section at the bottom says what the first real exercise will be.

## 1. What an ECO is, and why it exists

An ECO is a **surgical edit to a finished (or nearly finished) implementation**
— add a buffer, resize a cell, rewire a pin — applied *without* re-running the
flow that produced it. The reason it exists is asymmetry of cost:

| change vehicle | cost |
|---|---|
| edit RTL, re-synthesize, re-place, re-route | hours–days of runtime, and **every** timing number moves (the ±250 ps cone noise this campaign measured between Genus netlists is exactly this) |
| ECO: patch 20 cells, `ecoRoute`, re-time | minutes, and every path you did **not** touch keeps its timing |
| (after tapeout) new full mask set | ~all the mask cost again |
| (after tapeout) metal-only ECO | only the metal/via masks — the reason spare cells exist |

The second row is the everyday use and the one this project needs: late in the
flow, with 30 min of route behind a checkpoint, you do not re-route the die
because three hold paths need a delay cell. The last row is the famous one:
after silicon comes back broken, you fix logic by rewiring **existing**
transistors with new metal masks only.

Two orthogonal ways to classify any ECO:

- **Timing ECO** — the netlist function is unchanged; cells are resized,
  buffers added/removed, wires re-routed to fix setup/hold/DRV. Verified by
  re-running STA. This is what optDesign does internally, and what a
  signoff-driven ECO does with Tempus in the driver's seat.
- **Functional ECO** — the logic itself changes (a bug fix: an inverted
  enable, a missing qualifier). The patch is expressed as netlist surgery, and
  **must** be proven equivalent to the *intended* RTL by logical equivalence
  checking (LEC — Cadence Conformal; `lec` is installed on this server).

And by *when* they land:

- **Pre-mask** — before tapeout. Any cell can be added, moved, or resized;
  placement and routing adapt. This is our territory for now.
- **Post-mask** — after (some) masks are made. Base layers are frozen: you may
  only rewire what already exists, which means **spare cells** (see §5).

## 2. Where ECO sits in this project's flow

Our flow (renumbered 2026-08-30): `00 init → 01 floorplan → 02 power →
03 place+opt → 04 cts+opt → 05 route+gate+opt → 06 export`, then the signoff
directory checks the result with independent engines (Quantus extraction,
Tempus STA, Magic/netgen physical verification).

The ECO loop closes the circle:

```
05_route_opt.enc ──06 export──▶ netlist + SPEF ──▶ Tempus STA (signoff/tempus/)
      ▲                                                   │
      │                                            violations found
      │                                                   ▼
  ecoDesign / eco* commands + ecoRoute  ◀──── ECO file (what to change)
      (Innovus, on the checkpoint)
```

The point: **Innovus's own `timeDesign -signoff` and Tempus do not always
agree** (different engines, and only Tempus reads our per-corner Quantus
SPEFs). The numbers that count are Tempus's, so the *fixes* should be chosen
by Tempus too, and Innovus is then just the executor that makes them physical.

## 3. The signoff-driven timing ECO (the standard loop)

Step by step, with the commands this repo will actually use:

**1. Time it in Tempus** (`signoff/tempus/sta.tcl` — netlist + SPEF + the
same MMMC file as Innovus, so corners cannot drift).

**2. Let Tempus choose the fixes.** Tempus has the optimizer built in:

```tcl
# inside the Tempus session, after init_design + spefIn
set_db opt_signoff_fix_hold true
opt_signoff -hold            ;# or -setup, -drv
write_eco_opt_db -to_file eco_hold.tcl   ;# the ECO file: a list of surgical edits
```

The ECO file is human-readable Tcl — read it before applying it. Expect
`ecoChangeCell`-style entries (resize), `ecoAddRepeater` (buffer insertion),
cell moves. If it wants to touch hundreds of cells, stop and ask why; a
healthy post-route hold ECO is tens of cells (v2's honest hold number was
-0.068 ns across 27 paths — that is ~30 delay cells, a classic small ECO).

**3. Apply in Innovus on the routed checkpoint:**

```tcl
restoreDesign checkpoints/05_route_opt.enc.dat $TOP
setEcoMode -honorDontUse true -honorDontTouch true -honorFixedStatus true
source eco_hold.tcl          ;# the edits, as eco* commands
ecoPlace                     ;# legalize the new/changed cells only
ecoRoute                     ;# route ONLY the disturbed nets
```

`ecoRoute` is the whole reason the loop is cheap: NanoRoute re-routes the
handful of broken nets and leaves the other hundreds of thousands untouched.

**4. Re-extract, re-time, converge.** After any ECO the SPEF is stale:
re-run extraction (stage 06's extractRC, or Quantus), feed Tempus again, and
loop until clean. Then re-export **all** deliverables — a netlist, SPEF, SDF,
DEF, or GDS from before the ECO no longer describes the design (this is the
sync trap in §6).

## 4. The Innovus eco* commands (the vocabulary)

For hand-written ECOs — sometimes a one-liner beats a tool run. All of these
exist in our Innovus 21.16:

| command | does |
|---|---|
| `ecoAddRepeater -net N -cell BUF -loc {x y}` | insert a buffer/inverter pair into a net at a location |
| `ecoDeleteRepeater -inst I` | remove one |
| `ecoChangeCell -inst I -cell NEWCELL` | swap a cell for another footprint-compatible one (upsize/downsize, VT swap) |
| `ecoPin`, `ecoConnect`/`ecoDisconnect`... | rewire pins (functional ECO territory) |
| `ecoPlace [-inst I]` | legalize only what the ECO disturbed |
| `ecoRoute [-modifyOnlyNets ...]` | route only the disturbed nets |
| `setEcoMode -batchMode true` | defer placement/routing until the end of a batch of edits |
| `setEcoMode -refinePlace false -updateTiming false` | full manual control while experimenting |

sky130 notes: upsizing means e.g. `sky130_fd_sc_hd__buf_2 → buf_4` (same
footprint family, wider); hold fixing uses `sky130_fd_sc_hd__dlygate4sd3_1`
and friends; and every ECO cell choice must respect the `dont_use` list
`00_init.tcl` applies (`setEcoMode -honorDontUse true` enforces it).

## 5. Post-mask ECOs and spare cells (for completeness)

After tapeout, base layers (diffusion, poly, li1) are frozen. A functional fix
then has to be built from gates that already exist on the die but do nothing:
**spare cells** — small farms of NANDs, NORs, inverters, flops sprinkled
through the placement before tapeout, inputs tied off, waiting. The ECO
rewires them with metal/via changes only:

```tcl
ecoChangeCell -inst spare_7/nand2 ... ;# repurpose a spare
ecoRoute -postMask                    ;# new metal only, base layers untouched
```

Innovus supports it end to end (`ecoDesign -postMask`, spare-cell aware
`place_design -incremental`). **This project inserts no spare cells today** —
there is no silicon plan, so they would be dead area in the PPA numbers. If a
shuttle run (efabless/TinyTapeout-style) ever becomes the goal, add a
spare-cell insertion step to stage 03 and re-measure area; that is the price
of post-silicon fixability.

## 6. Traps (learned elsewhere in this repo, or standard)

1. **The deliverable-sync trap.** After an ECO, *every* exported view is stale
   until re-exported: netlist, SPEF, SDF, DEF, GDS, and any Tempus/Magic/LVS
   result derived from them. Treat "ECO applied" as "stage 06 must run again".
   (Same class as the live-edit trap: artifacts must correspond, or numbers
   lie silently.)
2. **OCV mode.** Post-route timing/opt in Innovus requires
   `setAnalysisMode -analysisType onChipVariation -cppr both` (IMPOPT-6080 —
   this killed a route once already, 2026-08-26). Any hand-driven ECO session
   on a routed database needs it set before timing anything.
3. **Do not ECO a gated design.** The stage-05 DRC gate exists because
   optimisation on a DRC-riddled route multiplies the damage (v2: 331k → 1.8M
   violations). An ECO is optimisation in miniature — same rule. Fix the
   floorplan; ECO the healthy result.
4. **Functional ECOs need LEC, not simulation confidence.** A hand netlist
   edit that "obviously" matches the RTL fix still gets proven with Conformal
   (`lec` is at `/apps/cds/confrml241/bin/lec`) against the patched RTL:
   4/4 regression + digit-identical reports is this repo's bar for RTL
   changes; LEC clean is the equivalent bar for netlist changes.
5. **Fixed cells and derates.** The SRAM macros are `pStatus fixed` with
   per-instance timing derates applied by name (`pnr_apply_macro_derates` in
   `mmmc.tcl`). ECO sessions restore those derates only if the MMMC file is
   loaded the same way — a hand session that skips it will time the macros
   optimistically and "fix" the wrong paths.

## Status (2026-08-30)

Nothing ECO'd yet. The planned first exercises, in order:

1. **Hold-fix ECO on the v3 winner** after stage 05: if post-route hold is a
   handful of small violations (v2's was -0.068/27 paths), fix it via the
   Tempus `opt_signoff -hold` → `write_eco_opt_db` → Innovus
   `source eco.tcl; ecoPlace; ecoRoute` loop of §3 instead of a second
   `optDesign -postRoute -hold` pass — same result class, and it exercises
   the whole loop on a real, small problem.
2. **A deliberate one-liner** (`ecoChangeCell` upsize on a known worst path)
   to see the mechanics end to end: edit → ecoRoute → re-extract → re-time,
   watching only that path's slack move.
3. Post-mask/spare-cell flow: reading material only, until there is a silicon
   plan.
