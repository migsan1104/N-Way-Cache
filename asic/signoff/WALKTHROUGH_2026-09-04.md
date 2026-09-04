# Signoff day 4 walkthrough (2026-09-04) - follow along

This is a narrative of one working day on the iter16b signoff, written so
that someone who has never opened the flow can follow each step, rerun it,
and understand why it was done. Numbers are quoted from the reports named in
each section. The campaign ledger (`../PnR/DRC.md`) has the same facts in
ledger form; this file explains them.

Run under study: `asic/PnR/innovus/runs/20260902_iter16b_e35_fp16_die2900`
(16 KB, 4-way, 16 SRAM macros, 2.9 mm die, 4.0 ns clock). "The run dir"
below means that directory.

## 0. Vocabulary you need

- **P&R database / checkpoint** (`checkpoints/*.enc`): Innovus's saved state
  of the design at a stage. `05_route_opt.enc` is the routed, hold-fixed,
  DRC-clean state from 01:14 today.
- **verify_drc**: Innovus's own design-rule check on the routed database,
  using the rules in the tech LEF. Fast, approximate, the router's view.
- **KLayout DRC**: the full foundry rule deck (`sky130A_mr.drc`) run on the
  streamed-out GDS. Slow (4-5 h here), the truth.
- **Antenna**: charge collected by a metal wire during fabrication can
  damage the gate it drives. `verifyProcessAntenna` checks the ratio;
  fixes are layer hopping or a diode cell on the pin.
- **Fill**: filler and decap cells placed in every empty row site after
  routing so the power rails and wells are continuous (section 3).
- **Export**: the stage that writes deliverables: netlist, SPEF, SDF, SDC,
  DEF, GDS (section 3).
- **SPEF**: parasitic R and C of every net, extracted by Quantus from the
  routed geometry. Consumed by Tempus (timing) and Voltus (power
  integrity). Not by DRC.
- **MMMC / analysis view**: Tempus and Innovus time the design in *views*.
  A view = a delay corner (library set + RC corner) + a constraint mode
  (SDC). We have `setup_view` (slow cells, slow RC) and `hold_view` (fast
  cells, fast RC).
- **Source latency vs network latency**: network latency is the clock tree
  insertion delay, measured. Source latency is an SDC adjustment on the
  clock port, here a *negative* number Innovus's CTS writes so that I/O
  constraints stay relative to the clock at the port.

## 1. Where the day started

Overnight, `antenna_then_chain.sh` had (a) attached 7 antenna diodes with
`attachDiode` (`antenna_fix2.tcl`), (b) run the winner chain: hold
optimisation, `ecoRoute -target` until `verify_drc` = 0, saved
`05_route_opt.enc` at 01:14, and (c) measured antenna = 0 on it. That is
the first database in the campaign that is DRC 0 and antenna 0 at once.

Then the antenna ECO script ran an unconditional `refinePlace
-preserveRouting true`. On a database with nothing to fix, refinePlace
re-legalised the whole design against its region constraints and 4
unplaceable buffers: 46,888 instances moved (mean 235 um). The following
`optDesign -postRoute -hold` ground for 9 h on the wreckage and then
launched a full reroute. Nothing after 01:14 was saved. Lesson:
**a legalisation step is not a no-op; gate it on whether anything was
actually inserted.** Fixed in `antenna_eco.tcl` (baseline count parsed
first; 0 -> skip everything).

How to see this yourself:
```
grep -n "INFO: ANTENNA\|refinePlace\|Move report" <run dir>/logs/chain_af_sh.log
```

## 2. Export from the clean checkpoint

```
ASIC_CHAIN_FROM=export ASIC_EXPORT_SRC=05_route_opt.enc \
  asic/PnR/innovus/scripts/winner_chain.sh 20260902_iter16b_e35_fp16_die2900
```
(`ASIC_CHAIN_FROM=export` is new today: skip the hold/eco/antenna steps and
export a checkpoint you have already judged.) The export stage
(`06_export.tcl`) does, in order: fill, `globalNetConnect` rebind,
connectivity / geometry / antenna / well-tap checks, Quantus extraction,
signoff timing, reports, then netlist, SDF, SDC, DEF, GDS. ~50 minutes.

