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

## 6. How CTS fit this project's timeline

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
