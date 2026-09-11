# FLOORPLAN.md - the macro ring, and why it caps the frequency

Written 2026-09-07 21:50 from the first honest placement numbers (timer fixed,
see `CTS.md` section 5). Companion to `DRC.md` (routability history of the
same floorplan) and `CTS.md` (tree). Nothing here is implemented yet.

## 1. What the floorplan is (`../floorplans/fp_iter16.tcl`, iter7 geometry + die knob)

- Die 2900 x 2900 um (`ASIC_FP_DIE`), core margin 16 um.
- 16 SRAM macros (`sram_1rw1r_32_256_8_sky130`, 376.5 x 446.2 um each,
  2.69 mm2 = 32.7 % of the core) placed as a **ring**: one way per die edge,
  four banks in a row along that edge, 40 um between banks, 40 um from the
  edge, 8 um halo, orientation chosen so `dout1` faces inward.
  way 0 bottom (y=40), way 1 top (y=2413), way 2 left (x=40), way 3 right
  (x=2413); bank columns at x/y = 637, 1053, 1470, 1886.
- Soft "wedge" regions 380 um deep between each macro row and the centre for
  that way's standard cells (`GEN_WAYS[w]*`), and a central **hub** guide for
  everything shared (`COMPARE_SELECT_REPLACE_*`, `RESPONSE_UNIT_*`, `MSHR_*`,
  `ADDR_DECODE_*`, `REPLACEMENT_*`, `inreg_*`) with a 40 % partial placement
  blockage over it (G7b, congestion).
- I/O pins: 117 on the left edge, 95 on the bottom, 4 on the right, 0 on the
  top; `clk` on the left edge at y = 1432.

The ring was chosen for routability (DRC.md: iter5..iter16b), and it did get
the design through DRC, LVS, IR and EM. It was never evaluated for timing
with an honest timer, because none existed until today.

## 1a. Where the die size comes from (written 2026-09-08 23:55)

The die is chosen by us, not by the tool. Stage 01 (`scripts/01_floorplan.tcl`)
would size the core from a utilisation target (`ASIC_FP_UTIL`, default
`FP_ROW_DENSITY` = 0.65, the value Genus used for its physical estimate), but a
floorplan file replaces that path entirely, and both `fp_iter16.tcl` and
`fp_iter23_quad.tcl` hard-code `ASIC_FP_DIE` = 2900 um with the macros at fixed
coordinates. The number dates from the routability fight (DRC.md, iter5..iter16b)
and was never re-derived; this section is the derivation, after the fact, from
measured runs.

| item | area | share |
|---|---|---|
| die 2900 x 2900, core margin 16 -> core 2868 x 2868 | 8.41 / 8.23 mm2 | |
| 16 x `sram_1rw1r_32_256_8` (376.48 x 446.235 um) | 2.69 mm2 | 32.7 % of core |
| standard cells, E37 fo32 (iter26 `reports/place/checkplace.rpt`) | 2.06 mm2 | 40.5 % of free sites |
| standard cells, E35 fo20 (iter19b) | 2.54 mm2 | 50.0 % of free sites |
| placement blockages (hub partial blockage, halos) | 0.73 mm2 | |
| chip density incl. macros (iter26) | | 59.0 % |

Three facts fix the number:

