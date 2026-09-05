# Iteration 17 — plan (brainstorm 2026-09-04 16:50; launched 18:03; GATE FAILED 23:05; iter17b = die 2980 launched 23:11)

**Result 2026-09-04 23:05:** route gate FAILED at 134,154 markers (100k
reported): met2 52 % / met3 21 % / met1 16 % / met4 10 % / met5 < 1 %; 79 %
metal shorts; 48 % in the wedges, 44 % in the ring band, 2.6 % inside macro
bodies (the blockages worked), 67 % in three ring corners. Cause: EDGE 80 on
the same 2900 die shrank every corner pocket from 151 to 111 um a side while
the blockages closed the through-body escape. Timing was the campaign's best
(post-route reg2reg +1.246 vs 16b +0.916). D4 therefore reversed:
**iter17b = iter17 + ASIC_FP_DIE=2980** (pockets back to 151 um) + the li1
fixes (bounded sroute, li1-OBS LEF), launched 23:11 as
`20260905_iter17b_e35_fp17_die2980_1v76`, tmux `iter17b`.

**Launched 2026-09-04 18:03** (user: "go with your recommendations on D1-D6"):
run `20260904_iter17_e35_fp17_die2900_1v76`, tmux `iter17`, 4.0 ns, ss_n40C_1v76,
`floorplans/fp_iter17.tcl` (ASIC_FP_EDGE=80, macros flipped, met1-met4 route
blockages 3 um inset per macro body), `02_power.tcl` horizontal straps via
`ASIC_PG_STRIPE_H_LAYER=met5 ASIC_PG_STRIPE_H_PITCH=60` (width 2, spacing 2),
otherwise iter16c's launch line minus `ASIC_PNR_SDC`. Log
`innovus/runs/<stamp>/logs/flow.log`. Gate criteria: section 5.

Purpose of this page: say what iter16b, iter16c and the proposed iter17
are, what differs between them and why, and list the decisions still open,
before a single script is written. The campaign discipline is one
variable per iteration (`DRC.md` scoreboard); iter17 deliberately breaks
it, and this page says where and why.

## 1. What exists

| | iter16b (signed off today) | iter16c (running since 14:50) | iter17 (proposed) |
|---|---|---|---|
| purpose | 9/13 package: DRC 0, timing signed off | "what does 3 ns cost": same recipe, faster clock, right corner | fix the two structural findings of the day |
| floorplan | fp_iter16: macro ring, wedges, 40 % partial blockage over hub | same | fp_iter17: same ring, macros flipped, wider edge margin, blanket route blockages over macro bodies |
| die | 2900 um | 2900 | 2900 (open: 2980) |
| edge margin (macro to die) | 40 um | 40 | 80 um (open: 120) |
| macro orientation | 70-pin edge faces the margin | same | 70-pin edge faces the core |
| route blockages over macros | none (router threads 300-720 nets per macro body) | none | met1-met4 blanket, 3 um inset, PG excepted |
| PDN | met4/met5 ring 4 um; met4 vertical stripes 2 um @ 60 um; no horizontal straps | same | + horizontal met5 VDD/VSS straps across the macro ring into the hub (pitch from the what-if, section 3) |
| clock | 4.0 ns | 3.0 ns | 4.0 ns (open: 3.5) |
| setup corner in P&R | ss_100C_1v60 (launch omission) | ss_n40C_1v76 | ss_n40C_1v76 |
| macro derate | x1.5 late / x0.67 early | same | same |
| netlist | Genus 20260828_151051 e35abcde (ss1v76) | same | same |
| density cap / cong effort / inst gap | 0.55 / high / 2 | same | same |
| CPUs | 1 (23 h to route) | 16 | 16 |
| stop | stage 05 (route), DRC gate off | same | same |

## 2. Why each iter17 change — the evidence

1. **Macros flipped + blanket route blockages.** `DRC.md` "Floorplan lesson
   for iter17" (09-03): NanoRoute threads signals through the SRAM
   interiors because the LEF OBS is shape-level with gaps and there is no
   met4 OBS; every one of iter16b's last residual DRCs was a threading
   artefact and closing them took ten legalisation passes. Blanket
   blockages remove the interiors, but the router was using them to
   escape the port-0 pin edge that faces the 40 um margin. LEF pin census
   (this page, 16:40): **S edge 70 signal pins, N edge 34, W 9, E 8.**
   fp_iter16 puts the 70-pin edge at the margin (bottom row R0, top R180,
   left R270, right R90). Flip every macro (R180 / R0 / R90 / R270): the
   70-pin edge faces the core, the 34-pin edge faces the margin, and the
   margin grows 40 -> 80 um so those 34 can escape without the interior.
2. **Horizontal met5 straps.** Voltus static IR on iter16b (`voltus.md`,
   "First static IR result"): ring-as-supply VDD 119 mV / VSS 121 mV
   worst against a 53 mV budget; <3 mV of it in met5; the whole hub inside
   the macro ring in the worst band, fed through the four corner gaps.
   The PDN has vertical met4 stripes only, and the macro ring interrupts
   them. met5 is free over the macros (no met5 in the macro LEF), so
   horizontal met5 straps ring-to-ring carry supply across the macros into
   the hub and stack down to the hub's met4 stripes. Pitch is being sized
   now on iter16b's own database (section 3). Cost: ~2 met5 tracks per
   pitch; at 120 um pitch that is ~6 % of met5, the layer the DRC campaign
   worried about - `DRC.md` hypothesis 1 is closed the other way (met5 is
   under-, not over-provisioned into the hub).
