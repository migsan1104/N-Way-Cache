# CTS.md — clock trees, and this project's clock tree

A learning/interview reference. Everything in here is grounded in this repo:
the stage script is `scripts/04_cts.tcl`, the numbers are from iter14
(`runs/20260901_iter14_e35_fp7_armE/reports/cts/`), and the war stories are in
`../DRC.md` and the git history.

## 1. The problem CTS solves

Every flop in a synchronous design must see the same clock edge. Physically
that's impossible: one clock pin at the boundary has to reach ~35k flop clock
inputs spread over ~2.7 × 2.4 mm of silicon, and a wire that long with that
much load isn't even a valid signal — it would have a multi-nanosecond rise
time. So the tool builds a *tree*: the root drives a few buffers, each drives a
few more, fanning out until every flop is a leaf. Clock Tree Synthesis is the
construction of that tree — choosing the topology, the buffer sizes, and the
routing — to balance three quantities:

- **Insertion delay (latency)** — root-to-leaf delay through the tree.
- **Skew** — the *difference* in insertion delay between two leaves. This is
  what eats directly into timing: launch flop and capture flop seeing the edge
  at different times shifts the setup/hold window.
- **Transition (slew)** — edges must stay sharp everywhere in the tree, or
  downstream delays balloon and short-circuit power spikes.

Before CTS the flow *pretends*: the clock is **ideal** (zero delay to every
flop) and a lump of **clock uncertainty** stands in for the skew and jitter of
the tree that doesn't exist yet. CTS is the moment the pretending stops.

## 2. Vocabulary that comes up in interviews