1. **The macro geometry sets the floor.** On the quad, a way block is two
   R90/R270 macros plus the channel, 2 x 446.2 + 260 = 1152 um wide and
   2 x 376.5 + 40 = 793 um tall. Two blocks per side plus the 40 um edge
   clearance is 2385 um, so no square die below ~2400 um holds the quad at
   all; the ring has the same floor from a different direction (four banks in
   a row along one edge: 4 x 376.5 + 3 x 40 + 2 x 40 = 1706 um, plus the
   opposite way's row and the centre).
2. **The hub band sets the rest.** Everything shared (`COMPARE_SELECT_REPLACE`,
   `RESPONSE_UNIT`, `MSHR_*`, `ADDR_DECODE`, `REPLACEMENT`, the boundary
   registers) is ~0.83 mm2 of cells that must sit between the way blocks. At
   2900 the band between the top and bottom blocks is 2900 - 2 x 793 - 80 =
   1234 um tall, 3.5 mm2 of sites for 0.83 mm2 of cells.
3. **Routability, not area, has been the binding constraint.** sky130 gives this
   flow five signal layers (met1..met5, li1 excluded). The ring at 50 % cell
   density routed with 13 % H overflow and ~3,000 post-route DRC on E37; the
   quad at 41 % sits at 1.7 % overflow and routes E35 to 105. Raising density
   is what the DRC history says not to do.

Cross-check against the tool: auto-sizing at 0.65 on the 4.75 mm2 of macros
plus cells would give a ~7.3 mm2 core, i.e. a ~2700 um square, within 7 % of
2900, and without channels for the macro geometry. So the hard-coded die is
close to what Innovus would have picked, and the extra 7 % is what the ring and
quad spend on channels and the hub band.

Is it too big? Not by utilisation: 59 % total density on a macro-dominated
block with a five-layer stack is ordinary. By timing it is worth a sweep, after
the 9/14 signoff: the quad geometry would fit a 2600 um die (hub band 934 um,
2.35 mm2 of sites for the 0.83 mm2 hub), 20 % less silicon, with shorter
hub-to-way and boundary wires (the long nets are where single small drivers
show 1.5-2.2 ns). CORRECTION (23:20, same night): it DOES bear on the wall. The 19b Tempus
worst path at 7.3 ns (`tempus_..._v8_p7p3_refpin/reg2reg.rpt`, path 1:
`u_sram/dout1[11] -> COMPARE_SELECT_REPLACE_out_rdata_reg[20]`) spends 3.585 ns
after the macro in 24 stages, of which 16 are repeaters on two nets
(`rline_raw_116`, `n_288227`) and only 7 are the way-select mux itself;
roughly 2.4 ns of the 3.6 is distance from the macro corner to the hub. A
smaller die shortens exactly that. It still pushes density toward the overflow
the ring showed, which is the risk the iter26i/j pair measures. One-variable experiment: `ASIC_FP_DIE=2600` on the
quad with the E35 netlist (the one that routes); the quad file scales from that
knob. When quoting area, quote both: 4.74 mm2 is the Genus/Innovus cell area,
8.41 mm2 is the silicon.

## 2. What the honest placement shows

iter21 (4.0 ns target, source latency off, reference-pin I/O), placement
stage, `reports/place/setup.rpt`: worst reg2reg -3.44 ns, TNS -2704 ns, and
the worst path is a **wire**:

| endpoint | position (um) |
|---|---|
| `MSHR_FILE_REFILL_MUX_refill_line_reg[100]/Q` (launch, hub) | (124, 222) |
| `GEN_WAYS[2]...refill_line_r_reg[100]/D` (capture, way 2) | (55, 576) |
| same bit, way 0 | (2283, 70) |
| same bit, way 1 | (2260, 1939) |
| same bit, way 3 | (2299, 1887) |

One 128-bit refill bus must reach all four ways, and three of them are 2.2
to 2.8 mm away from its source. 19b's placement-stage worst path was the
same family (`MSHR_FILE_REFILL_MUX_refill_set_id_reg` -> way 1's
`refill_rd_tag_r_reg`). The MSHR file's 3,062 flops are smeared over
x 17..1757, y 29..1895 by the placer trying to be near all four ways at once.
The same geometry costs the clock tree: 35k sinks spread to all four edges
from a pin on the left edge is part of why even the clean tree (ctsE) is
4.2 ns deep, and it is why the tag-array `rindex` replicas and the
`refill_rd_tag` registers keep showing up as worst paths.

None of this is fixed by CTS, RC factors, useful skew or the netlist: a
2.5 mm sky130 wire with repeaters is about 2 to 3 ns however it is driven.

## 3. What a physical designer would do

1. **Cluster the macros so shared logic is short-reach.** Two candidates:
   - *Two columns*: 8 macros down the left third and 8 down the right third
     (or 4x4 in two blocks), shared logic in the centre channel, each way's
     cells beside its own macros. Longest hub-to-array wire drops from
     ~2.6 mm to ~1.2 mm.
   - *One quadrant per way*: 4 macros as a 2x2 block in each quadrant, the
     way's cells wrapped around its block, hub at the centre. Symmetric, and
     the hub reaches each way in ~1 mm.
   Keep `dout1` facing the way's logic (the half-cycle read path,
   CTS.md section 5) and the halo/strap rules DRC.md settled.