3. **Campaign corner from stage 00.** iter16b was placed and routed at
   ss_100C_1v60 by omission (corner audit 09-03). iter16c already fixes
   this; iter17 keeps it. This is the one change that is "free".

## 3. Measured before launch: the strap pitch (Voltus what-if, 16:47-17:05)

`static_rail.tcl` with `VOLTUS_WHATIF_M5_PITCH`: horizontal met5 VDD/VSS
what-if wires (2 um, spacing 2) across the full core plus auto-vias on
every met4/met5 crossing (one net per via call - VOLTUS_ERA-3058; wires
without vias float and change nothing), imported into the rail solve on
iter16b's own `06_final.enc`. Ring as supply, macros excluded, as in the
baseline.

| VDD | worst drop | average | met5 share of the drop |
|---|---|---|---|
| baseline, no straps | 119 mV | 78 mV | 0.2 mV |
| straps @ 120 um | 65 mV | 41 mV | 64 mV (the straps are now the bottleneck) |
| straps @ 60 um | **47 mV** | 29 mV | - |
| budget 3 % | 53 mV | | |

VSS mirrors VDD at 120 um (66 / 42 mV); 60 um VSS pending at the time of
writing. **D5 = met5, 2 um wide, 60 um pitch** (~12 % of met5 tracks).
Margin under budget is 6 mV with the macro current still excluded, so
iter17's own Voltus run may want 4 um straps at the same pitch; that is a
knob, not a redesign. Results: `signoff/results/<stamp>/voltus_whatif_m5p{120,60}/`.

**EM (assumed limits, `voltus.md` "EM screen"):** worst J/Jmax 4.5 on both
rails, all at the hub corner feeds and the inter-macro channels - the same
few 2 um met4 stripes that set the IR drop. The straps fix both; iter17's
own Voltus run repeats the screen.

## 4. Decisions open (owner: user)

| # | decision | recommendation | why |
|---|---|---|---|
| D1 | clock 4.0 or 3.5 ns | **4.0** | iter16c is the speed experiment; iter17 is the structural fix and should be judged against iter16b at equal clock. 3.5 later, on whichever floorplan wins. |
| D2 | bundle flip+blockages with PDN straps, or split (17a PDN only, 17b flip) | **bundle** | 9 days left; both target the same object (the macro ring as a wall, for routing and for supply). If it fails the route gate, the DRC pattern (threading vs not) tells which half; if IR fails, the straps are the only PDN variable. |
| D3 | edge margin 80 or 120 um | **80** | 34 pins on a 376 um edge with an 80 um strip is comfortable; 120 shrinks the wedges by another 80 um each side at a 55 % density cap. |
| D4 | die 2900 or grow | **2900** | keep comparable to 16b/16c; the margin growth (+40 x 2) comes out of the wedges, which iter16 (die 2780) showed tolerate more. |
| D5 | strap pitch | **60 um, 2 um wide** (measured, section 3) | 47 mV worst vs 53 budget; 120 um leaves 65 mV |
| D6 | launch tonight or after iter16c's route gate | **tonight** | 16 CPUs: place ~4 h, CTS ~3 h, route ~2 h -> gate by Saturday morning; iter16c and iter17 fit on the machine together (128 cores, 450 GB free). |

## 5. What iter17 has to show to be worth keeping

- Route-stage `verify_drc` <= iter16b's 38 at the gate, and residuals NOT
  inside macro bodies (the blockages did their job).
- Voltus static IR (same script, ring-as-supply, macros excluded) worst
  drop <= 53 mV, or at least the hub no longer the worst band.
- Tempus SI at both corners: setup and hold positive at 4.0 ns, hold >=
  iter16b's +0.010.
- Then the same chain as today: legalize if needed -> antenna -> export ->
  KLayout / LVS / Tempus / Voltus.

If it fails the gate badly (iter16b-class 640k markers), iter16b stays the
9/13 package and iter17 becomes the post-9/13 campaign opener; nothing is
lost but a night of machine time.

## 6. Recipe (to be written as scripts only after D1-D6)

- `floorplans/fp_iter17.tcl` = fp_iter16 + `ASIC_FP_EDGE` (80) +
  orientation map flipped + `createRouteBlk -layer {met1 met2 met3 met4}
  -exceptpgnet` per macro body (3 um inset so edge pins stay reachable).
- `02_power.tcl` + knobs `ASIC_PG_STRIPE_H_LAYER=met5`,
  `ASIC_PG_STRIPE_H_PITCH=<D5>`, width 2 spacing 2, default off so no other
  run changes.
- launch = iter16c's command with `ASIC_PNR_SDC` unset (4.0 ns),
  `ASIC_FLOORPLAN=fp_iter17.tcl`, `ASIC_FP_EDGE=80`, the two PG knobs,
  stamp `20260904_iter17_e35_fp17_die2900_1v76`.