| term | meaning | in this project |
|---|---|---|
| ideal vs propagated clock | pre-CTS fiction vs real tree delays | switched by `set_propagated_clock` right after `ccopt_design` |
| global/target skew | max leaf-to-leaf latency difference CTS aims for | target 0.100 ns (`ASIC_CTS_TARGET_SKEW`) |
| insertion delay | root→leaf latency | ~1.6 ns at CTS estimates; **7.433 ns at signoff** (see §5) |
| local skew | skew between flops that actually talk | what really matters; global skew is a proxy |
| clock uncertainty | margin for jitter + unmodeled skew | 0.250 ns pre-CTS → 0.100/0.050 ns (setup/hold) post-CTS |
| useful skew | *deliberately* unbalancing the tree to donate time to a failing path | ccopt does this natively (it's the "cc" in ccopt) |
| ICG (integrated clock gate) | AND-with-latch cell that stops the clock to idle flops; saves dynamic power | **zero in this design** — no clock gating was synthesized |
| NDR (non-default rule) | fatter/wider-spaced wires for critical nets | 2×-width/2×-spacing rule available for clock trunks (§6) |
| H-tree / mesh / fishbone | classical balanced topologies | ccopt builds an optimized irregular tree instead |
| CTS cells | buffers/inverters used to build the tree | inverter-dominated: 2,083 inverters vs 251 buffers |

Why inverters instead of buffers? Two inverters = one buffer, but the tool can
place each half independently, and an inverter chain keeps the duty cycle
symmetric (each stage inverts, so rise/fall asymmetries cancel pairwise
instead of accumulating).

## 3. What Innovus ccopt actually does

`ccopt_design` ("clock concurrent optimization") is not just tree building —
it builds the tree *while* looking at the data paths, and it will skew the
clock on purpose (useful skew) to help a failing path: give the capture flop a
later clock and a setup-critical path gains time (its hold gets worse — it's a
trade, not free money). The flow in `04_cts.tcl`:

1. `create_ccopt_clock_tree_spec` — derive the clock structure from the SDC
   (what's a clock, what's a generated clock, where the sinks are).
2. Set properties: `target_skew` 0.100 ns, `target_max_trans` 0.750 ns.
3. `ccopt_design` — build, place, and route the tree (the clock is routed
   *now*, before signal routing — it gets first pick of resources).
4. Switch to `set_propagated_clock` and cut the uncertainty down.
5. Post-CTS `optDesign` — setup first, **then** hold.

Why that order, and why is hold suddenly real? Hold checks launch and capture
on the *same* edge, so with an ideal clock (zero skew) hold is trivially
optimistic — the pre-CTS flow doesn't even try to fix it. Once real skew
exists, a fast data path next to a skewed clock can genuinely race. Hold fixes
are *delay insertion* (buffers in the data path), which can only hurt setup —
so setup is optimized first and hold fixes are layered on top, never the
reverse. That ordering holds at every optimization stage in this flow.

## 4. Our tree, in numbers (iter14, 4.0 ns target, SKY130 HD, ~350k placed cells)

| metric | value |
|---|---|
| clocks | 1 (`clk`) — plus `rst` explicitly *not* a clock (timed synchronous input, ~590 flops post-E29) |
| sinks | 34,820 flop clock pins |
| tree cells | 2,334 (2,083 inverters, 251 buffers, 0 clock gates) |
| tree cell area | 12,471 µm² |
| clock wire | 345 mm total: 91.7 mm trunk, 253.5 mm leaf |
| target skew / max trans | 0.100 ns / 0.750 ns |
| latency @ CTS estimates | ~1.6 ns (preroute, no SPEF, BcWc) |
| latency @ signoff | **7.433 ns** — Tempus, propagated, Quantus SPEF, ss_n40C_1v76 |

That last row jump (1.6 → 7.4 ns) is the single most instructive number in
this section — see §5.

## 5. Findings worth being able to explain

**The 7.331 ns "gift": `update_io_latency` made 300 MHz look closed
(found 2026-09-07, iter19b).** Every Innovus and Tempus setup number quoted for
iter16b/19/19b/20 from the route stage onward was optimistic by the tree's
insertion delay. What happened, in order:

1. `ccopt_design` finishes with its `update_io_latency` step (a ccopt property,
   default `true`, no log message). It writes a **negative source latency on
   the `clk` port** equal to roughly the tree insertion delay per view: on
   iter19b `-7.331` ns (setup view, `-max` only) and `-2.968` ns (hold view,
   `-min` only). Purpose: the golden I/O budgets are referenced to the ideal
   edge at the pin; shifting the pin's edge earlier by the insertion delay
   re-centres them on the clock the boundary flops actually see. So yes, the
   intent is purely about the input and output ports.
2. It is declared on the clock, so it enters the clock arithmetic of **every**
   path. That is harmless only if launch and capture both get it, because on a
   reg2reg path the two cancel. They do not both get it: the setup view holds
   only the `-max` value, and the setup check takes the min-qualified value for
   the capture clock. Result, verbatim from
   `reports/route/postroute_reg2reg.tarpt.gz` and reproduced by an in-session
   probe (`scratchpad/probe_srclat.tcl`, 2026-09-07 17:00): launch clock
   `+ Source Insertion Delay -7.331`, capture clock `Other End Path ...
   Beginpoint Arrival Time 0.000`. Every internal path is handed 7.3 ns.
   Tempus reads the exported SDC the same way, so signoff agreed with P&R and
   nothing flagged it.
3. Per-stage evidence, worst reg2reg WNS at 3.333 ns, iter19b: place `-3.175`
   (ideal clock, honest) -> postCTS opt `-2.750` (honest) -> route `+3.031`
   (the gift) -> ECO signoff `+3.564`. A route stage cannot improve a path by
   5.8 ns. **When it took effect (settled 2026-09-07 20:30):** the latency is
   written at the end of `ccopt_design`, but through the post-CTS
   optimization the analysis mode is still single-corner, and in that mode
   both clock ends receive it: the stage-04 path report shows launch
   `1.846` (= 9.18 - 7.33) and capture `0.038` (= 7.37 - 7.33), so it
   cancelled and the `-2.750` was honest (today's clean experiments on the
   same placement land at -2.6 to -2.8). `05_route.tcl` line 56 then runs
   `setAnalysisMode -analysisType onChipVariation -cppr both`; under OCV the
   capture clock takes the early/min latency, which was never written (only
   `-max` in the setup view), so from the route stage on the launch kept
   -7.331 and the capture got 0. Routing, post-route optimization, the ECO
   loops, the exported SDC and Tempus were all in that state; placement, CTS
   and post-CTS optimization were not. Same signature on the 4.0 ns twins: iter19 route reg2reg `+3.565`
   with `-6.744`, iter20 `+2.837` with `-6.731`.
4. The same path with the latency stripped (Tempus SI, ss_n40C_1v76, macro
   x1.5, `SIGNOFF_KEEP_CLK_SRC_LATENCY` unset, tag `_v8_refpin_dbg2` /
   `_v8_strip`): `GEN_WAYS[0].rindex_rep_r_reg[3]/Q` ->
   `GEN_WAYS[3]...rtag_raw_r_reg[17]/D` = **-3.899 ns**, 7.7 ns of data path
   (index fan-out repeaters, two 0.8 ns `buf_6` stages on one net), i.e. a
   ~7.2 ns period, ~138 MHz, at the cold corner; ss_100C_1v60 is worse.
   Innovus's own arithmetic on the identical path gives 3.031 - 7.331 = -4.3.
5. Why the paths are that long: from the route stage on, `optDesign` saw +3 ns
   of margin on every reg2reg path and stopped working them. The 19b layout is
   a design that P&R never tried to close, not the RTL's ceiling. Genus closes
   3.5 ns on wire estimates; honest post-place was 6.5 ns, honest post-CTS
   6.1 ns; the gap to Genus is the 16-macro floorplan's wire lengths.
6. Hold went the other way: `-2.968` on the launch only makes every hold check
   2.97 ns **pessimistic** (route-stage `default` hold `-3.006`). Post-route
   hold fixing paid for a phantom requirement, but cheaply on 19b: 180 delay
   cells at signoff (the 715-cell case on armC was the earlier, ideal-clock
   I/O problem).
7. Post-layout SDF GLS at 3.333 ns failing in the first transactions
   (`xcelium/GLS.md` 2026-09-07 07:35, X responses at 185 ns) was this finding
   arriving by another road: the netlist really does not run at 3.333 ns.

**Three ways to time the ports once the clock is real.** All three answer
the same question: *when does the external agent see the clock edge, relative
to our flops?* `set_input_delay 0.7 -clock clk` says "data arrives 0.7 ns
after clk's edge", and "clk's edge" means the edge at the clock's definition
point (the port), at time 0, unless something says otherwise. Before CTS the
flops also see it at time 0 (ideal clock), so the budget is consistent. After
CTS the flops see it 2 to 11 ns later. If the constraint is left alone, every
input looks 7 ns early (hold fixing stuffs delay cells, the armC 715-cell
case) and every output looks 7 ns late (reg2out "violations" that are pure
insertion delay). The CPU on the other side of the port is on the same clock
and behind a tree of similar depth, and each model states that in a
different way:

| Model | What it says | Where the number comes from | Weakness |
|---|---|---|---|
| **Virtual clock with latency** (`create_clock -name vclk_io`, `set_clock_latency -source L vclk_io`, I/O delays `-clock vclk_io`). Textbook method; `io_vclk.tcl` legacy mode. | "The other side has its own tree of depth L." | You measure L per corner and pick one value for a tree that spans 0.45 to 9.6 ns. | A single L for a skewed tree is wrong for most ports (the 2026-09-07 "not latency-matched" finding). Must be re-measured per corner and re-applied in signoff. |
| **`update_io_latency`** (ccopt property, default `true`; Innovus runs it silently at the end of `ccopt_design`). The Cadence automation of the same idea. | "Redefine the edge at the port so that the internal flops see the clock at about time 0" - a **negative source latency on `clk`** per view. | The tool derives one value per analysis view from the tree it just built (19b: -7.331 setup view, -2.968 hold view). | Lives on the clock, so it enters every path. Only cancels on reg2reg if every early/late x min/max slot is populated in every view; our views carried one kind each and it became a one-sided 7.3 ns gift, exported into the SDC and inherited by signoff. One value per view, so still a single L for a skewed tree. |
| **Reference pin** (`set_input_delay 0.7 -clock clk -reference_pin <boundary flop>/CLK`; same for outputs). SDC/PrimeTime/Tempus/Innovus feature; `io_vclk.tcl` reference-pin mode, iter21. | "The other side's launch and capture flops are clocked exactly when *this* flop of ours is." | Nothing to measure: the propagated arrival at the named pin, per corner, per stage, whatever the tree does. | Honest only if the boundary flops sit near the reference pin's latency, hence the `io_regs` skew group in `04_cts.tcl` (costs tree effort/area on those sinks). Needs the pin to exist in the netlist (fails loudly if not). |

Which is right depends on what is true about the other side, not on the tool:

- If the block goes into a top level whose clock tree is built later, the
  industry norm is **budgeted latency**: the integrator hands the block a
  `set_clock_latency -source +T` (the top-level tree delay to the block pin)
  and the I/O budgets; the block times its ports against that; the top
  level re-times the boundary with the block's ETM/ILM and the real trees.
  `update_io_latency` and the virtual clock are the block-level stand-ins for
  that budget when no integrator exists yet. This is what most Cadence block
  flows run by default.
- If the other side is on the *same* tree at comparable depth, which is the
  assumption this project has always made (`golden.sdc`: in 0.7 = measured
  CLK->Q, out 0.3 = setup + margin), the reference pin states exactly that
  with no invented constant and tracks every corner automatically. It is
  less common in block flows and more common for source-synchronous
  interfaces, but it is standard SDC and every signoff tool honours it.

None of the three is "more correct" in the abstract; the reference pin is the
better fit *here* because the tree is skewed 20:1, there is no integrator,
and the previous two attempts each needed a hand-measured number that was
wrong. Its cost is the skew group and the discipline of re-applying it at
every stage (it is an interactive constraint, not part of the netlist).

Are they mutually exclusive? In effect, yes:

- Virtual clock + `update_io_latency` double-count: the virtual clock carries
  +L and the port carries -L. 19b ran **both** (vclk_io at 2.179 plus clk at
  -7.331), which is how the I/O numbers were nonsense in both directions.
- Reference pin + `update_io_latency` is arithmetically consistent (the
  reference pin's arrival includes any source latency, so both sides move
  together), but the source latency still pollutes reg2reg one-sidedly in
  our views, so the safe pairing is reference pin **plus
  `update_io_latency false`**. That is the iter21 flow.
- Whatever P&R uses, signoff must load the identical model. 19b's signoff
  read the exported SDC (with the -7.331) and then layered the virtual clock
  on top, so it agreed with P&R for the wrong reason.

**How to keep it out of the flow (iter21 onward).**

- `set_ccopt_property update_io_latency false` before `ccopt_design`, and
  verify after the tree: `get_ccopt_property update_io_latency`,
  `report_clocks` must show no source latency on `clk`. Then the I/O budgets
  need a real model, which is the reference-pin mode in `io_vclk.tcl`
  (`set_input_delay/-output_delay -clock clk -reference_pin <boundary
  flop>/CLK`, applied after `set_propagated_clock`, re-applied before every
  `optDesign` and in `sta.tcl`). The external agent is then modelled as
  clocked like our boundary flops, and no source latency exists to mis-apply.
- If a run must keep `update_io_latency`, make it symmetric before any timing
  is trusted: every `-early/-late` x `-min/-max` combination set to the same
  value in each view, and the exported SDC must carry all four lines. Never
  strip it in signoff without also removing it in P&R, or the two disagree.
- The tripwire, every stage: print `report_clocks -latency` (or a
  `-path_type full_clock` report of the worst reg2reg path) and check that
  launch and capture show the same source insertion delay. A reg2reg WNS that
  jumps by more than the RC delta between two stages is this bug until proven
  otherwise.
- Quote nothing from a view whose clock report you have not read. The 09-04
  hold "split" fix in `sta.tcl` mirrored `-max` to `-min` and stopped there;
  it needed to be `-early` to `-late` as well, or better, no latency at all.

**The 7.433 ns insertion delay (2026-09-01, `../DRC.md`).** At signoff corner
(ss, −40 °C, 1.60 V→1.76 V lib) with real extracted RC, the tree's insertion
delay is nearly *two clock periods*. Why so large: 35k sinks through ~10+
levels of inverters, each stage slowed by the slow corner, driving long met
wires whose extracted RC is worse than the CTS-time estimate. Why it mostly
doesn't matter: **insertion delay is common-mode**. Launch and capture flops
both sit at the end of ~7.4 ns of tree, so reg2reg timing sees only the
*difference* (skew), not the total. Where it *does* matter: (a) I/O timing —
input/output budgets reference the ideal edge, so 7.4 ns of latency makes port
paths report nonsense until a latency-matched virtual clock is added (open
constraints TODO); (b) on-chip variation — OCV derates scale with path length,
and a 7.4 ns common path means more derated margin lost (CPPR claws back the
shared portion; that's why `-cppr both` is set); (c) power — the whole tree
switches every cycle.

**Is the tree bad, and should it be rebuilt? (2026-09-07 18:30, iter19b, for
the 250 MHz attempt.)** Short answer: yes, and for a reason that is not skew.

*What ccopt actually built* (`flow.log`, "Skew group summary after
post-conditioning"): 34,820 sinks (34,788 flops; the tag arrays are flops,
`bank_tags_reg` is the largest family, plus the per-line `word_valid`/
`allocated`/`dirty` bits), one skew group, 2,348 inverters + 149 buffers, no
clock gates, 25 levels deep from the clk pin at the left edge mid-height
(0, 1432 um) across a 2.9 mm die. Insertion delay at the CTS corner
**7.12 to 7.64 ns, skew 0.52 ns** against a 0.342 ns target (ccopt relaxed our
0.100, IMPCCOPT-1261). So at CTS time the tree *was* balanced to 7%; it is
just 7.3 ns long. Three warnings explain the length: IMPCCOPT-1183 "no
usable balanced buffers" (the tree is inverter-only because we never set
`buffer_cells`/`inverter_cells`), IMPCCOPT-1033 x29 "max_capacitance 0.100 pF
below clkinv_2" (a 0.1 pF cap wall means each stage drives ~500 um of sky130
wire, so crossing 2.9 mm alone costs many stages), and the leaf/trunk routing
is on met1/met2 (46.9k + 59.4k segments vs 24.5k met3 and 549 met4 in the
DEF), the highest-resistance layers, with no NDR.

