# Physical Design Notes

Learning-oriented notes on the physical-design concepts this project uses,
anchored to the cache's real numbers. Read top to bottom the first time;
after that it works as a reference. Companion docs: `README.md` (roadmap),
`asic/MACROS.md` (SRAM macro survey + corner decision).

## 1. The journey from RTL to silicon

Our SystemVerilog describes *behavior*. Hardware needs *placed, wired
transistors*. The flow between them:

```
RTL  ->  logic synthesis  ->  place & route  ->  signoff  ->  GDSII (mask data)
         (Genus / DC)         (Innovus)          (STA, DRC, LVS)
```

- **Logic synthesis** maps RTL onto a library of prebuilt **standard cells**
  (NAND, mux, flop...) and optimizes the network against a timing target.
- **Place & route (P&R)** decides where every cell physically sits and draws
  every wire on the metal layers.
- **Signoff** re-checks timing with real extracted wires (STA), and checks the
  geometry obeys manufacturing rules (DRC) and matches the netlist (LVS).

This project is currently at the end of logic synthesis, about to start P&R.
The same RTL also targets an FPGA (Vivado), which is a *different* physical
reality — prefabricated lookup tables and routing — and that difference shows
up everywhere in the results (see §3).

## 2. PPA — the three-way trade

Every decision is judged on **Power, Performance, Area**. "Performance" here
is **Fmax**, the highest clock frequency the slowest path allows. You rarely
improve one leg without paying another; the interesting optimizations (like
this campaign's) improve one leg for free because they remove *waste*.

## 3. Timing: how "how fast" is actually computed

A synchronous design moves data flop -> logic cloud -> flop every cycle. For
each such path the tool computes **slack**:

```
slack = clock period - (clock-to-q + logic delay + wire delay + setup time)
```

- **WNS** (worst negative slack): the single worst path's slack. Defines Fmax:
  `Fmax = 1 / (period - WNS)`. Our FPGA runs constrain at an impossible 1 ns
  on purpose, so WNS of -2.169 ns means the design really runs at
  1/(3.169 ns) = 315 MHz.
- **TNS** (total negative slack): the sum over all failing paths — how *broad*
  the problem is, not just how deep.
- A timing report names a **startpoint** (a flop's clock pin), an **endpoint**
  (a flop's D or CE pin), and every cell and wire hop between. Learn to read
  the per-hop `Incr` column: it tells you whether the path is **logic-bound**
  (many gate levels) or **wire-bound** (few levels, long routes).

Concrete example from this repo (the path Entry 7 killed): 10 logic levels
but 66% of the delay was routing, ending on a net driving 133 flop clock
enables. The fix didn't shorten the logic — it moved the wide net onto a
shallow source. Fanout, not depth, was the disease.

### Populations, not single paths

One worst path is an anecdote. We always census the worst 1000 paths and
group them by startpoint -> endpoint pair. A fix is judged by whether its
*population* disappears, because the #2 path is usually 5 ps behind #1.
After a fix, a new population becomes the wall — timing closure is peeling
an onion.

## 4. Inside logic synthesis — the stages

§1 treated synthesis as one box. It is really five stages run in order, and
each can only fix certain kinds of problem. Knowing which stage owns your
problem is the difference between a fix that works and three hours spent
waiting for a tool that was never going to save you.

The commands below are our Genus flow
(`asic/synthesis/cadence/scripts/run_genus.tcl`). Design Compiler and Vivado
differ in vocabulary, not in shape.

### The five stages

**1. Read and elaborate** — `read_hdl -sv` then `elaborate`.

Parses the SystemVerilog, resolves parameters, unrolls `generate` blocks, and
builds a **generic netlist**: RTL operators (adders, muxes, comparators) with
no technology behind them yet. There is no timing at all at this point.

Two things bake in here permanently:

- **Parameters.** `elaborate -parameters {CACHE_BYTES 16384} {ASSOC 4}` renames
  the design to `Cache_CACHE_BYTES16384_ASSOC4`. That name is your receipt —
  it is how you confirm after the fact which configuration a run actually
  built.
- **Generate branches.** `USE_SRAM_MACRO` picks the macro or the flop banks
  *here*, before any timing exists. A macro that "didn't bind" was never going
  to; no later stage adds one. This is why the flow counts macro instances
  right after elaboration and fails loudly at zero (§10, step 7).

**2. Constrain** — `read_mmmc`, `read_physical -lefs`, `init_design`.

Loads the library set and corners (the analysis view, §7), the SDC (clock
period, I/O delays, exceptions), and the LEF that makes physical estimation
possible. An unconstrained design has no target: the tool will cheerfully hand
back something small and slow. **Every number produced downstream is relative
to what you set here** — quoting a WNS without naming the period and corner is
meaningless. There is also an ordering trap: `read_physical` requires the
design to be timing-initialized already, which is why the script's sequence is
commented rather than obvious.

**3. Generic synthesis** — `syn_generic -physical`: technology-*independent*
optimization.

Constant propagation, dead-logic removal, resource sharing, datapath
architecture selection (which adder topology), and **structuring** — factoring
common subexpressions out of your logic. Still generic gates; no real cells.

This stage rewrites your coding style, which cuts both ways. It is where
well-intentioned RTL gets undone: Entry 13 wrote a 3-level prefix-OR and
subexpression sharing serialized it into 6 levels. **If your careful structure
vanished between RTL and the netlist, suspect this stage first.**

**4. Technology mapping** — `syn_map -physical`.

Generic operators become **real standard cells** chosen from the `.lib`: which
gate, which drive strength, which flop. The `-physical` flag means the tool
also does a coarse placement and uses LEF + PLE (§8) to estimate wire lengths,
so it can weigh a bigger gate against a longer wire while choosing. Large
designs are cut into partitions and mapped concurrently (see below).

This is the expensive stage — **5,075 s (85 min)** on our 16KB A4 run.

**5. Incremental optimization** — `syn_opt -spatial`.

The long tail: resize gates, insert repeater chains for fanout, clone
high-fanout drivers, restructure the worst paths, and *recover area* on paths
with slack to spare. Most of a run's wall clock lives here.

What it **cannot** do is change your architecture. It buys picoseconds with
transistors. When a path is long because of a structural mux tree, syn_opt
grinds for hours and returns almost nothing — which is itself a signal, and a
valuable one.

Then `write_hdl` + the report suite hand off to P&R (§11).

### Reading a run's trajectory

The stage boundaries are visible as a slack trajectory. From the 16KB ASSOC=4
flop-bank run of 2026-08-21:

| Moment | WNS @ 3.5 ns | Instances | Cell area |
|---|---|---|---|
| after partitioning | -3106 ps | — | — |
| post-map (`M:Cleanup`) | -2601 ps | 598,120 | 6.45 mm² |
| 2.5 h into serial `incr_tns` | -2585 ps | — | — |
| `init_delay`, just after partition assembly | **-3382 ps** | — | — |
| after the distributed `pbs_iopt` pass | -2326 ps | — | — |
| **final** (6h18m total) | **-2163 ps** | 693,356 | 7.39 mm² |

Four lessons, and the last two only exist because we watched the whole run
instead of the first half:

- **Mapping does the heavy lifting; opt does refinement.** -3106 → -2601 came
  from choosing real cells. Expect the shape of your result to be set by the
  end of `syn_map`.
- **Know which phase you are in before concluding opt has given up.** The
  serial `incr_tns` loop moved 16 ps in 2.5 hours, which looks exactly like a
  tool out of ideas. It wasn't finished — a *distributed* `pbs_iopt` pass
  followed and took another 422 ps. Reading "opt has stalled" off one phase is
  how you kill a run an hour before its best work.
- **A slack spike at a phase boundary is not a regression.** `init_delay`
  reported -3382, worse than anything before it, because partitions optimize
  against allocated *budgets* and assembly re-times the design for real. The
  budgets flattered; assembly told the truth; the next pass recovered it. Read
  `init_*` rows as starting points, never as results.
- **A path that survives every phase is structural.** `order_head_r →
  mem_req_wdata` — a grant-selected mux tree reading the victim buffer — held
  WNS through mapping, serial opt, eight partitioned opt jobs, and reassembly.
  *That* is the signal worth acting on, not the stall. No amount of gate
  resizing shortens a mux tree; only RTL does.

One more trap: **area goes *up* during opt, not down** — the tool spends
transistors to buy time. Three measured runs, and note the spread:

| Run | post-map | final | growth |
|---|---|---|---|
| 4KB A4 (Entries 1-5) | 2.18 mm² | 2.30 mm² | +5.3% |
| 16KB A4 (Entries 1-8) | 7.51 mm² | 8.24 mm² | +9.7% |
| 16KB A4 (E9-E19a) | 6.45 mm² | 7.39 mm² | **+14.6%** |

Budget 5-15%, not a single number, and expect the harder-pressed run to grow
more — it has more failing paths to buy. The mechanism is visible in the
instance count: 598,120 cells at post-map became 693,356 final, ~95k of them
buffers and repeaters inserted to fix fanout. Never quote final area from the
post-map checkpoint.

### Reading the mapping stage summary

When a partitioned mapping stage finishes, Genus prints a per-partition table.
Ours had five partitions; the shape to read:

```
PARTITION                2         5         3         1         4
PRE_WNS              -2887      -272      -386      -585      -321
POST_WNS             -2861      -521      -470      -580      -462
POST_PORT_CNT        18666     18134       575      1015       578
PRE_AREA           1657145   2400085   1723982   1776948   1722179
POST_AREA          1024224   1618806   1188626   1246272   1200348
PRE_LEAK_PWR        292595    770774    518803    541210    518600
POST_LEAK_PWR       629300    994167    740098    813546    759454
Total Elapsed         2167      1984      1697      1652      1593
```

`PRE_*` is the partition entering mapping (generic gates, scored against an
allocated timing *budget*); `POST_*` is after mapping to real cells. Slack is
in ps, area in µm², leakage in library power units.

Three things worth looking for:

1. **Which partition owns WNS** — partition 2 here, at -2861. Its
   `PORT_CNT` tells you what that partition *is*: 18.6k boundary ports means
   datapath (our 128-bit line plumbing), while the ~600-port partitions are
   control logic. That is a free structural hint about where your problem
   lives.
2. **`POST_AREA` below `PRE_AREA` is normal** (~-30%): generic operators
   collapse into real cells. **Leakage roughly doubling is also normal** — the
   mapper bought speed with faster, leakier cells.
3. **`POST_TNS` worse than `PRE_TNS` is not a regression.** Pre-numbers are
   scored against per-partition budgets, post-numbers against real mapped
   delay. `syn_opt` recovers it.

The stage also reports its own parallelism. Our partitions summed to 9,093 s
of work but `M:Distributed` was 2,171 s ≈ the longest single partition
(2,167) — they genuinely ran concurrently. `PBS Index: 0.84` scores how evenly
the cut balanced; near 1.0 is ideal.

### Practical notes for this flow

- **Genus exits 1 on success.** A `write_sdc -view` bug makes the run return a
  nonzero status even when everything completed. Check for the presence of
  `reports/`, never `$?`.
- **`PHYS-1015` spatial fallback is expected.** `opt_spatial_effort` above
  standard wants probabilistic extraction we don't have (no QRC), so the flow
  falls back. Not an error.
- **Checkpoint after mapping.** The script writes a `post_map` database
  because generic + map are the expensive part. A `syn_opt` that dies can be
  salvaged by re-reading that db and re-running opt only — we did exactly that
  on 2026-08-20, turning a lost 3-hour run into a 45-minute recovery.
- **Read the threading advisory.** The log prints how much time more
  super-threading servers would have saved (ours claimed 5,780 s with 3, 7,216
  s with 5). We currently set no `super_thread_servers` at all — free runtime
  sitting on the table when a run costs four hours.

### The FPGA analogue

Vivado runs the same five ideas under different names: `synth_design`
(elaborate + generic + map, targeting LUTs and FFs instead of standard cells)
→ `opt_design` → `place_design` → `phys_opt_design` → `route_design`. The
mapping target is fixed silicon rather than a cell library, and because Vivado
routes for real, its numbers are post-route truth while Genus's stop at an
estimate (§8).

### Which stage owns your problem

| Symptom | Stage that owns it | What to do about it |
|---|---|---|
| Macro/branch didn't appear in the netlist | elaborate | It's a parameter or geometry gate. No later stage adds one. |
| Your careful RTL structure vanished | `syn_generic` | Subexpression sharing re-factored it. Pin with `keep`/`dont_touch` — sparingly; Entry 17 showed accumulated pins become a straitjacket. |
| Worst path is deep logic (many levels) | your RTL | Precompute a cycle earlier, or re-architect. Opt cannot fix depth. |
| Worst path is high fanout, few levels | `syn_opt` | It will clone and buffer. If it still can't, move the signal to a shallower source (§5). |
| WNS barely moves over hours of opt | your RTL | Structural. Opt has done what it can — the fix is upstream. |
| Area looks wrong | `syn_opt` | You're reading the post-map checkpoint; opt adds ~5%. |

## 5. Fanout, clock enables, and why storage placement matters

The recurring lesson of this campaign, four entries in a row:

> A signal computed late (through deep logic) must never drive something
> wide (thousands of flop enables, a big decoder).

Late x wide = the tool inserts repeater chains and still loses. The cures we
used, in increasing strength:

1. **Precompute** the decision a cycle earlier and register it (Entry 4).
2. **Load-gate**: let harmless capture registers load unconditionally off a
   shallow signal; keep the guarded decision on a narrow D input (Entry 7 —
   1064 enable pins moved off the deep cone, replaced by 32 D bits).
3. **Stop moving the data**: replace a shifting queue with static storage
   plus moving *pointers* (Entry 8 — the RS victim side-buffer; ~2.5k flops
   stopped re-writing on every retire).
4. **Change the storage primitive** entirely (Entry 5, and the SRAM macros).

## 6. Storage: flops vs RAM primitives vs hard macros

A flip-flop is the most expensive way to store a bit: ~20 um^2 in SKY130 HD,
a clock pin that burns power every cycle, and a write port that needs a
decoder + enable per bit. Fine for 30 control bits; catastrophic for 131,072
data bits (our 16KB array).

- **FPGA**: code a memory as the canonical "one write port, one sync read,
  no reset, no bypass" template and the tool *infers* LUTRAM or BRAM —
  purpose-built memory silicon. Entry 5 did this: -75% LUTs, -82% dynamic
  power, and the enormous enable fanout vanished *by construction*.
- **ASIC**: there is no inference. You instantiate a **hard macro** — a
  pre-laid-out SRAM block (ours comes from OpenRAM). A macro ships as views:
  - `.lib` (Liberty): timing/power arcs per corner — what STA reads.
  - `.lef`: the abstract footprint — outline, pin locations, blockages —
    what placement/routing reads. (The full polygons stay in `.gds`.)
  - `.v`: a behavioral model for simulation only.
  The synthesizer treats the macro as a black box with known timing at its
  boundary; P&R treats it as a large fixed rectangle to place around.

Our binding is ASIC-only: the Genus flow sets the `EN_SRAM_MACRO` parameter,
so the FPGA flow still elaborates the behavioral banks. Same RTL, two
physical realities, zero divergence in verified behavior.

## 7. PVT corners, Liberty files, and derating

Silicon speed varies with **P**rocess (fab luck), **V**oltage, and
**T**emperature. A standard-cell library is characterized at specific PVT
points — each `.lib` file IS one corner:

- `ss_100C_1v60` — slow silicon, hot, 11% under nominal voltage. Our setup
  (worst-case) signoff corner: if timing closes here, it closes everywhere.
- `ff_n40C_1v95` — fast, cold, high voltage: the *hold*-check corner (fast
  paths can beat the clock and corrupt the receiving flop). Hold is fixed
  after clock-tree synthesis in P&R, not at synthesis.
- `tt_025C_1v80` — typical: realistic power numbers, never timing signoff.

**MMMC** (multi-mode multi-corner) is how tools organize this: a *library
set* (which .libs) + *constraint mode* (which SDC) = an *analysis view*.
Our synthesis deliberately uses ONE view (setup at ss_100C_1v60).

**When corners don't match** — our macro's only slow lib is SS at 1.8V/25C,
but our cells sign off at 1.6V/100C — you either move the whole flow to a
shared corner (destroys comparability with all previous numbers), or keep
your corner and apply a **timing derate**: multiply the mismatched block's
delays by a safety factor. We measured the macro's own voltage (+5.7% per
-0.1V) and temperature (+1.2%/degC) sensitivities from its TT lib family and
chose x2.0 — provably enveloping the gap. Lesson: a derate should be
*derived*, not guessed. Second lesson: characterization data can be broken
(the macro's TT/100C lib reports 7.8 ns — 13x out of family; we blacklisted
it). Always sanity-check a .lib against its siblings before trusting it.

## 8. Wire modeling: why synthesis numbers are a floor

Gates are only half the delay; wires are the other half, and synthesis
doesn't know where anything is yet. Three levels of truth:

1. **Wire-load models (WLM)**: statistical guesses from fanout ("net area
   0.000" in a report = wires cost nothing). Our old DC/Genus flow — numbers
   were optimistic fiction.
2. **Physical-aware synthesis (PLE)**: the tool reads the cell **LEF** and a
   rough floorplan, does a quick placement, and estimates real wire lengths.
   Our rebuilt Genus flow. Much better, still an estimate.
3. **Post-route extraction**: actual drawn wires with parasitics — only P&R
   gives this. The FPGA numbers in this repo are post-route (Vivado routes
   for real), which is why we trust their wire story more than Genus's.

Rule of thumb we keep re-learning: **post-P&R slack is worse than synthesis
slack, never better**. Treat every synthesis WNS as a floor on the problem.
And note: PLE models wires — it does nothing about PVT. Corner choice (§7)
and wire modeling are orthogonal knobs.

## 9. FPGA vs ASIC: one RTL, two different verdicts

The same RTL ranked associativity differently on the two targets (FPGA said
A4, ASIC said A8; after Entry 5 they disagreed again the other way). Neither
meter is wrong — they measure different physics:

- FPGA logic depth comes in LUT quanta; a 25-bit compare is ~3 levels, and
  **routing dominates** (66-79% of our worst paths) because signals travel
  prefabricated switch fabric.
- ASIC depth is counted in gate levels (31 levels on the old worst path) and
  fanout is repaired with **inserted repeater chains** you can see in the
  report (12 of those 31 levels were repeaters).
- Storage flips the comparison hardest: FPGA gets LUTRAM "for free"; ASIC
  pays flop area until you do the macro work.

Use each meter for what it sees: our FPGA runs can't see the Reservation
Station at all (0 of 1000 worst paths) — only Genus can. Know your meter's
blind spots before believing a null result.

## 10. Integrating a hard macro — the recipe

What "using an SRAM macro" actually takes, in the order that avoids pain.
This is exactly what this repo did on 2026-08-20; the concrete artifacts are
in `Flag_Tag_Data_Array.sv`, `asic/synthesis/common/scripts/project_config.tcl`,
`asic/synthesis/cadence/scripts/run_genus.tcl`, and `asic/MACROS.md`.

1. **Shape the RTL first, long before touching the macro.** A macro has a
   rigid port profile; your RTL memory must already look like it. Entry 5 did
   this months of work early: one write port, one sync read, binary address,
   no reset, no internal bypass. Because of that, integration day was pure
   wiring — zero architecture change. If your RTL needs 2 write ports or an
   async read, no macro exists and you redesign *first*.

2. **Pick the macro by port profile and exact geometry.** Survey what the
   PDK offers (ours: `asic/MACROS.md`). We needed 256 deep x 32 wide per
   bank; `sram_1rw1r_32_256_8` is *exactly* that, so 16 instances cover
   16KB ASSOC=4 at 100% utilization. A macro that's the wrong depth wastes
   silicon (half-used) or forces ugly banking logic around it.

3. **Bind it conditionally, not unconditionally.** The instantiation lives
   inside a generate branch selected by a **parameter** plus a geometry check:

   ```systemverilog
   localparam bit USE_SRAM_MACRO =
       EN_SRAM_MACRO && (DEPTH == 256) && (DATA_WIDTH == 32);

   if (USE_SRAM_MACRO) begin : g_sram
       sram_1rw1r_32_256_8_sky130 u_sram (...);
   end else begin : g_flops
       // the behavioral / FPGA-inference template
   end
   ```

   A parameter, not a `` `define ``, and that choice was forced: the OpenFLEX
   YAML configs driving the FPGA flow can't pass defines, so a define-gated
   macro would have been unreachable from one of our two meters. Genus sets it
   with `elaborate -parameters {EN_SRAM_MACRO 1}`; the FPGA flow leaves it at
   its `1'b0` default. The geometry terms matter as much as the enable — they
   are why only 16KB ASSOC=4 binds today (256x32 banks); every other
   associativity silently falls back to flops, which is what step 7's
   zero-instance guard exists to catch.

   Note the testbench defaults `EN_SRAM_MACRO=1`, so simulation exercises the
   macro branch through the vendor's `.v` model rather than avoiding it — the
   ASSOC=4 DUT runs macros while the other four cover the behavioral banks in
   the same regression.

4. **Read the macro's Verilog header for pin semantics before wiring.**
   OpenRAM pins are active-low (`csb` chip select, `web` write enable) and
   the write mask is per byte. Ours: port 0 is write-only
   (`csb0 = web0 = !bank_wen_c`, `wmask0 = 4'hF`, `dout0` unconnected),
   port 1 is the every-cycle read (`csb1 = 0`, `addr1 = raddr`). Also
   re-verify read-during-write semantics — a macro is *undefined* on a
   same-address collision, so the architecture must already tolerate that
   (ours does: a colliding word is `word_valid=0` to its reader).

5. **Feed each tool the view it reads.** Three views, three consumers:
   - `.lib` -> the timing library set. Synthesis then *binds* the
     unresolved RTL instance to the Liberty cell by name — no Verilog stub
     needed. (In our Genus flow: the macro lib joins `ss_libs` in the
     generated MMMC file.)
   - `.lef` -> `read_physical`, so PLE/placement knows the block's footprint
     and pin locations.
   - `.v` -> simulation only. Never hand a behavioral model to synthesis.

6. **Settle the corner story explicitly** (§7): our macro's only slow lib is
   SS_1p8V_25C vs cell signoff at ss_100C_1v60, closed with a derived x2.0
   late derate on the macro instances — applied in the flow as
   `set_timing_derate -delay_corner ss_corner -late 2.0 <insts>` (this
   Genus *requires* naming the delay corner).

7. **Make the flow fail loudly on silent fallback.** The generate-else means
   a geometry mismatch quietly synthesizes flops — and would report
   flop-bank numbers under a macro-labeled run. Our script counts macro
   instances after elaboration and kills the run at zero. Also tag the
   output directory (`_sram` suffix) so netlists can't be confused.

8. **Expect physical friction and log it.** Our macro LEF trips ~21
   PHYS-148 "undefined pin layer" errors against the standard-cell tech
   LEF — tolerated at synthesis (pin modeling is crude in PLE anyway), but
   on the list to resolve properly at Innovus, where macro placement,
   halos, and power hookup become real.

### Is our synthesis "MMMC"?

Structurally yes, semantically single-corner — deliberately. The Genus flow
speaks the MMMC command set (`create_library_set` -> `timing_condition` ->
`delay_corner` -> `constraint_mode` -> `analysis_view`, loaded via
`read_mmmc`), because that's the only mode where this Genus lets LEF-driven
physical estimation work. But it defines exactly ONE analysis view
(`ss_view` = ss_100C_1v60 + golden.sdc) used for both setup and hold. That's
the right scope for synthesis: hold numbers are meaningless before a real
clock tree exists, so a fast-corner view would add runtime and no
information. True multi-view analysis (setup at ss, hold at ff_n40C_1v95)
enters at Innovus CTS. The macro integration didn't change this shape — the
macro's `.lib` simply joined the one existing library set, and its corner gap
is carried by the derate instead of a second view.

## 11. What P&R (Innovus) adds — the next stage for this project

1. **Floorplan**: die size, pin locations, and where the 16 SRAM macros sit.
   Macro placement is the highest-leverage manual decision — bad macro
   placement is unfixable by any later step.
2. **Power grid**: rings and straps; IR drop is why we sign off at 1.6V.
3. **Placement**: cells get real coordinates; congestion becomes visible.
4. **Clock-tree synthesis (CTS)**: the ideal clock becomes a real buffer
   tree with **skew** and **insertion delay**; hold checks now mean
   something and get fixed here.
5. **Routing**: every net drawn on metal; shorts/spacing (DRC) resolved.
6. **Signoff STA** with extracted parasitics — the first *true* numbers.

Everything before this point was prediction; P&R is where predictions meet
geometry.

## 12. Glossary

| Term | Meaning |
|---|---|
| WNS / TNS | worst / total negative slack (§3) |
| Fmax | 1 / (period - WNS) |
| CE | flop clock-enable pin — a favorite hiding place for fanout disease |
| Standard cell | prebuilt logic gate at fixed height, from the PDK library |
| PDK | process design kit — everything the fab gives you (SKY130 here) |
| Liberty / .lib | per-corner timing+power characterization of cells/macros |
| LEF | abstract physical view: footprint + pins, no transistor detail |
| GDSII | full mask geometry — the final deliverable |
| Corner / PVT | one (process, voltage, temperature) characterization point |
| MMMC | multi-mode multi-corner analysis organization |
| Derate | multiplier on delays to cover modeling gaps (ours: x2 on macros) |
| WLM / PLE | statistical vs placement-based wire estimation (§8) |
| Hard macro | pre-laid-out block (SRAM) placed as one object |
| CTS | clock-tree synthesis (§11) |
| STA | static timing analysis — exhaustive path checking, no simulation |
| DRC / LVS | geometry rules check / layout-vs-schematic equivalence |
