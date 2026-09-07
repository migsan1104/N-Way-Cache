# Gate-level simulation (GLS) for the cache

Written 2026-09-07, after the iter19b export. This is both the tutorial and
the plan; the "Status" section at the end is the ledger.

## 1. What GLS is, and what it is for

RTL simulation checks that *your description* of the design behaves. Gate-
level simulation re-runs the same testbench against the *netlist the tools
produced* - standard cells and macros wired together - to check that what
will be manufactured still behaves, and (with delays annotated) that it
behaves **at speed**. Nothing else in the flow does this end to end:

| Question | Who answers it | What GLS adds |
|---|---|---|
| Is the netlist logically the RTL? | equivalence checking (Conformal / Formality) - not in this flow | GLS is the poor man's LEC: if the regression passes on the netlist, synthesis/P&R did not break function on the paths the tests exercise |
| Does every path meet timing? | STA (Tempus) - exhaustive, but static | GLS shows the *dynamic* consequence: a setup violation becomes an X that propagates, or a wrong value the scoreboard catches |
| Does the design come out of reset cleanly? | nobody, exhaustively | gate models start every flop at X; anything the reset strategy misses shows up as X on a real output. This design stripped reset from all but ~590 architectural flops (E29 campaign), so this is a real question here |
| Simulation/synthesis mismatches | lint, if you have it | `translate_off`, incomplete sensitivity lists, `x` handling in `casez`, initial blocks - all invisible to STA, all visible in GLS |
| Are the deliverables usable? | nobody | the netlist + SDF the export wrote are what a customer or a DFT/ATE team would receive; GLS is the first consumer that actually reads them |

What GLS is **not**: it is not timing signoff (STA is exhaustive, GLS only
sees the paths the stimulus toggles), it is not coverage, and it is slow -
expect 10-50x the RTL wall time for the same stimulus.

## 2. Where it sits in the flow - there are two of them

```
RTL ──sim──► Genus ──► mapped netlist ───► Innovus ──► export ──► netlist + SDF + GDS
                            │                                       │
                     (a) post-synthesis GLS                 (b) post-layout GLS
                     zero/unit delay, functional            SDF-annotated, at speed
```

**(a) Post-synthesis GLS.** Netlist from Genus, cell models in *functional*
mode (no delays, or unit delays), no SDF. Purpose: catch synthesis-level
mismatches early (the RTL had something synthesis interpreted differently),
validate that the netlist even elaborates against the testbench, and get the
reset/X story right before spending hours on the annotated run. Cheap:
compile in minutes, run in well under an hour. Genus can write an SDF from
its wire-load / PLE estimates, but this flow never asked it to, and an
estimate-based SDF adds little over STA; zero-delay is the standard choice.

**(b) Post-layout GLS.** Netlist from the Innovus export (clock tree, hold
buffers, tie cells, diodes all present), cell models *with* their `specify`
blocks, delays back-annotated from the SDF the export wrote from extracted
parasitics. Purpose: the at-speed check - the same regression at the target
clock period, with the simulator enforcing every `$setuphold` / `$width` /
`$recrem` check in the cell models. This is the one tapeout reviews ask about.
Run it at least at the setup corner (slow, MAXIMUM delays) and the hold
corner (fast, MINIMUM delays); a design with multiple modes runs each.

Both use the **same testbench and the same tests**. The only things that
change are which module sits in the DUT slot and what the simulator loads
around it.

## 3. Inputs, and where each comes from in this repo