*What signoff sees* (Tempus SI, Quantus RC, `_v8_refpin_dbg2` with the
source latency stripped, setup view): latency **5.53 ns (`rindex_rep_r_reg`)
to 9.49 ns (`bank_tags_reg`)**, worst timed-pair skew 2.30 ns. The "0.45 to
9.6 ns, 20:1" figure quoted on 2026-09-07 13:30 was contaminated by the
-7.331 source latency on some entries (Innovus's own `reports/cts/skew.rpt`
"0.139 min" is 7.47 - 7.331). The real spread is **-22% / +24% around 7.3 ns**.
It is not SI (Innovus non-SI capture arrival 7.362 vs Tempus SI 7.395 on the
same pin) and it is not OCV derating (`sta.tcl` sets none beyond the macro
x1.5). **Corrected 19:40 the same evening:** it is mostly not RC either. The
skew report written at the end of stage 04 on 19b (same session, same RC
model as ccopt) already read 7.47 to 9.83 ns against ccopt's 7.12 to 7.64.
What sits between the two is `optDesign -postCTS` with useful skew on: the
post-CTS tree structure holds **324 `FE_USK*` delay cells inserted into
clock branches, up to 19 in series on one root-to-leaf path**. Correction 20:30: at that
stage the latency was still symmetric (see item 3 above), so this was
useful skew working honestly against an unreachable 3.333 ns target,
delaying capture clocks to buy setup on paths that were 2.7 ns short. It
is still the wrong trade for a tree that must survive routing and RC
drift, which is why the default is now off and the tripwire counts it. Routing and Quantus
then moved the branches by roughly -20%/+0% on top (min 7.47 -> 5.53, max
9.83 -> 9.49). A direct SPEF comparison (below, "RC-factor caution") puts
the pre-route model within a few percent of Quantus in total resistance,
so the 5x factor from generateRCFactor is not the explanation and is not
trusted. `04_cts.tcl` now defaults useful skew OFF in post-CTS opt
(`ASIC_CTS_USEFUL_SKEW=1` restores it) and prints a tripwire with the tree's
Max Level and its FE_USK count.