Two things to know:

- **The Innovus session did not exit.** `06_export.tcl` has no `exit`,
  and under tmux the tool has a terminal, so it sat at `innovus 1>` for an
  hour while three downstream jobs waited on it. Tempus did the same after
  an error later in the day. Lesson: **batch launches must either end in
  `exit` or be fed `< /dev/null`** so a prompt gets EOF and quits.
- **`saveNetlist -physicalInsts` was never an option** (IMPTCM-48, also on
  armC's export). saveNetlist omits fillers/taps by default, so the sim
  netlist only needs `-excludeLeafCell`. Fixed.

## 3. What fill is, and the post-fill checks

Standard cells assume neighbours: each carries a slice of the VPWR/VGND
rails and of the N-well. An empty site breaks both, and the diffusion/well
layers have density rules. Fill cells (no logic) plug every gap; decaps are
fillers with a VDD-VSS capacitor for local charge. 196,806 were inserted.
Fill has no timing and appears in GDS/DEF but not in the sim netlist.

After fill the export re-runs four checks (`reports/signoff/*.rpt`):

| check | result | meaning |
|---|---|---|
| verifyConnectivity | "1000+ unconnected VSS terminals" | see below |
| verifyGeometry | 1000 Overlap (cap) | retired as a signal; KLayout is the truth |
| verifyProcessAntenna | 0 | clean |
| verifyWellTap | 0 | every cell within 13 um of a tap |

The connectivity number had been on every export and was mis-diagnosed
on 09-03 because the report caps at 1000 lines. With the cap raised
(`scripts/classify_vss.tcl`, `verifyConnectivity -error 200000`) the real
count is 199,895, and 199,894 of them are the **VNB** pin, the p-well
substrate tie, on every kind of cell. VNB/VPB ports sit on `pwell`/`nwell`,
which the tech LEF declares `TYPE MASTERSLICE`: no metal, nothing to route,
nothing the checker can trace. The substrate tie is physical, via the tap
cells (well-tap check = 0). Lesson: **never diagnose from a capped report;
raise the cap and group by pin name.** Remaining items: one internal m3
shape of one SRAM `gnd` pin (benign) and 106 VDD met4 stripe-end stubs.

## 4. Timing signoff in Tempus, and the SDC bug

`asic/signoff/tempus/sta.tcl` builds the MMMC from `mmmc.tcl`, reads the
netlist and SPEF, loads the **as-implemented SDC** the export wrote, applies
the I/O virtual clock (`io_vclk.tcl`), and reports. Today's launcher
`run_two_corner.sh <stamp> [corner:derate ...]` runs it once per
standard-cell corner into `results/<stamp>/tempus_<corner>_d<derate>/`.

Setup came out clean at both corners on the first pass:

| corner | reg2reg | reg2out | I/O clock latency |
|---|---|---|---|
| ss_n40C_1v76 (campaign) | +2.284 | +1.192 | 2.251 |
| ss_100C_1v60 (iter16b's own P&R corner) | +1.569 | +0.692 | 3.448 |

Hold came out **+4.608 ns** on a same-clock register path, which cannot be
physical at a 4 ns period. The cause took four passes to pin down:

1. The export writes two SDCs that differ in exactly four lines: the
   negative source latency on `clk`. `write_sdc -view setup_view` emits
   only the `-max` values (-4.59), `-view hold_view` only the `-min`
   values (-1.85). The Innovus DB holds all early/late x min/max combos per
   view; the export is lossy.
2. Tempus takes max-qualified latency for the capture clock and
   min-qualified for launch. A view with only one kind is inconsistent.
   Loading the setup SDC alone: hold +4.6 (fake). armC's +5.1 was the same.
3. Loading both SDCs in one constraint mode: the second `create_clock`
   overwrites `clk` (TCLCMD-1594) and the -max latencies vanish; setup
   collapsed to -4.8 (fake).
4. Setup SDC plus the four -min lines evaluated: hold +2.76 and setup
   -0.22 (both fake).

Correct emulation: **one constraint mode per view**, and inside each mode
set every min/max combo to that view's own value (`_mirror_source_latency`
in sta.tcl; `create_constraint_mode` -> `update_analysis_view` ->
`set_analysis_view` -> `set_interactive_constraint_modes` -> mirror; the
order matters, TCLCMD-1047 otherwise). Lesson: **when a signoff number is
physically impossible, stop and find the constraint that made it so**; a
+4.6 ns hold slack is not "good margin". Pass 5 (this fix) is the signoff
number; a 3.0 ns period what-if follows it (`SIGNOFF_PERIOD=3.0`).

### 4b. Pass 5 results (the signoff numbers) and the 3 ns what-if

| corner (macro x1.5) | reg2reg | reg2out | hold | violators |
|---|---|---|---|---|
| ss_n40C_1v76 | +2.284 | +1.192 | +0.018 | 0 |
| ss_100C_1v60 | +1.569 | +0.692 | +0.018 | 0 |

Hold is the same at both because hold_view is the same fast corner. The
hold path terms now read launch 0.611 = 2.460 - 1.848 and capture 0.897 =
2.745 - 1.848, i.e. both clocks carry the hold view's own source latency.
These passes are NOT SI-aware; the Innovus signoff was and reported 9 hold
violators at -0.075. An SI-aware pass (`run_si_pass.sh`, `SIGNOFF_SI=1`)
is the tie-breaker.

What-if at 3.0 ns on the same package (campaign corner): reg2reg **+1.284,
0 violators** - the internal logic meets 3 ns. The I/O groups fail (reg2out
-1.808 x40, in2reg -1.373 x748) under the unchanged 0.7/0.3 external
budgets and a virtual-clock period the run recorded as 4.0, so the I/O side
of the what-if is not a usable number; it would need re-budgeting anyway.
Statement that is safe: "post-route STA shows the register-to-register
logic meets a 3.0 ns period at ss_n40C_1v76".

### 4c. SI-aware pass (`run_si_pass.sh`, SIGNOFF_SI=1)

| ss_n40C_1v76, SI on | slack |
|---|---|
| reg2reg | +1.593 |
| reg2out | +0.917 |
| worst hold | +0.010 (0 negative of the 50 listed) |

Crosstalk costs ~0.7 ns of setup margin and 8 ps of hold margin against the
plain-calculator pass, and no path goes negative. This is the number to
quote for hold: Tempus with Quantus parasitics and SI on. The Innovus
signoff step (also SI-aware, but on its own medium-effort extraction) had
reported 9 hold violators at -0.075; the two engines disagree by ~85 ps on
a margin that thin, which is worth one sentence on the sheet and no ECO.

## 5. What Fmax can be claimed

The design was implemented to 4.0 ns and signs off at 4.0 ns: **250 MHz**
is the claim. The internal critical path (~2.4 ns at ss/100 C) says the
logic could go faster, but the I/O budget, the clock tree, the hold fixes
and the SRAM macro's real access time (SPICE: ~6 ns clock-low, see
`../MACROS.md`) were all set for 4 ns. A Tempus re-time at 3.0 ns on the
same package is a supporting statement ("routed netlist meets setup at 3
ns"), never an Fmax. A real 3 ns number needs a re-implementation, which is
what iter16c is (section 7).

## 6. Utilisation, for the record

Route-stage summary: core 8.22 mm2, macros 2.69 (32.7%), logic 2.62,
blockages 0.78. Innovus "core density" = placed cell area / core area =
67.2% (64.6% logic+macros). The number that matters for routing is logic
over rows actually available (core - macros - blockages) = ~55%, which is
the placement density cap the run was launched with. After fill the
density reads 97% because fillers count as cells; quote the pre-fill one.

## 7. iter16c

Launched 14:50: iter16b's recipe with two changes, the campaign corner
(`ASIC_SIGNOFF_LIB=ss_n40C_1v76`, iter16b had run at ss_100C_1v60 by
omission) and a 3.0 ns clock (`ASIC_PNR_SDC=constraints/pnr_3ns.sdc`, new
knob in `innovus_config.tcl`), plus 16 CPUs (iter16b ran on one CPU for 23
h because the launch never set `ASIC_CPUS`). Watch the route-gate DRC
count against iter16b's 38.

## 8. Voltus: why, and the first step

No IR-drop analysis has been run on any iteration. The notebook
(`voltus/voltus.md`) argues it matters: ~1 W at 1.76 V is ~620 mA across
the die; 5% sag costs 200-400 ps, the same order as the setup margin. The
blocker was that SKY130 ships no power-grid views (PGVs), the per-cell
electrical model of rails and vias Voltus needs. Today they were generated
for the first time (`voltus/run_pgv.sh`, scripts `pgv_*.tcl`):

- `techonly`: wire/via RC model of the PG network from the Quantus
  techfile. 437 cells, seconds.
- `stdcells`: one Spectre simulation per cell from the PDK SPICE
  (`sky130_fd_sc_hd.spice`, models `sky130.lib.spice` corner `tt`) for the
  P/G capacitance and leakage. Hours. Spectre is bundled in the Voltus
  install and licensed (8 CPUs allowed by the licence).

With both `.cl` libraries, a static rail analysis on the routed database
is quick (voltus.md step 2). In a real flow this is done twice: after power
planning (on the placed design, cheap to fix) and at signoff (routed +
extracted, with IR-aware timing fed back to STA).

### 8b. The result, and how "pass" is judged

Voltus prints no verdict. `set_pg_nets -threshold` defines the pass line
(here 3 % of 1.76 V) and the report counts nodes below it. EM is judged as
J/Jmax per wire and via and needs per-layer limits loaded; with none, the
EM line reads "0 violations" and means nothing.

Ring-as-supply (228 sources per net at 50 um), macros excluded:

| net | worst | average | budget | verdict |
|---|---|---|---|---|
| VDD | 119 mV | 78 mV | 53 mV | fail (2.2x) |
| VSS | 121 mV | 80 mV | 53 mV | fail (2.3x) |

The map: periphery within 1 % of nominal, the whole hub inside the macro
ring in the worst band, gradients only at the four corner gaps. The macro
ring walls the hub off. Fix for iter17: met5 straps across the macros into
the hub. Lesson: **a first IR number is only as good as the supply-entry
assumption** - one source per side gave 275 mV, the ring as supply gives
119 mV, and the difference is not the grid.

It took seven attempts to get one number. In order: Innovus-DB restore
loses floorplan across versions; power nets must exist before connection;
`analyze_rail -type net` is one net; `init_design` puts Voltus in timer
mode, which silently drops `defIn` and refuses `read_def`; the alias
`spefIn` did nothing; the Voltus UG's own load sequence works. Every one
of those is a five-minute run, and each is written in `voltus/voltus.md`.

## 9. Tool inventory learned today

- Pegasus Verification (Cadence DRC/LVS) is licensed (18 features, idle)
  but not installed; `/apps/cds/pegasus231` is Pegasus DFM. IT request
  drafted in `pegasus/Pegasus.md`. Calibre 2026.2 and IC Validator are
  installed and licensed, but no SKY130 decks exist for any of the three.
- Verisium Manager 25.02, IMC and Verisium Debug 25.01 are installed and
  licensed (`source /apps/settings` puts them on PATH). Adding
  `-coverage all` to the Xcelium regression gives a coverage database IMC
  opens directly.

## 10. Checklist to reproduce today's export + signoff on another run

1. Judge a checkpoint: `verify_drc` 0 and `verifyProcessAntenna` 0.
2. `ASIC_CHAIN_FROM=export ASIC_EXPORT_SRC=<ckpt> winner_chain.sh <stamp>`
   (then type `exit` at the `innovus 1>` prompt if it appears).
3. `signoff/tempus/run_two_corner.sh <stamp>` (both corners; per-view
   constraint modes are automatic).
4. KLayout runs inside the chain; classify its items against the macro
   boxes before judging.
5. Black-box LVS: expect "pin matching" failure until the macro name map
   is fixed (`lvs/lvs.md`).
6. Static IR: `voltus/voltus.md` step 2, once `pgv/stdcells` exists.