2. **Put the shared structures where the bus lengths are balanced**, and
   register the refill bus once per way if the bus is still the worst path
   (RTL, +1 cycle on refill only, not on hits).
3. **Move the clock pin** toward the centre of the pin edge nearest the hub
   (or the top-level integrator supplies it there) so the tree fans out
   from the middle rather than from one edge.
4. **Re-check routability**, because the ring exists for DRC reasons:
   two-column and quadrant floorplans concentrate the macro pin escapes
   (629 vdd/gnd met4 strap pins per macro) and the channel between macro
   blocks becomes the new congestion hotspot. Expect the DRC.md corner
   lessons (met4 blockages over macro bodies, strap pitch) to need a
   re-tune.

## 4. How to test it cheaply

Placement only, no CTS or route: `launch_from_knobs.sh <base> <new> <tag>
ASIC_FLOORPLAN=<new fp .tcl> ASIC_PNR_TO=03` (about 2 h), then compare
`reports/place/*.summary.gz` WNS/TNS, `reports/place/setup.rpt` worst path,
and the placement-stage wire length (`flow.log` "Total wire length") against
iter21's -3.44 / -2704. The ring can only be beaten on those numbers by a
floorplan that shortens the hub-to-array buses; if a candidate does not,
routing it is a waste of a day. Write each candidate as
`../floorplans/fp_iter2x_<name>.tcl` with the macro coordinates as the only
change first, wedges and hub second.

## 4b. Screen results (2026-09-08, night)

- **Two columns (`fp_iter23_cols.tcl`) does not fit this die.** Two attempts,
  both killed at legalization. First: way regions = the half-block alone, 0.23
  mm2 of sites for 0.18 mm2 of cells (78 %, cap 55 %), 18,251 cells unplaceable
  (`reports/floorplan/utilization.rpt` gives the per-group density; the ring
  and quad sit at 0.33-0.41). Second: regions extended into the end bands
  (29 %), still 13,082 unplaceable, all array registers (`word_valid_mem`,
  `allocated_mem`, tag banks). Probe of the power checkpoint: no placement
  blockages, sites present. The array registers are pulled into the 160 um
  channel between the macro columns, next to the pins, and the only spare
  sites are in the band beyond the far end of the block, 600-800 um away,
  outside the legalizer's reach. Widening the channel enough to hold a way's
  registers (~300-400 um) leaves no centre channel for the 0.83 mm2 hub on a
  2900 um die. Runs kept as `runs/20260907_iter23_cols*_BAD_*`.