*Is that normal?* No. A block of this size in a mature flow lands at 1 to
3 ns insertion delay and a skew of 5 to 10% of the period. Ours is 1.8
periods of insertion delay at 4 ns. The rule that follows: keep the tree
short, because every percent of model error is paid in nanoseconds of skew
proportional to the tree length, and CPPR only removes the *common* part.

*What to change for iter22 (CTS recipe, no RTL change):*

1. `set_ccopt_property buffer_cells {clkbuf_8 clkbuf_16}` and
   `inverter_cells {clkinv_8 clkinv_16}` (sky130 max_capacitance: clkinv_2
   0.28 pF, clkinv_8 0.90, clkinv_16 1.56, clkbuf_16 1.01). Fixes 1183 and
   the 0.1 pF wall in one move; expect roughly half the levels.
2. Trunk/top on met3..met5 with the 2w2s NDR (`ASIC_CTS_CLOCK_LAYERS=met3:met5`,
   the G7a hook in section 7): lower R per stage reach, less coupling.
3. `ASIC_CTS_RC_FACTORS` from `generateRCFactor -preroute true -reference
   signoff` on the 19b routed database (run 2026-09-07 18:21; result in the
   session scratchpad `rcf_preroute_signoff.txt`), so balancing happens on
   delays that match Quantus.
4. `target_skew 0.35` (what ccopt recommends at this corner; 0.1 is refused)
   and keep the `io_regs` boundary skew group.
5. Judge by `reports/cts/skew.rpt` *without* source latency (the tripwire in
   `04_cts.tcl` now guarantees that) and by Tempus `clock_summary.rpt`: the
   goal is insertion delay under 4 ns with a spread under 1 ns.

Longer term: the tag arrays as macros or as gated banks would remove most
of the sinks; that is an RTL/floorplan project, not a CTS knob.

*The other 250 MHz blocker, found the same evening:* the SRAM read is a
**half-cycle path**. The OpenRAM macro launches `dout1` on the *falling* edge
(`timing_type: falling_edge` in the macro .lib), so from macro output to the
capturing flop (`COMPARE_SELECT_REPLACE_out_rdata_reg`) there is only P/2.
On 19b at the 7.3 ns what-if that path is the worst in the design:
0.86 ns macro access (x1.5 derate) plus **3.6 ns** of standard-cell logic
(six `rline_raw` repeaters, the way-select mux, ten repeaters on the output
net) = -0.867 at 7.3 ns, closing only around 9.0 ns. At 4 ns the budget is
2.0 ns minus setup and skew, so the post-macro logic must fit in about 1 ns.
P&R with a working timer can shrink 3.6 ns a lot (this logic was never
optimized, section 5 "the gift"), but the robust fix is architectural:
register the macro outputs before the way mux (+1 cycle of hit latency) so
the half-cycle path is macro access plus a wire. Decide that after iter21
shows what honest optimization achieves.

**What ccopt was actually allowed to use, and the professional CTS plan
(2026-09-07 18:40).** Asked directly in a probe session on `04_cts.enc`
(`report_ccopt_cell_filtering_reasons`, `report_ccopt_clock_tree_structure`,
`get_ccopt_property`), the tool explains the 7.3 ns tree in three lines:

- **Cell filter.** Every buffer in the library (`buf_*`, `clkbuf_1..16`) and
  every inverter except `clkinv_2` and `clkinvlp_2` was rejected for
  "Unbalanced rise/fall delays" (`clkinvlp_4` for "Library trimming"). With no
  explicit `buffer_cells` / `inverter_cells`, ccopt's auto-selection keeps only
  cells whose rise and fall delays match within its tolerance, and in sky130
  HD at ss/-40C that is the two weakest clock inverters. The whole tree is
  clkinv_2 and clkinvlp_2, 2,370 of them.
- **DRV limits.** `golden.sdc` sets `set_max_capacitance 0.100 [current_design]`
  and ccopt honours the SDC on clock nets, so each clkinv_2 stage was capped
  at 0.1 pF, about 500 um of wire plus a dozen sinks. `target_max_trans` was
  0.75 ns (the signal-net DRC), far looser than a clock wants.
- **Depth.** `report_ccopt_clock_tree_structure`: Max Level 45. Sink depth
  histogram: L19 54, L20 70, L22 143, L25 234, L27 163, L29 165, L33 174,
  L35 153, L37 94, L39 58, L41 56, L44 45. Every leaf is 19 to 44 stages
  from the pin. The 30-odd `FE_USK*` cells in the deepest chains are the
  post-CTS useful-skew/hold engine adding delay *into* clock branches on top.

The knobs that a physical designer would set, and now exist in `04_cts.tcl`:

| Lever | Command (Innovus 21 ccopt) | Knob | Why |
|---|---|---|---|
| Strong, explicit clock cells | `set_ccopt_property inverter_cells {sky130_fd_sc_hd__clkinv_8 sky130_fd_sc_hd__clkinv_16}`; `buffer_cells {clkbuf_8 clkbuf_16}` | `ASIC_CTS_INVERTER_CELLS`, `ASIC_CTS_BUFFER_CELLS` | An explicit list bypasses the rise/fall filter (the tool says so in IMPCCOPT-1183). clkinv_16 drives 1.56 pF vs 0.28 for clkinv_2: fewer, longer stages. |
| Clock DRV targets | `set_max_capacitance 0.30 [get_clocks clk]` (SDC on the clock network) + `set_ccopt_property target_max_trans 0.30` (and `target_max_capacitance` where the release accepts it) | `ASIC_CTS_MAX_CAP`, `ASIC_CTS_TARGET_MAX_TRANS` | Clock DRV belongs to CTS, not the signal SDC. 0.3 ns slew at a 4 ns period is a normal clock target; 0.3 pF is a third of clkinv_8's limit. |
| Skew target the tool accepts | `set_ccopt_property target_skew 0.35` | `ASIC_CTS_TARGET_SKEW` | ccopt refused 0.100 and relaxed to 0.342 anyway (IMPCCOPT-1261); asking for the truth avoids the tool "meeting" a number it rewrote. |
| Trunk/top on upper layers with an NDR | `add_ndr -name cts_2w2s -width_multiplier {met3:met5 2} -spacing_multiplier {met3:met5 2}`; `create_route_type -name cts_trunk -non_default_rule cts_2w2s -bottom_preferred_layer met3 -top_preferred_layer met5`; `set_ccopt_property route_type -net_type trunk cts_trunk` (and `top`) | `ASIC_CTS_CLOCK_LAYERS=met3:met5` (G7a hook) | The DEF shows the clock on met1/met2 (106k segments) vs met3/met4 (25k): the highest-R layers. Fat, spaced trunks on met3-5 cut RC per stage and coupling. |
| RC correlation before CTS | `generateRCFactor -preroute true -reference signoff` on a routed run, then `setRCFactor -preRoute_res/_cap -preRoute_clkres/_clkcap` | `ASIC_CTS_RC_FACTORS=res:cap` | So ccopt balances against Quantus-like delays (2026-09-07 finding: -22%/+24% per branch at 7.3 ns). |
| Boundary balance | `create_ccopt_skew_group -name io_regs -sources clk -sinks {...}`; `set_ccopt_property -skew_group io_regs target_skew 0.1` | `ASIC_CTS_IO_SINK_PATTERNS`, `ASIC_CTS_IO_SKEW` | Makes the reference-pin I/O model honest. **Caveat for ctsA-E and every run before 2026-09-07 22:20:** the sink matcher compared `dbGet` strings against `<inst>/CLK`, and `dbGet` brace-quotes any name containing `[]`, so only the four scalar flops matched: every `io_regs` line in those logs reads "4 sinks", and the group balanced nothing. iter21 was the first run without `ASIC_CTS_IO_SINK_OPTIONAL=1` and the tripwire caught it (abort at 21:23). Fixed in `04_cts.tcl` (match the library pin name `CLK`, `lindex` the strings); verified on iter21 03_place: 259 sinks, 0 missing, ccopt reports the group at 96.5% window occupancy before any tree. iter22/iter22b source stage 04 after the fix; iter21r is iter21 stages 04-05 on its own placement. |
| No source-latency artefact | `set_ccopt_property update_io_latency false` | `ASIC_CTS_UPDATE_IO_LATENCY=0` | Section 5, the gift. |
| Measure, every time | `report_ccopt_clock_trees`, `report_ccopt_skew_groups`, `report_ccopt_clock_tree_structure`, `report_ccopt_cell_filtering_reasons`, `report_clock_timing -type skew` | written to `reports/cts/ccopt_*.rpt` after every ccopt | Depth, cells, insertion delay min/max, skew, and what the tool refused. |

Not available in this release: `create_flexible_htree` / clock mesh (the
commands do not exist in Innovus 21.16 here). For 35k sinks on a 2.9 mm die
a buffered tree with strong cells is the standard answer anyway; an H-tree
top level is what one adds when the trunk itself must be skew-free across
a much larger die.

How to evaluate a recipe without a 5 h P&R: `scripts/cts_experiment.sh
<base> <new> <tag> VAR=VAL...` re-runs stage 04 only, on the base run's
frozen `03_place.enc` (symlinked), so one variable changes per experiment
and the result is in `reports/cts/ccopt_tree_structure.rpt` (Max Level),
`ccopt_skew_groups.rpt` (insertion delay min/max, skew), `skew.rpt` (no
source latency, tripwire) and `reports/postcts_opt/*.summary.gz` (honest
post-CTS reg2reg). A stage-04 run on 19b takes ~1 h of ccopt plus the
post-CTS opt. Launched 2026-09-07 18:36 on the 19b placement:

- `20260907_ctsA_19bplace_cells_drv` (tmux ctsA): clkinv_8/16 + clkbuf_8/16,
  target_max_trans 0.30, clk max_cap 0.30 pF, target_skew 0.35, update_io_latency off.
- `20260907_ctsB_19bplace_cells_drv_ndr` (tmux ctsB): A + trunks/top on met3-met5, 2w2s.
- **RC-factor caution (19:35).** A direct per-net check contradicts the
  0.205: the estimator's SPEF (trial global route + pre-route tables, the
  flow's own settings, `scratchpad/preunrouted19b_rc_slow.spef`) against the
  Quantus-tech SPEF of the routed 19b gives total R 1.137 with the 1.1 factor
  in, i.e. ~1.03 at factor 1.0; short nets (ref R < 20 ohm) 1.74, mid 1.1-1.3,
  the 3,537 longest nets 0.90. On real routed geometry the same tables give
  1.127. So the pre-route model is within a few percent in total and the
  error is *shape* (short nets over, long nets slightly under), which a global
  factor cannot fix. What generateRCFactor compared to reach 0.205 is not
  shown in its log. **Do not apply 0.205 to iter22 on the tool's word**;
  ctsC/ctsD trees built with it must be re-timed at factor 1.1 (or routed and
  extracted) before their insertion delays are believed.
- `20260907_ctsC_19bplace_cells_drv_ndr_rcf` (tmux ctsC, 18:39): B +
  `ASIC_CTS_RC_FACTORS=0.205:1.031:0.247:0.949`. That is what
  `generateRCFactor -preroute true -reference signoff` reported on the routed
  19b database: pre-route **resistance** scaled by 0.205 (clock 0.247),
  capacitance by 1.031 (clock 0.949). The LEF-based estimator had wire
  resistance about five times Quantus; the rc corners had been carrying
  1.1 / 0.9. Placement and CTS on every run so far optimized against wires
  that looked five times more resistive than they are.
- First checkpoint, "after Clustering" (pre-balancing, estimator RC):
  19b min/max/avg 6.1 / 8.4 / 7.4 ns; ctsA 0.7 / 5.3 / 4.9; ctsB 0.9 / 7.0 / 6.7
  (the 2w2s met3-met5 rule looks slower under the 5x-R estimator; C will
  say whether that survives the factors).

**Results, 2026-09-07 20:35 (stage 04 complete for A, B, C; all re-timed at
factor 1.1 from `04_cts.enc`; useful skew was ON in these four, the knob
came later).**

