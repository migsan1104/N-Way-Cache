# The routing-DRC campaign — iteration ledger, autopsies, hypotheses

Every P&R iteration since v2 has died at the same place: the router finishes,
`verify_drc` counts tens of thousands of violations, and the stage-05 gate
(`ASIC_DRC_GATE=2000`) stops the flow. This file is the ledger: what each
iteration was, what it violated, why we believe it happened, and what the next
generation changes. Floorplan geometry and the v3 design rationale live in
`FLOORPLAN.md`; this file owns the DRC story.

A healthy detail route ends with **hundreds** of violations that the router's
own iterations clean up. 50k–640k means the placement was unroutable and the
router is reporting that fact — *the router doesn't create congestion, it
reveals it*. Post-route optimisation on such a route makes it strictly worse
(measured twice, below).

## The autopsy recipe

Same four cuts on every `reports/route/drc.rpt`, so iterations are comparable:

```bash
R=reports/route/drc.rpt
grep -aoE "^[A-Z-]+:" $R | sort | uniq -c | sort -rn                  # by type
grep -aoE "\( (li1|met[1-5]) \)" $R | sort | uniq -c | sort -rn       # by layer
grep -a "Bounds" $R | awk -F'[(,) ]+' \
  '{print int($3/500)*500"_"int($4/500)*500}' | sort | uniq -c | sort -rn  # 500um bins
grep -ac "FE_" $R; grep -ac "CTS_" $R                                 # net class
```

(`$3/$4`, not `$2/$3` — the `Bounds :` colon is its own field.)

**Forecast table for every run** (stage-03 settled / post-CTS / route-phase
hotspot + overflow): `python3 innovus/scripts/forecast_table.py` — run it any
time; it reads the logs live, future iterations included.

## The scoreboard — one iteration sequence, variable explicit

Every row is an iteration of the SAME experiment: get the 16KB ASSOC=4 cache
through route with < 2000 DRCs at 4.0 ns. Early iterations varied the
floorplan; from iteration 7a on, the variable is whatever the evidence
indicted — floorplan, CTS, netlist, or route settings. One variable per
iteration; "vs" names the baseline it changed.

All at 4.000 ns SDC; iters 3+ at corner ss_n40C_1v76 + vendor macro ×1.5.
"markers" = live `top.markers` at the gate; `drc.rpt` caps at 100k.