- **Quadrant (`fp_iter23_quad.tcl`)**: every way at 34 % (same as the ring),
  zero legalization errors; early global route started at 65 % H overflow
  (ring 31 %) and settled to 10-17 % H after the first optimisation pass,
  below the ring's 23 %. **Placement result (2026-09-08 03:50), same netlist and
  knobs as iter21:**

  | placement end, 4.0 ns | iter21 ring | iter23 quad |
  |---|---|---|
  | reg2reg WNS | -3.440 | -2.105 |
  | TNS | -2704 | -838 |
  | violating paths | ~15k | 4,585 |
  | density | 59.1 % | 52.9 % |
  | routing overflow | 13.2 % H / 7.5 % V | 5.3 % H / 3.1 % V |

  Worst paths are still the hub-to-array family (`refill_set_id` -> way 3
  `refill_rd_tag_r`, 3.57 ns of path) but 1.3 ns better, and a second family
  now shows: `GEN_WAYS[0].rindex_rep_r_reg` -> read registers of ways 1, 2, 3.
  The rindex replicas are all named under way 0, so the way-0 region owns
  them and three of them cross the die. Give each way its own replica (RTL)
  or move the `rindex_rep` pattern out of the way regions in the floorplan.
  Full flow launched as `runs/20260907_iter23q_quad_ctsA_p4000_1v76` (iter22
  knobs = ctsA cells + useful skew off + RC 1.1, stages 04-05 on this
  placement).

## 4d. iter23q routed: 5,932 DRC, all at the mouth of way 0's channel (2026-09-08 11:15)

E37 on quad v1, honest tree (21 levels, 0 FE_USK), post-CTS -2.184. Detail route
plateaued at ~5.4-5.9k over 40 iterations (the ring: 129k after 5). Of 5,715
verified: 4,560 shorts, 1,105 spacing; met2 2,406, met3 1,259, met4 1,068,
met1 822. **4,244 of them sit in one 250 um bin, x 500-650 / y 700-900: the
top of way 0's interior channel.** The 160 um slot between way 0's macro
columns is closed by the die edge at the bottom, so every net of the way's
array registers (tag banks, `rline_raw`, plus 1,300 generic buffered nets)
exits through that one mouth. Way 3's mirror channel: 0 violations; way 2: 2.
I/O nets are only 67 of the hotspot, but way 0's corner is where the 117
left-edge and 95 bottom-edge default pins live, so their escapes share the
same tracks.

Quad v2 (same file, two knobs): `ASIC_FP_WAY_CHANNEL=260` (block 1152 wide,
mouth 1.6x) and `ASIC_FP_PIN_BAND=1` (all ports `editPin` onto the left edge
inside the hub band, met3). Launched as
`runs/20260908_iter25_quad2_ch260_pinband_ctsA_p4000_1v76` (E37, 4.0, iter22
knobs) - the one-variable test against iter23q. If the mouth is still hot,
the next lever is a second exit: lift the corner blocks off the die edge
(EDGE 40 -> ~250) at the cost of hub-band height, or put the array
registers' region (`STRIP`) on the channel side only.