| run | ccopt tree (its summary) | after ccopt_design returned (skew.rpt) | after explicit post-CTS opt, re-timed at 1.1 | levels / FE_USK cells | post-CTS reg2reg WNS @3.333 |
|---|---|---|---|---|---|
| 19b | 7.12-7.64, skew 0.52 | 7.47-9.83 | (signoff 5.53-9.49) | 45 / 324 | -2.75 |
| ctsA | 4.17-4.58, skew 0.41 | 5.25-7.47, skew 2.22 | **4.17-6.24, skew 2.07** | 56 / 651 | **-2.41** |
| ctsB | 5.62-6.23, skew 0.60 | 6.36-8.70, skew 2.34 | 5.95-8.45, skew 2.50 | 59 / 538 | -2.63 |
| ctsC | 4.75-5.29 (at 0.247 clk R) | 5.33-7.25, skew 1.92 | **6.02-8.12, skew 2.10** | 51 / 383 | -2.45 |
| ctsD | 3.57-4.02 (at 0.247 clk R) | 3.57-5.26 (still at 0.247) | **3.97-6.35, skew 2.38** | 56 / 505 | |
| **ctsE** (A + useful skew OFF before ccopt) | 4.17-4.58, skew 0.41 (identical to A) | **4.20-4.57, skew 0.37** | pending | **19 / 0** | pending |