| Input | Post-synthesis | Post-layout | In this repo |
|---|---|---|---|
| netlist | Genus `write_hdl` | Innovus `saveNetlist -excludeLeafCell` | `asic/PPA/genus/assoc_4/runs/<stamp>/netlist/*_mapped.v`; `asic/PnR/innovus/runs/<stamp>/outputs/*_pnr_sim.v` (physical-only cells stripped; the `_pnr.v` and `_pnr_lvs.v` variants are for Tempus and LVS) |
| standard-cell models | PDK Verilog, `FUNCTIONAL` | PDK Verilog with `specify` blocks | `$PDK/libs.ref/sky130_fd_sc_hd/verilog/{primitives.v, sky130_fd_sc_hd.v}` - one file, 1,664 timing blocks. **One cell (`lpflow_bleeder_1`) has a specify path on `VPWR` outside its `USE_POWER_PINS` guard and breaks the compile**; the netlist never uses it, so the run script must compile a filtered copy (step 0 below) |
| macro model | behavioural | behavioural (no timing) | `extra_rtl/sram_1rw1r_32_256_8_sky130_sim.v`, already in `filelist.f`. The SDF has no entries for the 16 SRAM instances, so macro access time is **not** simulated - only the .lib in STA knows it |
| SDF | none (or Genus estimate) | Innovus `write_sdf` at export | `outputs/*_pnr.sdf`. **Written from one view only**: header says 1.76 V / -40 C and every triplet is `min::max` identical - that is the *hold* (fast) corner. See the SDF corner note below |
| testbench | `Test_Complete` unchanged | `Test_Complete` unchanged | `+define+GLS` makes the ASSOC=4 DUT slot instantiate `Verification/Cache_gls_wrap.sv`, which drops in the netlist; the other four associativities stay RTL. `-defparam Test_Complete.ASSOC=4` limits the run to that DUT |
| clock period | anything | the target period | TB default is 10 ns (`always #5`); `+define+GLS_HALF_PERIOD=1.6667` makes it 3.333 ns |
| timing checks | off | on, eventually | `+notimingchecks` disables them; see the section on why the first annotated run keeps them off |
| driver | `xcelium/run_gls.sh <pnr_stamp> [req_prob] [resp_prob]` | same | writes `logs/gls_sdf.cmd`, compiles into `xcelium_gls.d`, log `logs/xrun_gls.log`, same PASS banner as `run.sh` |

The SDF annotation itself is a three-line command file:

```
COMPILED_SDF_FILE "<stamp>/outputs/Cache_16384B_assoc4_sram_pnr.sdf"
SCOPE Test_Complete.GEN_ASSOC_SET[2].DUT.u      ;# ASSOC_IDX_4 = 2, then wrapper.u
MTM MAXIMUM                                     ;# or MINIMUM for the hold run
```

`SCOPE` must be the instance whose *cells* the SDF names, i.e. the netlist
module instance, not the wrapper. `-sdf_verbose` makes xrun list every cell
it could not annotate - the count must be zero except the 16 macros.

## 4. Things that bite, and what they mean here

**SDF corner.** `write_sdf` with no options writes the delays of the current
analysis view. Ours came out at the fast corner, so a "MAXIMUM" run today
would be an at-speed check at -40 C / 1.76 V, which proves nothing about the
100 C / 1.60 V setup corner Tempus signed off. The fix is in the export:
`write_sdf -min_view hold_view -max_view setup_view` gives real
`min::max` triplets in one file, and the two GLS runs pick with `MTM`. It is
a one-line change in `06_export.tcl`, but it means a re-export (13 min on
19b) to get a usable SDF. Genus SDF is the same story if ever written.

