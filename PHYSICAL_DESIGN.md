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

## 4. Fanout, clock enables, and why storage placement matters

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

## 5. Storage: flops vs RAM primitives vs hard macros

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

Our binding is ASIC-only: the Genus flow passes `-define SRAM_MACRO_BANKS`,
so FPGA and simulation still elaborate the behavioral banks. Same RTL, two
physical realities, zero divergence in verified behavior.

## 6. PVT corners, Liberty files, and derating

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

## 7. Wire modeling: why synthesis numbers are a floor

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
And note: PLE models wires — it does nothing about PVT. Corner choice (§6)
and wire modeling are orthogonal knobs.

## 8. FPGA vs ASIC: one RTL, two different verdicts

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

## 9. Integrating a hard macro — the recipe

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
   inside a generate branch selected by a synthesis define plus a geometry
   check:

   ```systemverilog
   `ifdef SRAM_MACRO_BANKS
       localparam bit USE_SRAM_MACRO = (DEPTH == 256) && (DATA_WIDTH == 32);
   `else
       localparam bit USE_SRAM_MACRO = 1'b0;
   `endif
   if (USE_SRAM_MACRO) begin : g_sram
       sram_1rw1r_32_256_8_sky130 u_sram (...);
   end else begin : g_flops
       // the behavioral / FPGA-inference template
   end
   ```

   Only the ASIC flow passes `-define SRAM_MACRO_BANKS`; simulation and the
   FPGA flow never see the macro, so their results are unchanged *by
   construction* — which you still prove by re-running the regression
   (define off) and elaborating with the vendor's `.v` model (define on).

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

6. **Settle the corner story explicitly** (§6): our macro's only slow lib is
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

## 10. What P&R (Innovus) adds — the next stage for this project

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

## 11. Glossary

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
| WLM / PLE | statistical vs placement-based wire estimation (§7) |
| Hard macro | pre-laid-out block (SRAM) placed as one object |
| CTS | clock-tree synthesis (§10) |
| STA | static timing analysis — exhaustive path checking, no simulation |
| DRC / LVS | geometry rules check / layout-vs-schematic equivalence |