Reading: the strong-cell tree is real (min branch 4.17 ns in every column for
A), and everything above ccopt's own max is useful-skew padding: 367 cells
inserted by ccopt's *integrated* optimization before `ccopt_design` even
returned, 284 more by the explicit pass, 651 in all, 56 levels. So the
useful-skew switch has to sit **before** `ccopt_design`
(`setOptMode -usefulSkewCCOpt none`), which is where it now is; a switch after
the call, as first written, is too late. ctsE (A + useful skew off before `ccopt_design`, 20:33) settled it at
21:40: after `ccopt_design` returned, 4.20-4.57 ns, skew 0.37, **19 levels,
0 delay cells** - the tree ccopt reported is the tree routing gets. iter22 /
iter22b carry the same setting. ctsC re-timed honestly is the
worst of the three (min 6.02 vs A's 4.17): a tree sized for wires at a
quarter of their resistance is under-driven when the real wires come back,
which is the classic wrong-factor failure and closes the RC-factor question
from the other side. ctsD (same wrong factor, no NDR) re-times to 3.97-6.35,
i.e. the same tree as A within noise: with cell-dominated trunks the wire
model barely matters; with the wide met3-met5 trunks of C it did. Post-CTS reg2reg lands at -2.4 to
-2.6 whatever the tree, which is the datapath on this placement.

Pass criteria for iter22's recipe: Max Level under ~15, insertion delay under
4 ns, ccopt skew under 0.35 ns, and post-CTS reg2reg WNS honest (no source
latency) better than 19b's -2.75 at 3.333 / equivalent at 4.0.

What this does *not* fix: the SRAM half-cycle read (above) and the RC error
per branch beyond what global factors correct. Those are iter23 (RTL) and
the routing-layer change respectively.

**Uncertainty double-counting.** Pre-CTS, 0.250 ns of setup uncertainty stands
in for skew+jitter. After CTS the skew is real and measured — keeping the full
0.250 on top would count skew twice, so it drops to 0.100 (setup) / 0.050
(hold). This is a signoff decision, not a cleanup: it directly moves every
reported slack, so the value used is recorded with any quoted result.

**Clock trunks don't belong on met1 (G7 campaign, `../DRC.md` hypothesis 4).**
iter5's DRC report opened with a met1 clock trunk (`CTS_789`) shorting
picket-fence rows of signal nets through a congested hub. Fix (available as
the G7a hook in `04_cts.tcl`): route clock trunk/top nets on upper layers
(e.g. `ASIC_CTS_CLOCK_LAYERS=met3:met5`) with a 2×-width/2×-spacing NDR —
fatter for RC/electromigration, wider-spaced to cut coupling (a victim next to
an aggressor that switches every cycle collects crosstalk *every* cycle).
Leaf nets keep default rules — they must still dive to met1 flop pins.

**No clock gating.** The Clock DAG has zero ICGs — the RTL was not written
with enable-driven register banks mapped to clock gates, so every one of 35k
flops clocks every cycle. On a power-focused project this is the first thing
to fix (synthesis `set_clock_gating_style` + RTL enables); worth volunteering
in an interview as a known limitation and the fix path.

**li1 is excluded from all routing** (`setDesignMode -bottomRoutingLayer 2`).
SKY130's local interconnect is 12.8 Ω/sq — poison for a clock: an earlier
flow variant measured multiple nanoseconds of pure li1 pessimism per path.

**What the honest placement says about the floorplan (2026-09-07 21:45).**
With the timer fixed, the placement-stage worst path on iter21 (4.0 ns) is
a wire: `MSHR_FILE_REFILL_MUX_refill_line_reg[100]` at (124, 222) um to
`GEN_WAYS[2]...refill_line_r_reg[100]`, and the same bus feeds way 0 at
(2283, 70), way 1 at (2260, 1939) and way 3 at (2299, 1887): 2.2 to 2.8 mm
per bit, -3.44 ns at 4.0 with TNS -2704 over reg2reg. 19b's placement-stage
worst path was the same bus family (refill set-id from the MSHR to a way's
tag register). Cause is the floorplan `fp_iter16.tcl`: the 16 macros sit on
the four die edges, way 2 down the left, way 1 across the top, way 3 down
the right, way 0 along the bottom, so every structure shared by the four
ways (MSHR refill bus, request/response muxes, replacement) lives in the
middle and must reach all four edges. The MSHR file's 3,062 flops are
already spread over x 17..1757, y 29..1895 trying to. No CTS or netlist
change shortens a 2.5 mm wire; a floorplan that clusters the macros (two
columns, or one quadrant per way with the shared logic at the centre of
the cluster) is the lever for 250 MHz after the tree is fixed, and it is a
placement-stage experiment, not an RTL one.

### 5c. The post-CTS opt re-enables useful skew (2026-09-07 22:40)

ctsE (ctsA cells + `ASIC_CTS_USEFUL_SKEW=0`) left `ccopt_design` at 4.20-4.57 ns, skew 0.37,
Max Level 19, 0 FE_USK cells, and ended stage 04 at Max Level 50 with 296 FE_USK cells:
`setOptMode -reset` before the explicit `optDesign -postCTS` restores `usefulSkew true`, so
the opt pass rebuilt the delay chains ccopt had been told not to build. Its post-CTS reg2reg
(-2.566 at 3.333) is therefore a clean-tree/dirty-opt number, not better than ctsA's -2.41.
`04_cts.tcl` now re-applies the knob after every `setOptMode -reset`; iter22/iter22b are the
first runs with useful skew off in both places. **Result (iter22, 4.0 ns, 2026-09-08 03:20):
stage-04 tripwire Max Level 18, FE_USK 0** - the tree ccopt built (3.99-4.44 ns, skew 0.45,
io_regs 259 sinks within 0.30) survived the post-CTS opt for the first time. Cost on paper:
post-CTS reg2reg -3.154 / TNS -1415 against iter21r's -2.078 / -512 with useful skew on
(same placement, legacy recipe: 46 levels, 222 FE_USK). Hold after fix +0.049. Lesson: any `-reset` of an opt/analysis mode
silently undoes every mode set above it - re-assert the knobs, and read the tripwire at stage
end, not only after ccopt.

## 5b. RC factor: findings, methods, timeline (2026-09-07)

**Question.** Does the pre-route wire model that placement and CTS optimize
against match what Quantus extracts from the routed wires? If not, by how
much, and is a scaling factor the fix?

**Answer.** It matches within a few percent in total. The rc corners' +-10%
placeholders were, by luck, about right. The 5x factor `generateRCFactor`
printed is not supported by direct measurement and was not adopted. The
error that exists is *shape*, not scale: short nets are over-estimated, the
longest nets slightly under-estimated, and no global factor fixes that.

**Timeline, with what was believed at each step.**

| when | event | belief afterwards |
|---|---|---|
| 2026-08-28 | `mmmc.tcl` creates `rc_slow`/`rc_fast` with `-preRoute_res/_cap 1.10` and `0.90`, commented as "mild placeholders, replace if a real extraction deck appears" | unmeasured |
| 09-07 18:30 | 19b's tree: ccopt 7.12-7.64 ns, Tempus signoff 5.53-9.49 ns. Hypothesis written into section 5: RC mis-correlation between the estimator and Quantus | RC is the cause (wrong) |
| 18:21-18:38 | `generateRCFactor -preroute true -reference signoff` on the routed 19b (`07_vssfix.enc`, Quantus techfile on both corners) reports `-preRoute_res 0.205 -preRoute_cap 1.031 -preRoute_clkres 0.247 -preRoute_clkcap 0.949` | estimator R is 5x too high (wrong) |
| 18:39, 19:18 | ctsC and ctsD launched with those factors (`ASIC_CTS_RC_FACTORS=0.205:1.031:0.247:0.949`) | |
| 19:12 | Probe 1: pre-route engine on the *routed* geometry, SPEF vs the export's Quantus-tech SPEF, per net: total R **1.127** (245,808 nets; >500 ohm nets 1.12, 100-500 1.14, 20-100 1.10, <20 1.08). The tables themselves are right. | the 5x is not in the tables |
| 19:29 | Probe 2: detailed routing deleted in a scratch session, `earlyGlobalRoute`, pre-route extraction (exactly what pre-CTS timing sees), same comparison: total R **1.137**; <20 ohm nets **1.74**, 20-100 1.27, 100-500 1.11, >500 ohm **0.90**. Both probes carry the 1.1 factor, so at factor 1.0 the estimator is ~1.03x Quantus in total. | RC is within a few percent; 0.205 unexplained |
| 19:40 | The 19b post-CTS tree structure holds 324 `FE_USK*` useful-skew cells, up to 19 in series; the stage-end skew report already read 7.47-9.83 before routing | skew growth was the optimizer, not RC |

**Methods.** Both probes are reproducible from `scripts/rc_correlate/`:
`estimator_spef.tcl` writes the estimator's SPEF from a routed checkpoint
(restore, `editDelete -type Signal`, `earlyGlobalRoute`, `setExtractRCMode
-engine preRoute`, `extractRC`, `rcOut -spef`), and `compare_spef.sh` joins
it with `outputs/*_pnr.spef` by net name and prints total and bucketed R/C
ratios. Two traps met on the way and fixed in the scripts: `extractRC`
refuses a design with no routes at all (hence the trial route), and the
SPEF `*PORTS` section reuses the `*N` name-map prefix, which silently
overwrote net names until the parser was scoped to `*NAME_MAP` only. Sorting
must be `LC_ALL=C` for `join`. Total C ratios (1.5-1.7) are not comparable:
the reference SPEF separates coupling capacitance, the estimator lumps it
to ground.

**What generateRCFactor did is not known.** Its log shows it reset the
factors to 1.0, extracted with the Quantus techfile, ran an internal
comparison ("ostrich") and printed the `update_rc_corner` lines; no totals,
no per-layer table, no net count. Possible explanations, none verified: a
pattern-based comparison on test structures rather than design nets, a
pre-route mode without the trial route, or a definition that is not the
ratio of totals. Until one is confirmed the number is treated as an
artefact.

**Consequences.**

- iter22 keeps `preRoute_res/_cap 1.10` (or 1.0; the difference is inside
  the measurement noise). The knob `ASIC_CTS_RC_FACTORS` stays for the day a
  measured correction is wanted, now in `res:cap:clkres:clkcap` form via
  `update_rc_corner`.
- ctsC and ctsD were built with clock-wire resistance scaled by 0.247, so
  their insertion delays (4.75-5.29 and 3.57-4.02) are optimistic on the
  wire part and must be re-timed at 1.1, or routed and extracted, before
  they are compared with ctsA (4.17-4.58, factor 1.1).
- The shape error is real and worth remembering when reading pre-route
  slack: a path made of short nets looks up to 1.7x slower on its wires than
  it is, a long trunk about 10% faster. It matters little for the tree
  (cells dominate) and more for hold-fixing decisions on short paths.
- The 25% branch-to-branch mismatch attributed to RC in section 5 was
  mostly the 324 useful-skew cells; the RC share is the -20% on the shortest
  branch (7.47 -> 5.53), consistent with short-net over-estimation.

**Verification going forward.** On every export: run probe 2 and expect the
total near the corner factor; run `generateRCFactor` too and record what it
says next to the direct measurement, so the discrepancy is either explained
or shown to be stable. In CTS: compare ccopt's post-conditioning min/max with
the stage-end skew report (same session), then with Tempus's clock summary;
the first gap is the optimizer, the second is RC plus SI.

## 6. How CTS fit this project's timeline

**Deadline: the signed-off package and its write-up are due 2026-09-14.** Any
new P&R iteration launched after 2026-09-09 cannot be DRC/LVS/IR/EM/Tempus
signed off in time (19b took 2 days from launch to a clean export, plus the
4 h KLayout and the signoff triplet); after that date only re-signoff of an
existing package at an honest period fits.

CTS lives in stage 04 of the 6-stage flow (00 init → 01 floorplan → 02 power →
03 place → **04 CTS + post-CTS opt** → 05 route + post-route opt → 06
fill/export). Practical lessons this stage taught, in ledger order:

- `TCLCMD-1048` (2026-08-28): SDC-style commands after `ccopt_design` need
  `set_interactive_constraint_modes` — the script once died *after* building
  the tree but before saving; the tree was rescued by hand. Now the mode
  switch is explicit and `04_cts_raw.enc` checkpoints the fresh tree before
  optimization touches anything.
- Report commands are wrapped in `catch`: a report-flag version quirk must not
  abort between the expensive `ccopt_design` and `saveDesign`.
- The stage banner line still applies: `postcts_opt/hold.rpt` is *the first
  honest hold number in the whole flow* — everything before it was ideal-clock
  fiction.
- `update_io_latency` (2026-09-07): ccopt's silent post-tree step put a
  one-sided -7.3 ns source latency on `clk`; route and signoff reg2reg numbers
  were 7.3 ns optimistic from iter16b through iter20 (§5, the "gift"). Fix is
  `set_ccopt_property update_io_latency false` + the reference-pin I/O model;
  honest 19b reg2reg is about 7.2 ns, not 3.333.
- `ASIC_CTS_TARGET_LATENCY` is read (default 0.500 ns) but never applied to a
  ccopt property — insertion delay was effectively unconstrained, which is
  part of how 7.4 ns happened. Candidate fix for a future iteration:
  `set_ccopt_property target_insertion_delay`, and judge the cost in tree
  area/power.

## 7. The Tcl, with examples

Everything below is Innovus 21 syntax; lines marked *(ours)* are verbatim from
`scripts/04_cts.tcl` or this repo's runs.

**Setup — before the tree exists:**

```tcl
# Keep the clock (and everything else) off li1; ints: li1=1, met1=2 … met5=6   (ours)
setDesignMode -bottomRoutingLayer 2 -topRoutingLayer 6

# Optional clock-trunk NDR + upper-layer route type (G7a hook)               (ours)
add_ndr -name cts_2w2s -width_multiplier "met3:met5 2" -spacing_multiplier "met3:met5 2"
create_route_type -name cts_trunk -non_default_rule cts_2w2s \
    -bottom_preferred_layer met3 -top_preferred_layer met5
set_ccopt_property route_type -net_type trunk cts_trunk
set_ccopt_property route_type -net_type top   cts_trunk

# Derive the clock structure from the SDC (clocks, generated clocks, sinks)   (ours)
create_ccopt_clock_tree_spec

# Goals                                                                        (ours)
set_ccopt_property target_skew      0.100    ;# ns
set_ccopt_property target_max_trans 0.750    ;# ns — matches golden.sdc's DRC
# The one we did NOT set (and paid 7.4 ns for):
set_ccopt_property target_insertion_delay 0.500

# Other properties you'll see in real flows:
set_ccopt_property buffer_cells   {sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_8}
set_ccopt_property inverter_cells {sky130_fd_sc_hd__clkinv_4 sky130_fd_sc_hd__clkinv_8}
set_ccopt_property routing_top_min_fanout 10000   ;# force a top-level H-tree/mesh style
```

**Build:**

```tcl
ccopt_design                       ;# build + place + route the tree           (ours)
ccopt_design -cts                  ;# variant: tree only, skip the concurrent datapath opt
```

**The regime change — clock becomes real:**

```tcl
set_interactive_constraint_modes [all_constraint_modes -active]  ;# else TCLCMD-1048 (ours)
set_propagated_clock [all_clocks]                                             ;# (ours)
set_clock_uncertainty -setup 0.100 [all_clocks]                               ;# (ours)
set_clock_uncertainty -hold  0.050 [all_clocks]                               ;# (ours)
```

**Inspect — the commands you actually live in:**

```tcl
report_ccopt_clock_trees -summary > clocks.rpt   ;# cells/area/wire/sinks      (ours)
report_clock_timing -type skew    > skew.rpt     ;# per-pin latency + skew     (ours)
report_clock_timing -type latency                ;# min/max insertion delay
get_ccopt_property target_skew                   ;# read any property back
ccopt_check_prerequisites                        ;# lint the spec before building

# Who is the deepest sink? (dbGet spelunking)
dbGet top.nets.name CTS_*                        ;# the tree's generated nets
report_timing -late -max_paths 1 -path_type full_clock   ;# see every tree stage in a path
```

`-path_type full_clock` is the underrated one: it expands the clock network
inside the timing report, so you can watch the 7.4 ns accumulate stage by
stage instead of taking the latency number on faith.

**Post-CTS optimization — order is law:**

```tcl
setOptMode -reset
setOptMode -fixCap true -fixTran true -fixFanout true                          ;# (ours)
optDesign -postCTS          ;# setup first                                     (ours)
optDesign -postCTS -hold    ;# hold second — delay insertion, never before setup (ours)
```

**Worked example — reading our own skew report** (`reports/cts/skew.rpt`):

```text
  Skew     Latency     Clock Pin
           1.597    r  GEN_WAYS[1]…bank_tags_reg[5][15]/CLK
  2.114   -0.517    r  GEN_WAYS[1]…rtag_raw_r_reg[15]/CLK
```

Read it as: the first pin is the *latest* sink (1.597 ns at CTS estimates);
the second line says another pin in the same array is 2.114 ns *earlier* —
that pair's skew. A flag: 2.1 ns of skew between registers in the same
generate block is far beyond the 0.100 target; at CTS-estimate stage that
usually means an unbalanced branch worth checking in the GUI
(`ctd_win`, the CCOpt clock tree debugger) before routing bakes it in.

## 8. Interview drill — questions this project lets you answer from experience

- *What is skew and why does it matter more than latency?* → §1/§5: latency is
  common-mode; skew shifts the setup/hold window. Ours: 0.100 ns target vs
  7.4 ns latency — a 74:1 ratio and the design still times.
- *Why does hold become critical after CTS?* → ideal clock has no skew; real
  trees do; hold fixes are delay insertion and must follow setup fixes.
- *Why inverters in clock trees?* → duty-cycle symmetry + placement freedom.
- *What's useful skew?* → ccopt trading clock arrival between neighbors to
  rescue setup paths, paid for in hold margin.
- *Your insertion delay is 7.4 ns on a 4 ns clock — is the chip broken?* → No;
  explain common-mode, then the three real costs (I/O reference, OCV/CPPR,
  power). This exact question is answerable *only* by someone who has seen it.
- *How would you cut clock power here?* → clock gating (we have none — 35k
  sinks × every cycle), then latency reduction (shallower tree = fewer
  switching stages), then leaf wire reduction via better placement clustering.
- *Where do clock nets get routed and why?* → upper layers, NDR-widened,
  early (before signal routing) — and what happened on iter5 when a trunk
  landed on met1.