**Timing checks versus how the testbench drives.** The cell models' `$setuphold`
checks fire on the *flop* clock, which arrives about 2.3 ns after the port
clock (Tempus's measured io clock latency). The testbench drives inputs with
non-blocking assignments at the port clock edge, i.e. 2.3 ns *before* the
flops sample - fine for setup, but any port-to-flop path whose delay lands
inside the hold window of that delayed clock reports a violation, and the
simulator then puts an X on that flop. That is an artefact of the testbench
having no input-delay model, not a design bug: `golden.sdc` promises inputs
0.700 ns after the edge and outputs sampled 0.300 ns before it, and Tempus
closed the design against that contract. Consequences:

- The first annotated run keeps checks **off** (`+notimingchecks`): every
  gate has its real delay, the design must produce the right data at the
  right cycle, but the simulator does not police setup/hold. This catches
  functional and X problems and validates the netlist + SDF pair.
- The at-speed run with checks **on** needs the testbench to honour the
  contract: drive requests `#0.7` after the edge and sample responses
  `#(period-0.3)` after it. That is a `GLS_IN_DELAY` knob in the helpers'
  drive tasks, not yet written. Without it a checks-on run reports
  violations that mean nothing.
- `$width` / `$recrem` checks on reset are also expected to fire once at
  time 0 in any GLS; the standard answer is `-negdelay` for the model's
  negative hold values and a `$assertoff`-style suppression until reset
  releases.

**X at time zero.** Every gate-model flop powers up at X, exactly like RTL
`logic`. The RTL regression already passes with X-at-start, so functionally
the design tolerates it. What changes at gate level is *pessimism*: a
`mux2` with an X select outputs X even when both data inputs agree, whereas
RTL `? :` often resolves it. If the post-layout run fails where RTL passed
and the failing signal is X, look for exactly this before suspecting timing.

**Speed.** 242k cells with `specify` blocks and a 260 MB SDF. Budget an hour
to compile and annotate and several hours for the full 200k-request ASSOC=4
regression at 1.0/1.0 pressure. The 0.8 pressure run doubles it. The
`TEST<n>_NUM_*` localparams at the top of `Test_Complete.sv` are the only
traffic knob; a GLS-specific reduced profile is reasonable if wall time
matters, as long as it is stated with the result.

**Things absent from the sim netlist.** Fill, decap, and tap cells (physical
only - `saveNetlist -excludeLeafCell` drops them). Antenna diodes are kept
(they have a pin) and the model exists. The 666 `UNCONNECTED*` nets Tempus
warns about are unloaded outputs; harmless.

**Timescale.** Cell models and SDF are `1ns/1ps`; `run_gls.sh` passes
`-timescale 1ns/1ps` so the SDF's 0.226 means 226 ps everywhere.

## 5. Plan

Ordered cheapest-first; each step is a gate for the next.

0. **Library filter.** Generate `xcelium/gls_lib/sky130_fd_sc_hd_gls.v` from
   the PDK file with the `lpflow_bleeder_1` module removed (awk over
   `module`/`endmodule`; the run script does it and checks the cell list of
   the netlist against the surviving modules). Compile-only check, minutes.
1. **Post-synthesis GLS, zero delay.** Genus mapped netlist of the frozen
   e35abcde run (the one iter19b was built from), `+define+FUNCTIONAL` on the
   cell models, no SDF, 10 ns clock, full ASSOC=4 regression at 1.0 and 0.8.
   Pass criterion: the same banner as the RTL regression. This is the
   sim/synth-mismatch and reset/X check, and it tells us the wrapper and
   filelist are right before the slow run. About an hour.
2. **Post-layout GLS, annotated, checks off.** 19b `_pnr_sim.v` + the export
   SDF as-is (fast corner), `MTM MAXIMUM`, 10 ns clock. Validates that the
   SDF annotates cleanly (zero unannotated cells beyond the macros) and that
   the routed netlist with real delays is still functionally the RTL.
   Several hours; runs in the background alongside the chain.
3. **Fix the SDF corner in the export** (`write_sdf -min_view hold_view
   -max_view setup_view`), re-export 19b (13 min; nothing else in the package
   changes, so KLayout/LVS/Tempus results stand), and re-run step 2 at
   `GLS_HALF_PERIOD=1.6667` with `MTM MAXIMUM` - the real at-speed run at the
   ss corner, still checks off.
4. **Checks on.** Add `GLS_IN_DELAY` to the helper drive tasks so the
   testbench honours the 0.700 / 0.300 ns io contract, then step 3 again
   with timing checks enabled, plus the same at `MTM MINIMUM` for hold. A
   clean run here is the statement "the netlist runs the regression at
   300 MHz with every cell-level timing check enforced".

What to claim once done, and no earlier: after step 2, "post-layout gate-
level simulation with SDF back-annotation passes the full regression";
after step 4, "... at 3.333 ns with timing checks, at both signoff corners".

## 6. Decisions still open

- Corner set: the two Tempus corners (ss 100 C / 1.60 V for setup, ff -40 C /
  1.76 V for hold) mirror the `mmmc.tcl` views and are the obvious pair.
- Traffic: full regression (hours) versus a reduced GLS profile (state it).
- Whether to also GLS the 16b package for the 250 MHz claim; the flow is
  identical, only the stamp changes.

## 7. Status

- 2026-09-07 00:23 - `Cache_gls_wrap.sv`, the `TC_DUT_MODULE` / `GLS_HALF_PERIOD`
  switches in `Test_Complete.sv`, and `run_gls.sh` written. First compile of
  the 19b netlist failed on the PDK library itself: `sky130_fd_sc_hd__lpflow_bleeder_1`
  references `VPWR` in a specify block outside its `USE_POWER_PINS` guard
  (`sky130_fd_sc_hd.v:72132`). Netlist does not use the cell. Step 0 is the
  fix. The RTL regression is unaffected by the testbench edits (both
  switches are `ifdef`-guarded and default to the old code).
- 2026-09-07 01:50 - post-synth run 1 (`logs/xrun_gls_postsynth.run1_assocrace.log`,
  90 s wall): every test printed PASSED but the per-assoc verdict said
  `Associativity 4 TestN FAILED data errors 0` with all-zero statistics, and
  `GEN_ASSOC_SET[0]` (the ASSOC=1 RTL DUT) reported 72,272 refills while the
  gate DUT saw nothing. ROOT CAUSE: a pre-existing testbench race, not the
  netlist. `Test_Complete_runner.svh` had two time-0 initial blocks: the main
  loop set `active_assoc_idx = a` (blocking) and the reset block then landed
  `active_assoc_idx <= ASSOC_IDX_1` (nonblocking) on top of it. Any run with
  `ASSOC != 0` was silently redirected to the ASSOC=1 DUT while the verdict
  slot for the requested associativity stayed at its "not run" default. The
  full sweep (ASSOC=0) starts at index 0, so it never showed. FIX: the two
  nonblocking writes removed (the variables carry declaration initializers).
  Run 2 relaunched 01:59 (tmux `gls_syn19b2`, `logs/gls_syn19b2_sh.log`).
- 2026-09-07 02:02 - post-synth run 2 PASSED (`logs/gls_syn19b2_sh.log`, xrun
  01:59:37-02:02:19, 2 min 42 s wall, +notimingchecks, UNIT_DELAY, 10 ns clock,
  pressure 1.0/1.0). Genus mapped netlist
  `asic/PPA/genus/assoc_4/runs/20260828_151051_e35abcde_ss1v76_d1p5_tb16_sram`
  through `Cache_gls_wrap` at `GEN_ASSOC_SET[2].DUT.g_gate.u`:
  `Associativity 4 PASSED | Test3 miss rate = 33.35% | avg hit read latency =
  4.88 cycles | hit read samples = 68408 | random requests = 100000 | total
  requests = 221500` and the `Congrats all associativity tests passed` banner.
  Plan step (1) is done; (2) post-layout SDF checks-off waits on the VSS-ECO
  re-export. RTL regression (`./verify_all.sh`, tmux `verify_all_0907`) launched
  02:02 to prove the runner race fix and the ifdef switches before commit.
- 2026-09-07 03:14-03:30 - post-layout SDF annotation took three tries; the
  first two are the lesson. (1) The `-sdf_cmd` file was written with bare
  keywords (`COMPILED_SDF_FILE "x"` / `SCOPE y` / `MTM z`): xmelab warned
  FLFMSP/FLFUKW "trying to continue", annotated nothing, and the zero-delay
  netlist (no `UNIT_DELAY` in postlayout mode) sat at time 0 for 17 min with
  no output at all: a combinational zero-delay loop is what "no output" looks
  like. (2) With the file in the real syntax (`KEY = value,` pairs ending in
  `;`) the SDF compiled but the scope `:Test_Complete.GEN_ASSOC_SET[2].DUT.g_gate.u`
  was refused (SDFSNF "scope not found"; the first attempt's scope had also
  missed the `g_gate` generate level). (3) Fix that works: `$sdf_annotate` on
  the netlist instance from inside `Cache_gls_wrap.sv` (`g_gate` block, under
  `GLS_SDF_FILE` / `GLS_SDF_MTM` quoted-string defines that `run_gls.sh` passes
  as `+define+GLS_SDF_FILE="\"path\""`). Result on the 19b post-ECO export:
  "Annotation completed with 0 Errors and 4998 Warnings, No. of Pathdelays =
  803650, Annotated = 99.76% (801692/803650), Tchecks 193128 all disabled"
  (`+notimingchecks`). The warnings are SDFNEP for `(posedge S) Y` mux paths
  the functional models do not declare, plus SDFNDP negative interconnect
  values clamped to 0; both are the normal noise of this PDK's models. The
  logs of the two failed attempts are kept as
  `logs/gls_pl19b_sh.run1_badsdfcmd.log` and `run2_scopenotfound.log`.
  Run 3 is in tmux `gls_pl19b` on the v2-ECO export (its SDF is the first
  with real min::max triplets, e.g. `(0.097::0.226)`; the pre-ECO SDF had
  identical columns).