| iter | aka | variable changed (vs baseline) | postCTS WNS | route DRC | verdict |
|---|---|---|---|---|---|
| 1 | v1 | floorplan: two macro columns per side | — | 47.7k (met4 cap + li1 poison) | discarded; post-mortem in `Innovus.md` |
| 2 | v2 | floorplan: central macro block, perimeter logic | -2.685 | **331k**; postroute opt → 1.8M | dead. Cross-corner (ss_100C_1v60 ×2.0) — don't compare timing |
| 3 | v3-A | floorplan: quadrant tiles | -1.326, hold clean | **640,478 markers** | gate FAIL; 79% density, center-south jam |
| 4 | v3-B | floorplan: true ring, hub 840 | -1.252, hold clean | **50,524** (104,845 markers) | gate FAIL — best of the pure-floorplan era |
| 5 | ringhub | floorplan: hub 940 (+25%) + global density cap 0.62 (vs 4) | **-0.949, hold clean** | **~133k live** | gate FAIL — hub bins 2× iter4: hub size & global cap measured dead |
| 6 | quadfix | floorplan: quad regions -120 µm, hub 1040, cap 0.62 (vs 3) | killed in place | — | forecast worsening (hotspot 2317→5321) |
| 7a | G7a (side) | CTS: clock met3–met5 + 2w2s NDR (vs 5, same placement) | -1.081 | **402,306 markers** | FAIL — NDR doubled clock footprint on starved layers |
| **7** | **G7b** | **floorplan: iter5 + 40% partial place blockage over hub (vs 5)** | -1.272, hold clean | **2,859 / 7,034 markers** | **breakthrough — 47×; hub bins clean, residue at 3 region corners** |
| 7r | G8-repair | route: 2 extra detailRoute passes on iter7's route | n/a | 3,103 (plateau) | residue is HARD (placement pile-ups), not congestion |
| 8 | G7d | netlist: E36(b) RTL, -2,336 cells (vs 7, same floorplan) | -1.512, hold clean | **2,133,467 markers at the gate** | CATASTROPHIC gate FAIL (14:02) — the netlist is toxic to this floorplan: EstWL +32%, eGR overflow 20%H vs 6.4%, hotspot saturated die-wide |
| 9 | fp_iter8 | floorplan: iter7 + 25% corner dampers; e35 netlist (vs 7) | -1.068, hold clean — best ring timing | **48,250 / 99,479 markers — 17× WORSE than iter7** | gate FAIL 18:23 — dampers BACKFIRED: violations moved back into the hub ring (bins (1500,1000) 8k, (500,1000) 7.8k). Total blocked area too large; displaced cells re-piled around the hub |
| 10 | — | netlist: E36(b') single-tree (vs 9, same floorplan) | launched 08-31 ~16:00 | — | pre-launched to save time: the destination of most decision branches. Kill criterion: stage-03 forecast reads iter8-class (>10%H / hotspot >5k) |

Schematics for every iteration: `floorplans/draw_floorplans.py` → `fp_*.png`.

## Path to the default flow

The goal is that the winning recipe stops being env-override archaeology and
becomes what `run_v3.sh` (or a successor `run.sh`) does with no arguments.
Promotion checklist, in order, each gated on the previous:

1. **Iteration 8 passes (or nearly passes) the gate** → its floorplan+netlist
   pair is the recipe.
2. **Adopt E36(b) in `src/`** as the new RTL baseline: re-apply the diff
   (snapshot `20260831_e36b.tar.gz`, or replay the edit), run the full
   4-check regression, commit as the new frozen point (e35abcde+e36b).
3. **Point the flow defaults at the recipe**: `innovus/env.sh` pins the
   corner-2 E36(b) netlist (`20260831_015237`); `run_v3.sh` defaults
   `ASIC_FLOORPLAN` to the winning fp file; retire the `_PRESET_*`
   workaround once env.sh no longer clobbers.
4. **Fold the blockage into the floorplan file permanently** (it already
   lives in `fp_iter7.tcl`) and delete dead knobs (`ASIC_PLACE_MAX_DENSITY`
   did nothing — remove or document as no-op).
5. **Re-run stages 00–06 end to end from the defaults alone** (no env
   overrides) and require: gate pass, export completes, signoff STA at
   200 MHz. That run's numbers become the quoted result.
![iter5](floorplans/fp_iter5.png)
![iter6](floorplans/fp_iter6.png)

Innovus captures: `floorplans/iter*.gif` (gallery table in `FLOORPLAN.md`).

## Autopsies

### Iteration 4 (run `20260830_160055_v3b`)

- Type: ~35k SHORT + 15k SPACING. Layer: met2 > met1 > met3.
- Spatial: hub square. Net class: ~90% of report lines involve `FE_*`
  (opt-inserted) nets, 19% `CTS_*`.
- Global eGR overflow only 7.3% H → **local** over-density, not global
  shortage. ~13k region-spill cells stacked into the 840 µm hub.

### Iteration 5 (run `20260830_205109_iter5_ringhub`)

- Type: 65,499 SHORT + 33,896 SPACING + 562 MAR (+ 36 minor).
- Layer: met2 37.8k > met3 30.1k > met1 18.4k > met4 12.7k > met5 0.9k.
  **li1: 3 violations** — pin access is *not* a problem (hypothesis 5 closed).
- Net class (report lines): `FE_*` 90.8k, functional (`GEN_WAYS`/MSHR/…) 14.1k,
  `CTS_*` 12.9k.
- Post-route `timeDesign`: setup -3.964 / TNS -298 — routing detours ate 3 ns
  of the -0.949 placement. (Timing over shorted extraction is fiction anyway.)
- **Smoking gun**: the first pages of `drc.rpt` are one long **met1** wire of
  net `CTS_789` at y≈2280.5 shorting a picket-fence of `FE_*`/functional nets
  at ~1.4 µm intervals — a clock spine routed on met1 straight through the
  congested zone.

### Iteration 4 vs 5 — the hub bins (hypothesis 6 answered)

Violations per 500 µm bin (bin SW corner), same recipe both runs:

| bin | iter4 | iter5 |
|---|---|---|
| (1000,1000) | 11,107 | 13,933 |
| (1000,1500) | 7,700 | 16,454 |
| (1500,1000) | 6,945 | **24,042** |
| (1500,1500) | 5,784 | **22,965** |

Same hub bins, **~2× the intensity** — despite +25% hub area and the density
cap. Growing the hub let placement/CTS/opt pull *more* cells and wire into it.
Hub geometry and placement density are now both measured dead as levers.

## Controlled experiments

| experiment | result | lesson |
|---|---|---|
| `optDesign -postRoute` on iter4's gated route (`reports/postroute_exp/`) | DRC 50,524 → 136,482 (×2.7); v2 measured ×5.5 | post-route opt cannot fix routing DRCs and multiplies them; the 2000 gate is justified |
| Router-only repair, 28 `routeDesign` iterations on iter4's `05_route.enc` (scratch session 619cf9cc, `rr/route_repair.log`) | 50.5k → 48k → 36k → 31k → **plateau oscillating ~23–26k** from iteration ~20; +8.9k antenna | iteration halves the count and stalls: half the violations are detours, half are wires that cannot all exist. Demand > supply is not iterable-away |
| Density cap 0.62 in iter5 | `setPlaceMode -place_global_max_density 0.62` accepted; opt log shows nets "could not be fixed because of exceeding max local density" (cap enforced); hotspot forecast still worsened 4.5k → 7.9k | hypothesis 3 closed: the cap was honored and it is not the binding variable |

## Hypothesis scoreboard

| # | hypothesis | status | evidence / decisive test |
|---|---|---|---|
| 1 | **Layer supply**: met5 carries the PDN stripes, li1 excluded → ~4.5 signal layers over the hub; supply, not demand, is short | **MEASURED as the symptom** (G7-diag: 26% of hub tracks remaining vs ~56% outside, ~24k gcells completely full; per-layer split still unmeasured) | met5 has only 0.9k viols (signals barely use it). Test: per-layer congestion + track utilization over hub bins on iter5's `05_route_raw.enc` (G7-diag) |
| 2 | **Absolute convergence**: 4 ways × 128b victim/rdata buses + hit FIFO + CTS all meet in the hub | **LIVE — wire through-demand, not pins** (G7-diag: pin density clean, no bin > 0.5). | Test: pin-density map over hub (G7-diag); real fix is E36(b) per-way compare split (RTL) |
| 3 | density cap not honored | **REOPENED — accepted but ineffective**: density_map shows 36.5% of core bins placed at 0.95–1.00; `-place_global_max_density` bounds the global target only, regions/guides/opt blow past it locally. Hard fix = partial placement blockage (G7b) | see experiments table |
| 4 | **CTS spine through the hub** on low metal | **SUPPORTED**: met1 `CTS_789` picket-fence; 13% of report lines touch `CTS_*` | Fix: clock `route_type` met3–met5 + NDR before `ccopt_design` (G7a) |
| 5 | li1 exclusion breaks pin access | **CLOSED — no**: 3 li1 violations in 100k | — |
| 6 | did the hub bins move iter4→5? | **CLOSED — same bins, ~2× intensity** | table above |

## Generation 7 — attack plan

Ordered by cost; each answers a hypothesis before the next lap is bought.
postCTS timing is a solved problem (-0.949, hold clean) — **route DRC < 2000
is the only gate that matters now.**

1. **G7-diag** (~20 min, batch Innovus on iter5 `05_route_raw.enc`): per-layer
   congestion, hotspot map, density/pin-density over the hub bins. Decides
   between hypotheses 1 and 2 with numbers.
2. **G7a — clock layers** (~3–4 h, restarts from iter5 `03_place.enc`, the
   campaign-best placement, via `ASIC_PNR_FROM=04`): `create_route_type` clock
   met3–met5 + NDR, `set_ccopt_property route_type` before `ccopt_design`,
   then CTS → route. Tests hypothesis 4; keeps everything else frozen.
3. **G7b — PDN relief over the hub** (if G7-diag confirms hypothesis 1):
   stage-02 stripe pitch/width change over the hub region, then 03→05.
4. **G7c — E36(b) per-way compare split** (if hypothesis 2 survives G7-diag):
   RTL change (per-way AND-OR reduce, small central mux) → regression (both
   pressures, all four checks) → Genus → P&R. The structural fix for
   convergence; the only lever that shrinks what *must* meet in the hub.

Deadline context: signoff 2026-09-13; def-of-done can be "clean 200 MHz STA
signoff + DRC/LVS documented". iter5's placement is the asset to protect —
generations reuse its `03_place.enc` wherever the change allows it.

## G7-diag results (2026-08-31 01:38, iter5 `05_route_raw.enc`, `reports/diag/`)

All nine candidate reports worked (`diag_congestion.tcl`). The verdict:

- **Hub track supply exhausted**: inside the 940 µm hub square, only **26% of
  routing tracks remain free vs ~56% outside**, with ~24k gcells at zero
  remaining in each direction (`congest_area.txt`, 500 µm-hub awk). Hotspot #1
  bbox (1265,1439)–(1787,1961) = the NE hub quadrant — exactly the worst DRC
  bins.
- **Pin density is clean** — no bin above 0.5 (global 0.1285). The congestion
  is wire *through*-demand, not pin access.
- **The real culprit the cap missed**: `density_map` shows **36.5% of core
  bins placed at 0.95–1.00 cell density** (51% above 0.75), while the way
  *regions* average a healthy 0.577. The stacked bins are the hub/spill area:
  `-place_global_max_density 0.62` shapes the global placer target and did
  nothing locally. Hypothesis 3 reopened and answered properly: density IS a
  lever, but the knob is a **partial placement blockage**, not the mode switch.
- Global route usage 47.5/49.6% — abundant supply overall. Purely local.

**Plan revision**: G7b = re-place with `floorplans/fp_iter7.tcl` (fp_iter5 +
40% partial placement blockage over the hub, launched 2026-08-31 ~01:55,
stamp `20260831_g7b_hubblock`); PDN-pitch relief demoted to G7c pending a
per-layer split; E36(b) becomes G7d. G7a (clock met3–met5 + 2w2s NDR, from
iter5's placement) running in parallel — stamp `20260831_g7a_clklayers`.
`run_v3.sh` now honors a pre-set `ASIC_FLOORPLAN`.

### Iteration 7a autopsy (G7a, run `20260831_g7a_clklayers`, gate FAIL 402,306 markers)

100k-capped rpt: 74,129 SHORT + 25,741 SPACING; met2 45.2k > met3 24.7k >
met1 24.1k > met4 5.9k; same hub bins as iter4/5 at higher intensity (peak
32.3k at (1500,1000) vs iter5's 24.0k); `CTS_*` lines 9.2k (was 12.9k),
`FE_*` 92.6k. Clock NDR verified applied: 350 clock nets under `cts_2w2s`.
Lesson: on a supply-starved region, any demand-adding "fix" is a dose
increase. Remaining levers all REDUCE hub demand or raise hub supply:
G7b (density blockage, running), G7c (PDN pitch), G7d (E36(b) netlist,
verified + synthesizing).

### Iteration 7 autopsy (G7b, run `20260831_g7b_hubblock`, gate FAIL at 7,034 markers — the breakthrough)

2,606 SHORT + 247 SPACING (+ ~1,083 antenna in the marker count); layer met2
1.2k > met4 1.0k > met1 0.4k. **The violation geography left the hub**: top
bins are (500,2000) 955 and (0,2000) 772 — the NW edge, likely blockage-
displaced cells crowding the way1/way2 corner — while the old hub bins hold
only 82–183 each. Hold clean, postCTS -1.272 (the ~320 ps vs iter5 is the
blockage pushing hub logic apart — the congestion/timing trade, now measured).
Hypothesis 3 (density, in its reopened form) is CONFIRMED as the dominant
cause: a hard local density cap alone took the route from 133k to 2.9k.
Hypothesis 2 (convergence) is thereby bounded: real but manageable once local
density is controlled.

**Generation 8**: (a) G8-repair — router-only iterations on G7b's saved
`05_route.enc`: 2.9k is inside the regime where iteration converges (unlike
iter4's 50k plateau); target < 2000, ideally hundreds. (b) G7d/G8b — full run,
fp_iter7 + the E36(b) netlist (`20260831_015237`, victim cone deleted at the
source), aiming to cut the residue and win back timing simultaneously.

### Iteration 7r: router-only repair on iteration 7 — PLATEAU (hard residue)

Two more `detailRoute` passes with antenna diode fixing: markers 4,351 → 4,322
(final verify_drc 3,103 DRC viols + antenna = 7,425 markers). The residue is
UNCHANGED in place and kind: ~2.7k SHORTs, met2/met4, same three bins
((500,2000), (0,2000), (1000,500)), overwhelmingly `FE_OFN*` fanout-buffer
nets shorting **each other**. Verdict: not congestion the router can iterate
away but locally unroutable pockets — opt-inserted buffer clusters that the
40% hub blockage displaced into the way-region corners. Repaired DB saved
(`05_route_repaired.enc`).

Two candidate fixes, one already in flight:
- **G7d (running)**: same floorplan, E36(b) netlist — deletes part of the
  very populations that are shorting; may clear the corners on its own.
- **fp_iter8 (if G7d's residue persists)**: shape the blockage — e.g. grade
  it (40% core / 20% rim), or add small partial blockages at the three
  residue corners so displaced cells spread instead of piling.

### Iteration 8 autopsy (G7d, e36b netlist) — a *placement* catastrophe, not congestion creep

Route finished with ~2,029,826 live violations (rpt capped 100k: 82k SHORT,
met2 58.7k > met1 19.7k > met3 17.4k). NOT the hub, NOT iter7's corners: the
mass sits in the SOUTH band (bins (1500,500) 39k, (1000,500) 24k, (2000,500)
19k) — way0's wedge and the way0/way3 quadrant. Functional nets involved are
way0/way3 FTDA internals (word_valid_mem, rline_raw, tag banks); 88% of lines
are `FE_OFN*` opt buffers. Confirmed NOT the clock hook (no `cts_2w2s` in the
log; iter7 also had ccopt's own clock NDRs). Same floorplan, same flow, only
the netlist changed — and demand exploded: EstWL 23.8M µm vs 18.0M (+32%),
eGR overflow 19–20%H vs 6.4%, hotspot 24,469 vs 1,042 at route start.

Working theory: E36(b)'s victim capture builds TWO parallel AND-OR reduction
trees (vfree/vrepl) per field where the old form was one indexed mux. The
512b of per-way line/tag buses now feed two physically separate reduction
networks; placement pulled them apart and the buses effectively cross the
die twice, then postCTS opt (TNS -542 vs -221) buried the region in fanout
buffers. Synthesis (PLE) saw none of this: Genus scored e36b BETTER (-49.7
vs -59.3 WNS, area flat). **Lesson: netlist-level wiring *demand* is a PPA
axis PLE timing does not price; a logic win can be a routability loss.**

Options for the netlist axis (not launched): E36(b') = single AND-OR tree on
miss_way_onehot (one 2:1 deeper on the late path, but the same bus demand as
the original mux — keeps the encode/decode deletion without doubling wires).

### Iteration 9 (launched): corner damping on the proven recipe

fp_iter8.tcl = fp_iter7 + three 25% partial placement blockages over
iteration 7's measured residue bins (NW band and south pocket). Netlist:
e35abcde reference (the proven router). Goal: spread the FE_OFN corner piles
→ push 2,859 under the 2,000 gate.

### Iteration 9 autopsy — the dampers backfired

48,250 DRC (32k SHORT + 16k SPACING) / 99,479 markers. The geography INVERTED:
iter7's corner piles are gone, but the violations went back to the hub ring —
the top bins are the hub periphery. Mechanism: hub 40% + two 25% dampers
removed too much aggregate capacity near the center; the cells that must be
central re-piled in the remaining ring between blockages at higher density
than iter7 ever had. Placement forecast (1,150, campaign best) did not see it
— same lesson as iter4: tile-level forecasts miss local-density pile-ups.
postCTS -1.068 = best ring timing (the dampers helped timing while killing
routability). Lesson: blockage is not additive; total reserved area near the
center is bounded.

### Iteration 11 (launched 18:48): E36(b') on PLAIN fp_iter7

The screen's settled reading — **331 hotspot / 5.8% H, campaign best, on the
unmodified iter7 floorplan** — makes (e36bp × fp_iter7) the strongest
untested cell of the matrix. Iteration 11 CONTINUES the screen's run from its
saved 03_place.enc (ASIC_PNR_FROM=04, same stamp) — no re-place, CTS + route
only, gate ~21:30. Iteration 10 (e36bp × damped fp_iter8) continues in
parallel: its lighter netlist may survive the dampers where e35 did not; its
gate is the (damper × light-netlist) data point either way.

## Methodology: the placement sweep (2026-08-31 evening)

**Why.** Iterations 7 and 9 steered congestion with hand-carved
`createPlaceBlockage` geometry. Reading `03_place.tcl` afterwards showed the
flow set only `place_global_place_io_pins` and `legalization_inst_gap 1` -
**Innovus's own congestion machinery was at defaults for all eleven
iterations**, and `setOptMode` had no congestion awareness at all, so
post-CTS optimisation buffered freely into congested regions (the mechanism
behind iterations 8 and 9). The professional escalation order is the reverse
of what we did: effort knobs and cell padding first, manual geometry last,
RTL and area after that. The sweep opens that untouched axis.

**Design.** One design point held fixed - E36(b') netlist x plain `fp_iter7` -
so the only difference between arms is the knob set. Control is already
measured: the iteration-11 placement (settled post-place **7,174 / 12.6% H**).
`cong_effort=high` is held across all arms, so arm B vs control isolates it;
padding and opt-congestion then vary as a 2x2 factorial:

| arm | place_global_cong_effort | legalization_inst_gap (padding) | extra |
|---|---|---|---|
| control (iter 11) | default | 1 | — |
| B | high | 1 | — |
| C | high | **2** | — |
| D | high | **4** | — (padding dose-response) |
| E | high | **2** | max_density 0.55 |

**Arms D/E were redefined 30 min in — and this is the sweep's first result.**
They originally carried `setOptMode` congestion effort; **Innovus 21.16 rejects
BOTH spellings** (`-congEffort` and `-congestionEffort`), so the arms had
silently degenerated into duplicates of B and C. The catch-wrapper caught it
and `reports/place/cong_knobs.txt` reported it, which is exactly why the hooks
were written that way - an unguarded `setOptMode` would have crashed four
2-hour placements instead. **Finding: there is no opt-stage congestion knob in
this build; post-CTS optimisation cannot be made congestion-aware by a mode
setting.** That closes one of the two axes the sweep set out to test, and it
means the iterations 8/9 buffer-flood mechanism can only be attacked through
placement (padding/effort) or through the netlist, not through opt settings.
Always read `cong_knobs.txt` before trusting an arm.

Stages 00-03 only (~2 h/arm), four arms in parallel: `./sweep_place.sh`
(subset: `./sweep_place.sh B D`). Compare with
`python3 innovus/scripts/forecast_table.py`.

**Implementation.** `03_place.tcl` gained `ASIC_PLACE_CONG_EFFORT`,
`ASIC_PLACE_INST_GAP` and `ASIC_OPT_CONG_EFFORT` hooks. They are **default
off** - with no env set the stage emits nothing new, so iterations 1-11 stay
comparable. Each setting is catch-wrapped (option spellings vary across
Innovus builds; an unknown option must not cost a 2-hour placement) and what
actually applied is written to `reports/place/cong_knobs.txt`.

**Decision rule.** Best settled post-place hotspot/overflow wins; ties broken
by preCTS WNS. The best one or two arms continue 04-05 (CTS + route) on the
same stamp via `ASIC_PNR_FROM=04`, exactly as iteration 11 continued the
screen - no re-placement. If no arm beats the control materially, the axis is
closed and the campaign falls back to the iteration-7 recipe plus targeted
ECO on its 2,859.

**Caveat carried from iterations 4 and 9.** A good forecast is necessary, not
sufficient: both routed far worse than their forecasts implied because their
killer was sub-tile local density. Any arm that wins here must ALSO be checked
with `reportDensityMap` (bins at 0.95-1.00) before it is trusted.

## Overnight 2026-08-31 -> 09-01: four tracks

| track | run | tests | why it matters |
|---|---|---|---|
| **12** | `20260831_iter12_e35_fp7_conghigh` | e35 x fp_iter7 x `cong_effort=high` | **the direct gate shot**: one variable added to the campaign's best route (iter 7, 2,859). If the tool's own congestion effort closes an 859-violation gap, the campaign is over |
| sweep + continue | `sweep{B,C,D,E}` then `cont*` | E36(b') x fp_iter7 x knob arms; best 2 auto-continue to CTS+route (`sweep_continue.sh`) | whether the placer can give E36(b') an iteration-7-quality placement - that would pair the campaign's best TIMING (-0.714) with its best routability |
| 11 | `20260831_e36bpscreen` | E36(b') x fp_iter7, default knobs | already past CTS at **-0.714 setup / hold clean - first run under the 200 MHz bar**; its route number calibrates the netlist against iteration 7 |
| export | `export_iter7.tcl` in the iter-7 run dir | stage 06 on iteration 7's gated route | **first GDS of the v3 flow.** Not clean (carries 2,859 violations) - it proves the back end and gives Magic DRC / netgen LVS a real target, so the 9/13 deliverable does not depend on winning the congestion fight first |

Morning triage order: iteration 12's gate, then the continued arms', then
iteration 11's, then whether the GDS exists. Any gate under 2,000 promotes to
"Path to the default flow"; otherwise the best-DRC run plus targeted ECO, with
the exported GDS carrying the deliverable.

## Iteration 11 verdict: the E36(b') netlist is better, and still not good enough

61,670 DRC / 127,446 markers on plain `fp_iter7` - the floorplan where the
e35 netlist routed to **2,859**. Same geometry, same knobs, only the netlist
differs, so the attribution is exact:

| netlist on fp_iter7 | postCTS WNS | route DRC |
|---|---|---|
| e35abcde (iteration 7) | -1.272 | **2,859** |
| E36(b') single tree (iteration 11) | **-0.714** | 61,670 |
| E36(b) dual tree (iteration 8) | -1.512 | 2,133,467 |

The single-tree repair was worth **34x** against E36(b) - but it is still
**21x worse than the netlist it replaced**. So the conclusion is not "the dual
tree was the bug"; it is that **restructuring the victim select into AND-OR
reduction at all costs routability on this floorplan**, and the dual tree
merely made it catastrophic. The indexed mux that E36 set out to delete was
apparently doing something useful physically: it kept the 512-bit per-way
line/tag buses terminating at ONE place instead of fanning into a reduction
network spread across the hub.

The forecast called it again (post-CTS 3,210 -> "tens of thousands"), which
strengthens the calibration table: at this sample point the only outliers
remain iterations 4 and 9, both sub-tile density failures.

**Consequence for the campaign.** E36(b') keeps its timing crown (-0.714,
the only run under the 200 MHz bar) but cannot be promoted on routability.
The two axes have now traded places: the best-timing netlist routes worst,
and the best-routing netlist (e35) has 270 ps less margin. Whether that gap
matters depends on post-route optimisation, which no run has reached yet.

**Overnight priority therefore shifted to the e35 netlist**: iteration 12
(e35 x fp_iter7 x `cong_effort=high`) and iteration 13 (same + `inst_gap=2`,
queued behind the sweep arms) test the new congestion knobs on the netlist
that actually routes. The four E36(b') sweep arms still run - they answer
"can placement effort rescue a wire-hungry netlist?", which is worth knowing
either way - but they are no longer the lead horse.

## Sweep result (arms B and C settled, 2026-08-31 22:42) — the knob BACKFIRED

Settled post-place readings, all on the same design point (E36(b') x
`fp_iter7`), control = iteration 11's placement:

| arm | knobs | settled place hotspot / ovf H |
|---|---|---|
| control (iter 11) | default | **7,174 / 12.6 %** |
| B | `cong_effort=high` | **13,271 / 15.0 %** |
| C | `cong_effort=high` + `inst_gap=2` | **16,924 / 15.5 %** |
| D | `cong_effort=high` + `inst_gap=4` | 12,015 / 14.0 % |
| **E** | `cong_effort=high` + `inst_gap=2` + **`max_density 0.55`** | **2,251 / 7.9 %** |

**`place_global_cong_effort high` made congestion ~1.9x WORSE than the
default**, and adding cell padding made it worse again. That is the opposite
of the intent, and it is a real answer to the question the sweep was built to
ask: the tool's congestion machinery is not an unused lever waiting to help -
on this design it actively hurts. (Plausible mechanism: high congestion effort
trades wirelength for spreading, and on a design whose problem is *local*
convergence around a blocked hub, spreading lengthens the very buses that are
saturating - the same trap iteration 5 fell into by enlarging the hub.)

**Do not read D and E from the table until they exit** - those runs are still
placing and their table row shows the latest mid-placement reading, which is
exactly the dip-versus-settled trap recorded above. Only rows whose run has
exited are settled values.

**Consequence for the runs in flight.** Iterations 12 and 13 both carry
`cong_effort=high` on the e35 netlist (13 also adds padding). If the effect
transfers across netlists, both are compromised - iteration 7 with DEFAULT
knobs settled at 3,156 and routed to 2,859. The decision data is iteration
12's own settled post-place number, due when it reaches `ccopt_design`:

- settles **above ~3,156** -> the knob hurts here too; kill iteration 13
  (which stacks the padding arm C showed is worse still) and treat the
  congestion-knob axis as closed-negative;
- settles **below 3,156** -> the effect did not transfer, and iteration 12 is
  a real shot at the gate.

## Sweep verdict (all four arms settled, 2026-08-31 23:00): the density cap wins

Arm **E beat everything, including iteration 7's e35 placement**:

| run | settled place hotspot / ovf H |
|---|---|
| **E: cong=high + gap 2 + max_density 0.55** | **2,251 / 7.9 %** |
| 7: e35, DEFAULT knobs | 3,156 / 8.5 % |
| 11 control: e36bp, default knobs | 7,174 / 12.6 % |
| D: cong=high + gap 4 | 12,015 / 14.0 % |
| B: cong=high | 13,271 / 15.0 % |
| C: cong=high + gap 2 | 16,924 / 15.5 % |

**The differentiator is `max_density`, not congestion effort.** C and E are
identical except for the density cap, and it moved the number 16,924 -> 2,251,
a **7.5x** improvement. Congestion effort ALONE (B) and with padding (C, D)
made things 1.7-2.4x worse than the default.

**Hypothesis 3, third revision.** Iteration 5 measured `max_density 0.62`
alone as honored-but-useless. It is not useless - it needed either the tighter
value (0.55), the congestion objective active alongside it, or both. The
global density knob and `cong_effort` are only useful *together*; each alone
is neutral-to-harmful. This is the first knob combination in the campaign that
beats hand-carved blockage geometry at its own game (arm E still sits on
`fp_iter7`, so it is blockage AND density cap, not either alone).

**Queue consequences, applied 2026-08-31 23:03:**
- arm E continued through CTS + route (`contE`) - its gate is the test of
  whether a 2,251 placement finally routes clean;
- **iteration 13 cancelled before it started** - it was arm C's losing recipe
  (cong+padding, no density cap) on the e35 netlist;
- **iteration 14 queued** (`20260901_iter14_e35_fp7_armE`): arm E's exact knob
  set on the **e35 netlist** - the campaign's best-routing netlist with its
  best-placing knobs, on the proven floorplan. It starts when iteration 12
  frees a slot;
- **iteration 12 settled at 8,664 / 11.4 %** against iteration 7's 3,156 / 8.5 %
  (same netlist, same floorplan, only `cong_effort=high` added): the knob makes
  the e35 netlist **2.7x worse**, so the effect transfers across netlists and
  the congestion-effort axis is **closed negative on both**. Stopped 23:34 to
  free its slot for iteration 14.
- **arm E's continuation reached post-CTS at 279 hotspot / 4.6 % H** - against
  iteration 7's 1,042 / 6.5 %, which routed to 2,859. That is 3.7x better than
  any pre-route reading in the campaign and, on the calibration curve, points
  at a route in the low hundreds.

## CAVEAT on the two overnight exports (2026-08-31 23:45)

Both iteration 7 and iteration 11 exported a full artifact set, but **through
different extraction engines**, so their Tempus numbers are NOT directly
comparable:

| | iteration 7 | iteration 11 |
|---|---|---|
| gds / def / sdf / v | 368M / 349M / 118M / 42M | 371M / 350M / 115M / 42M |
| **spef** | **262 MB, Quantus** (`ASIC_QRC_TECH` set, both corners updated in-session) | **793 MB, LEF-based** (`ASIC_QRC_TECH` never set by `export11.sh`) |

The 3x SPEF-size gap has two candidate causes that are not separated yet:
iteration 11's route is far more congested (61,670 violations = enormous
detour/jog count = more RC segments), and the engines differ. Do not read the
size difference as evidence for either until they are extracted the same way.

**To fix before quoting any iteration-7-vs-11 signoff comparison:** re-run
iteration 11's export with `ASIC_QRC_TECH` set, exactly as iteration 7's was:

```bash
ASIC_QRC_TECH=$REPO/asic/signoff/quantus/techfiles/sky130A_nom.tch \
  asic/PnR/export_route.sh 20260831_e36bpscreen_ss1v76_d1p5 <e36bp netlist>
```

Tonight's Tempus run on iteration 11 still has standalone value (it is a real
signoff STA of the best-timing design) - it just cannot be differenced against
iteration 7's.

## 2026-09-01: the gate was counting stacked markers - iter14 actually PASSES

**Morning gate readings vs reality.** The stage-05 gate counts
`dbGet top.markers`, on the assumption that verify_drc's markers are the only
ones on the design. That held for iteration 7 (gate 2,859 = verify_drc 2,859)
and iteration 11 (61,670 = 61,668), because those were single-pass runs. It
does NOT hold for runs that came through `sweep_continue.sh` (restored
03_place.enc, re-ran CTS+route): stale markers from the earlier pass plus
NanoRoute's own antenna/check markers stack under verify_drc's. Corrected,
like-for-like (verify_drc geometry count):

| run | gate read (top.markers) | verify_drc | antenna |
|---|---|---|---|
| iter7 (e35 x hub-blockage) | 2,859 | 2,859 | 1,106 |
| iter11 (e36b' x fp_iter7) | 61,670 | 61,668 | 3,395 |
| contE (e36b' x fp7 x armE) | 8,437 | **3,377** | - |
| iter14 (e35 x fp7 x armE) | 2,375 | **706** | 860 |

Consequences:
- **ITER14 IS UNDER THE GATE: 706 <= 2,000.** First run of the campaign to
  pass on the metric the gate was designed around. 4x better than iter7
  (2,859), the previous best. Breakdown: 684 SHORT / 20 SPACING / 1 MINWIDTH /
  1 NSMETAL. Post-route (pre-opt) timing: setup WNS -2.372 all / **-0.516
  reg2reg** (implied reg2reg Fmax ~249 MHz), hold -2.174 (not yet fixed - opt
  had not run).
- **contE's "forecast miss" shrinks**: 279 post-CTS hotspot -> 3,377 routed
  (not 8,437). Still a miss vs the low-hundreds prediction, and e36b' still
  routes worse than e35 on identical knobs (3,377 vs 706) - the netlist
  conclusion stands.
- **Gate fixed** in 05_route.tcl: `clearDrc` now runs immediately before
  verify_drc, so top.markers at the gate is verify_drc's count alone.

**Iteration 14 finished properly.** Its gated route was exported in the
morning (Quantus SPEF - 253 MB, same engine as iter7's, so those two ARE
Tempus-differenceable; artifact set gds 354M / def 338M / sdf 115M / v 41M).
After the gate misfire was found, post-route opt (setup+hold) + re-export was
launched in-place: `runs/20260901_iter14_e35_fp7_armE/opt_and_export.tcl`
(tmux `iter14_opt`), reports land in `reports/postroute_opt/`, checkpoint
`05_route_opt.enc`, outputs/ overwritten with the optimised artifact set.

**Overnight housekeeping.** The Tempus signoff chain never ran: sta.tcl
referenced `runs/<stamp>/scripts/innovus_config.tcl` (does not exist -
scripts live in `innovus/scripts/`), died at 23:38, sat until TERM'd ~11:58.
Fix the path and rerun on iter7 (Quantus SPEF already on disk) and iter14
post-opt. export11's SPEF remains LEF-based (828 MB) - re-export with
ASIC_QRC_TECH before quoting any 11-vs-7/14 signoff comparison.

**Presentation renders.** `asic/signoff/GDS11_Image/render_gds.py` renders
any run's exported GDSII through KLayout 0.30.7 (pip module, headless) into a
mm-ruled frame with a pre-signoff sheet (die size, std-cell/macro counts,
corners+derates, verify_drc breakdown, antenna, setup/hold, provenance
footer). Images for iters 7, 11, 14 are in that folder; future ones go there
too.

## First corrected Tempus signoff: iter7, propagated clocks (2026-09-01 ~15:00)

sta.tcl fixed (propagated clocks + post-CTS uncertainties 0.100/0.050, mirroring
04_cts.tcl; stage 06 now also exports as-implemented per-view SDCs). Tempus on
iteration 7's gated, UNOPTIMIZED route, Quantus SPEF, ss_n40C_1v76 / ff_n40C_1v95:

| group | setup WNS/TNS/#vio | hold WNS/TNS/#vio |
|---|---|---|
| REG2REG | **-4.291 / -7,043 / 16,936** | **-0.209 / -2.4 / 56** |
| IN2REG | clean | -3.116 / -1,993 / 1,206 |
| REG2OUT | -7.781 / -731 / 107 | clean |

- REG2REG is the meaningful pair: setup -4.291 on a route that never had
  post-route opt (repeater chains with 1.2-1.8 ns inv_2 stages on detoured
  nets - Quantus RC the LEF estimate missed), hold only -0.209 (opt-fixable).
- The PORT groups are now latency artifacts, not measurements: clock insertion
  delay is 7.433 ns (!), and the I/O budgets reference the ideal edge, so
  in2reg setup gets the whole tree depth as free time (clean) while reg2out
  setup and in2reg hold get charged it (-7.8 / -3.1). Before quoting port
  timing, the I/O reference needs a latency-matched virtual clock
  (set_clock_latency ~= insertion delay on the I/O clock) - standard OOC
  practice. Filed as a constraints TODO; does not affect reg2reg.
- 7.433 ns insertion delay is itself a finding worth revisiting at CTS
  (ccopt target, tree depth through 350k cells at ss/1.76V).
- Ideal-clock first run (superseded, for the record): reg2reg -5.658, "hold
  clean +0.127" - the +0.127 was structurally optimistic, real answer -0.209.

## PRIORITY DECISION 2026-09-01 (user call): DRC-clean over Fmax

Zero violations beats hitting 250 MHz - a clean GDS at ~210 MHz is a finished
chip; a fast dirty one is not. Consequences:
- iter14 full opt (running) is now the OPTIMISTIC arm: keep it only if its
  final DRC pattern ECOs to zero (it had closed reg2reg setup to +0.004 at
  4.0 ns mid-run, at a cost of ~8k transient route violations).
- FALLBACK ARM (matches the priority directly): restore 05_route.enc (706
  viols, reg2reg -0.516 = ~221 MHz on the Quantus-corrected timer),
  hold-only optDesign, ecoRoute -target to zero, export. Fmax = whatever
  Tempus reports on the clean database; no target-chasing.
- Hold fixing is non-negotiable either way (hold fails are functional at any
  frequency); setup shortfall is a reporting matter, not a defect.

## Iteration 15 launched (2026-09-01 ~23:15): fp_iter15 = fp_iter7 + cluster damping

Rationale closed tonight: arms B and C independently plateaued at 627/~624
from the clean 706 route (hold-only + eco-target, two different hold libs) -
the clusters are INHERENT to fp_iter7's geometry, not opt-induced. Arm A's
setup opt made it 5x worse (3,375 post-setup, hold phase oscillating ~6.1k).
Surgery (density relief on the routed DB) is still running; iter15 applies
the same relief PRE-placement instead, per the fp_iter8 precedent:
`fp_iter15.tcl` = fp_iter7 verbatim + 50% partial blockages over the four
measured cluster boxes (ring-corner convergence zones + two macro seams).

Run: `20260901_iter15_e35_fp15_damp`, tmux `iter15`. Arm E's exact knobs
(cong_effort=high, inst_gap=2, max_density=0.55, e35 netlist, no CTS NDR -
verified no logged session ever enabled the G7a hook), stages 00->05 with
**ASIC_DRC_GATE=0** so the flow routes and STOPS - no opt of any kind. Judge:
raw-route verify_drc vs fp_iter7's 706. Below ~700 and clustered less =>
hold-only continuation (armC recipe); zero-ish => straight to antenna ECO +
export + signoff triplet. Setup opt stays banned on respins.

Decision tree tomorrow AM: surgery clean -> surgery wins, iter15 becomes the
backup. Surgery dirty + iter15 < 706 -> iter16 tunes geometry (FP8.md menu:
die bump for the NE corner vs per-row GAP). Both dirty and >= 706 -> the
damping thesis is wrong, regenerate the pattern plot and rethink from data.

## Surgery FAILED (2026-09-02 ~06:00): >=100,000 violations (report cap), export withheld

Arm B act 2 is dead, and instructively so. The 46k-instance refinePlace
scramble (mean move 185 um) dirtied so much routing that ecoRoute became a
near-full re-route under the new density screens - and it could not close:
final verify_drc capped at 100,000, dominated by met1 metal shorts and
via3/via4 cut shorts clustered around GEN_WAYS[3] tag-bank nets (the same
right-row/NE-corner zone as always, now 100x worse). Post-route density
relief is now CLOSED as an approach: evicting placed cells after routing
destroys more connectivity than the freed tracks recover.

Standing scoreboard for fp_iter7: best databases are armC's 571
(hold-only, reg2reg setup +0.699, saved at iter14c 05_route_opt.enc) and the
original 706 route. KLayout (2026-09-02, signoff/drc/drc.md) proved these
counts are ~all SHORTS, not spacing - geometry outside macros is ~9 items.
ALL fp7 hopes now ride on **iter15** (pre-placement damping, placing now).
If iter15's raw route does not beat 706 decisively, escalate to iter16 =
geometry relief (FP8.md): the NE-corner convergence zone needs actual space.

Evidence preservation: armE outputs/ (the noon filled GDS that klayout_drc/
and lvs results reference) copied to outputs_noon_20260901_prefillGDS_signoff_ref/
before Arm A's export can overwrite it. Arm A itself oscillates ~7k in its
hold phase - recommend killing tmux iter14_opt to free a core-heavy slot;
its completion has zero win probability.

## Arm A closed (2026-09-02 10:24): 4,811 viols, setup +0.004 - dominated by Arm C on both axes

Full post-route opt finished: verify_drc 4,811, reg2reg setup barely positive
(+0.004). Arm C (hold-only, same starting route): 571 viols, +0.699 setup.
The optimized database is 8x dirtier AND 0.7 ns slower - setup opt's cell
insertion forced repair reroutes that repeatedly destroyed its own gains.
Setup-opt-on-fp7 is closed with prejudice. NOTE: Arm A's stage 06 export
OVERWROTE armE outputs/ with the dirty GDS; the noon signoff-reference GDS
survives in outputs_noon_20260901_prefillGDS_signoff_ref/. fp7 scoreboard
final: armC 571 / +0.699 is the lineage's best; everything now rides on
iter15 (placing) then iter16 (FP8.md) if needed.

## iter15 post-place: damping BACKFIRED globally; iter16 (die 2780) launched (2026-09-02 ~13:00)

iter15 post-place overflow: **219,755 = 16.40% H + 7.42% V** vs armE's
103,721 = 7.18%/4.13% at the same stage - the four 50% screens (on top of the
hub blockage and the 0.55 global cap) robbed enough capacity to DOUBLE
congestion. On the campaign calibration curve (7.18%H->706, 12.6%H->8,664)
that forecasts a catastrophic route. iter15 continues through CTS/route
anyway for the residual map + curve confirmation (gate=0 stops it pre-opt).

iter16 launched per FP8.md's geometry rung: `fp_iter16.tcl` = fp_iter7 with
the die as a knob (`ASIC_FP_DIE`, default/used **2780** vs 2700; rows,
wedges, hub group and hub blockage all recompute) and deliberately NO
damping boxes. Run `20260902_iter16_e35_fp16_die2780`, tmux `iter16`, armE
knobs, gate=0, stages 00->05. First run to self-record knobs.txt.
Hypothesis: the ~600 corner shorts need SPACE at the ring-corner
convergence zones, not density pressure anywhere.

Tempus port-timing methodology CLOSED same hour (signoff README): round 5b
clean - correlated-external vclk (late=early=11.901, measured ff-early 4.318
recorded), reg2out hold deferred; IN2REG setup honest (-4.028), REG2OUT
setup passes at the 0.3 budget, no phantom holds. Five validation rounds,
four script bugs + one modeling artifact fixed on iter7's corpse.