**Correction (2026-09-08 evening).** Neither iter25 nor iter25b had the pin
band. Both launched from the same knobs at 11:03/11:04 (the `ctsA` and
`pinband` directory names differ, the knobs do not), and both read the
floorplan file BEFORE the 11:08 edit that removed a stray `-unit MICRON` from
the `editPin` call; Innovus rejected the call (IMPTCM-113, "-spacing required
with -unit") and left every pin at its default place. So iter25/25b are a
replicate pair of "channel 260, no band": 3,089 / 3,043 post-route DRC
(iter23q 5,932), setup WNS -4.415 / -6.066, hold +0.098 / +0.081. Two
readings follow: channel 260 is the whole DRC gain, and 1.6 ns of post-route
setup WNS between identical runs is the run-to-run noise on this flow. The
committed `editPin` (no `-unit`) was verified standalone on iter25's stage-01
checkpoint (`runs/20260908_pinbandtest_scratch/logs/pinband_test.log`): all
216 pins land inside the hub band, y 1113..1787, pitch chosen by the tool
(`-spreadType range` ignores `-spacing`). The band is still untested in a
flow; iter26/26b run with it OFF on purpose so their netlist comparison stays
one-variable.

**Correction to the correction (2026-09-08 23:50, from the run logs).** The
paragraph above is wrong about iter25b. Its `logs/flow.log` line 556 shows the
FIXED call, `editPin ... -side LEFT -layer 4 -spreadType range -start {16
1112.96} -end {16 1787.04} -fixOverlap 1` with no `-unit`, followed by
"Successfully spread [216] pins". iter25's log at the same line has the old
call and the IMPTCM-113 rejection. iter25b launched 11:04 but its stage 01
sourced the floorplan file after the 11:08 edit (stage 00 reads the netlist
first), so **iter25 = channel 260 without the band, iter25b = channel 260 with
the band**. They are not a replicate pair, and the "1.6 ns run-to-run noise"
reading has no support: the flow's noise is unmeasured until a true replicate
pair is run. What the pair does say, n = 1 each side: the band is DRC-neutral
(3,043 with vs 3,089 without) and came with 1.65 ns worse post-route setup WNS
(-6.066 vs -4.415), which may be the band's cost or may be noise. Commit
c427c62's message carries the wrong reading; this paragraph supersedes it.
iter26's exclusion of the band stands, now for a different reason: it did not
help DRC and might cost timing.

**iter26 2x2 DRV table (2026-09-08 23:06).** All four are E-netlist x cap-rule on
the same quad floorplan (channel 260, no pin band, ctsA, 4.000 ns, ss 1v76),
fanout 32 everywhere (Genus 2x2x2 showed fo32 is the sweet spot). Each run's
Genus netlist was synthesized under the same DRV rules that P&R applies
(`golden.sdc` reads `ASIC_MAX_CAP` / `ASIC_MAX_FANOUT`, so Genus, Innovus and
Tempus see one value):

| run | netlist | ASIC_MAX_CAP | ASIC_MAX_FANOUT | Genus run |
|---|---|---|---|---|
| iter26  | E37 (skid + rst_r, current src) | none (library per-pin) | 32 | `20260908_e37_nocap_fo32` |
| iter26b | E35 (Aug netlist, `Cache_e35` worktree) | none | 32 | `20260908_e35_nocap_fo32` (Cache_e35) |
| iter26c | E37 | 0.100 (campaign blanket) | 32 | `20260908_e37_cap0p1_fo32` |
| iter26d | E35 | 0.100 | 32 | `20260908_e35_cap0p1_fo32` (Cache_e35) |

Rows answer "does the cap blanket matter post-route" (26 vs 26c, 26b vs 26d);
columns answer "does E37 beat E35" (26 vs 26b, 26c vs 26d). iter25/25b
(E37, cap 0.100, fo20) is the fo20 reference outside the table. iter26b
aborted at CTS 22:20 (the boundary skew-group patterns `*rst_r_reg*` and
`*RESP_SKID_*` do not exist in E35; iter24a had `ASIC_CTS_IO_SINK_OPTIONAL=1`
but iter26b was generated from iter25's E37 knobs and lost it). Its
`03_place` checkpoint is intact; iter26d carries the knob. Relaunch iter26b
from stage 04 with `ASIC_PNR_FROM=04 ASIC_CTS_IO_SINK_OPTIONAL=1` to fill
its cell.

**Extension (23:30, user: "iter26e-h same as a-d at a relaxed clock, then i,j
on the smaller die").** iter26b was resumed from its `03_place` checkpoint at
23:08 (stage 04 on, `ASIC_CTS_IO_SINK_OPTIONAL=1`; `launch.stage00.sh` is the
original launch line). Six more runs, all quad channel 260, no pin band, ctsA:

| run | base | one variable vs base |
|---|---|---|
| iter26e | iter26  (E37 nocap fo32) | period 7.000 ns (`constraints/pnr_7ns.sdc`) |
| iter26f | iter26b (E35 nocap fo32) | period 7.000 ns |
| iter26g | iter26c (E37 cap 0.1 fo32) | period 7.000 ns |
| iter26h | iter26d (E35 cap 0.1 fo32) | period 7.000 ns |
| iter26i | iter26c (E37 cap 0.1 fo32) | die 2600 (`ASIC_FP_DIE=2600 ASIC_FP_WAY_STRIP=200 ASIC_FP_HUB_X_INSET=450`) |
| iter26j | iter26d (E35 cap 0.1 fo32) | die 2600 (same three knobs) |

Why 7.0 ns and not 5.0: iter24b (E37 quad, 5.0 ns) ended post-route at
reg2reg -3.862 with 4,881 DRC, i.e. the same ~8.9 ns wall as the 4.0 ns runs,
so 5.0 is still unreachable and the optimizer behaves as at 4.0. 19b misses 7.3
by 0.867 ns on the SRAM path; 7.0 is the first target within the optimizer's
reach, and the question e-h answer is whether optDesign can pull ~1 ns out of
the macro-to-hub segment when it is not spread over 12k violators. Compare each
against its base at the SAME signoff period in Tempus (what-if 7.3 / 9.1), not
by P&R WNS.

Why those three die knobs together: the strip and hub inset are absolute
offsets, so at 2600 with the 2900 values the way0/way3 (and way2/way1)
regions overlap by 305 um. Two stage-01 dry runs (`fp2600*_scratch`, deleted)
set the choice: strip 100 gave the way regions TU 74.6 % (the two-column
floorplan died at 78 %), strip 200 gives 62.3 % (2900: 56.3 %) with a 185 um
region overlap and a 534 um hub band (2900: 714). The die is the variable; the
offsets are its geometric consequence. Core utilisation 67.0 % vs 53.7 %.

## 4c. iter21r: the iter21 ring placement does not route (2026-09-08 02:30)

iter21r (iter21's 03_place + legacy CTS, 4.0 ns) finished stage 05 with
129,459 DRC violations, 68k of them metal shorts on met1/met2 spread over the
whole die, signal against signal and against clock nets; the DRC gate stopped
post-route opt. Router settings identical to 19b (14 violations). The
difference is the placement it was handed:

| | iter19b (3.333) | iter20 (4.0) | iter21 (4.0) |
|---|---|---|---|
| Genus netlist | E35 (0828), 142,766 cells | E35 | E37 (0907, skid + rst_r), 144,124 cells |
| placed instances | 393,555 | 397,057 | 433,851 |
| optimizer buffers (FE_OFC/FE_OCP) | | 65k / 33k | 97k / 42k |
| placement density | 50.0 % | 50.0 % | 59.1 % |
| post-place routing overflow | | 4.1 % H / 1.8 % V | 13.2 % H / 7.5 % V |
| unplaced WNS at place_opt start | | -87.8 | -121.7 |

The extra ~39k cells are timing-driven fanout buffering spread over
anonymous logic nets (not the reset: rst_r fans out to 3). The E37 Genus
netlist, same knobs as E35, came out with 8k more sdfxtp mux-flops, 5k more
inverters and far more x4/x6 drives, and the placer then buffered 40 % more.
Same Genus fanout profile, same SDC, same placement scripts (unchanged since
09-01). iter22 / iter22b carry this placement (iter22 placed at the identical
-3.44), so their routes are expected to fail the same way; the quad screen
uses the same netlist but its early global route settled at 4-5 % overflow
against iter21's 13 %, so the floorplan comparison stands.

Open question for the morning: why the E37 synthesis is worse (RTL effect
of the registered reset / skid buffer on Genus's structuring, or run-to-run
variance), and whether ASIC_PLACE_MAX_DENSITY / setOptMode -maxDensity should
cap the optimizer so a placement can never leave stage 03 above ~52 %.

## 5. Where this sits in the schedule

Not before 9/14 unless iter22/iter22b fail for a reason the floorplan would
fix. The deliverable for 9/14 is an honestly signed-off package on the ring
(iter21 or iter22, whichever closes); the floorplan is the first experiment
of the campaign after that, and the one most likely to move the honest
number from the 5-6 ns band toward 4 ns.
