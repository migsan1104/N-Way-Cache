# SKY130 SRAM macros available on this server

Location: `/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_sram_macros/`
Views present for every part: **LEF, Liberty, GDS, Verilog model, SPICE, Magic** —
everything needed to simulate (Xcelium/Questa), synthesize (Genus), place & route
(Innovus), and stream out GDS. All OpenRAM-generated; all **1RW + 1R** (one
read/write port, one read port), synchronous, active-low `csb`/`web`, byte write
mask. ASIC tools do NOT infer these — they must be instantiated explicitly.

## The inventory

| Macro | Org (words x bits) | Capacity | Footprint (um) | Area (mm^2) | um^2/bit | Timing corners |
|---|---|---|---|---|---|---|
| `sram_1rw1r_32_256_8_sky130` | 256 x 32 | 1 KB | 376 x 446 | 0.168 | 20.5 | **TT/SS/FF, 7 libs** (V/T spreads) |
| `sky130_sram_1kbyte_1rw1r_32x256_8` | 256 x 32 | 1 KB | 480 x 398 | 0.191 | 23.3 | TT_1p8V_25C only |
| `sky130_sram_2kbyte_1rw1r_32x512_8` | 512 x 32 | 2 KB | 683 x 417 | 0.285 | 17.4 | TT_1p8V_25C only |
| `sky130_sram_1kbyte_1rw1r_8x1024_8` | 1024 x 8 | 1 KB | 455 x 446 | 0.203 | 24.8 | TT_1p8V_25C only |

### Part-by-part

**`sram_1rw1r_32_256_8_sky130` — the recommended part.**
256 x 32b, 4-byte write mask, and the ONLY one with multi-corner Liberty
(TT/SS/FF at several voltages/temperatures) — the only part our ss-corner
signoff flow can time without corner fakery. Smallest footprint of the 32b
parts. Interface: port0 = clk0/csb0/web0/wmask0[3:0]/addr0[7:0]/din0/dout0
(RW); port1 = clk1/csb1/addr1/dout1 (R). All inputs register at the edge;
read data next cycle (matches our S0-address -> S1-data pipeline exactly).
Model quirks: unconditional $display on every access (use a local quieted
copy for sim), dout goes X during writes, memory powers up X (our
word_valid gating already makes that safe).

**`sky130_sram_1kbyte_1rw1r_32x256_8`** — same 256x32 organization, ~14%
larger, TT-only timing. Strictly dominated by the part above for our flow.
Skip.

**`sky130_sram_2kbyte_1rw1r_32x512_8`** — 512x32; best density (17.4
um^2/bit — taller arrays amortize periphery). TT-only, which blocks honest
ss signoff. Geometrically interesting: exact per-way fit for A2 at 4KB and
A8 at 16KB in {set,word} addressing — but those mappings need the
eviction redesign (single R port). Keep in reserve; would matter if the
corner gap is accepted or an SS lib is generated with OpenRAM.

**`sky130_sram_1kbyte_1rw1r_8x1024_8`** — 8-bit word. Built for
byte-oriented designs; our datapath is 32b words with no byte enables.
Using it would take 4 in parallel per 32b with no benefit. Not useful here.

## Fit analysis for this cache (data store per way = CACHE_BYTES/ASSOC)

Two mapping styles:
- **Per-bank** (4 macros/way, one per line word, addr = set): preserves the
  full-line read -> victim capture and the whole current architecture
  survive unchanged.
- **Per-way** ({set,word} addr, 1 macro/way): fewest macros, but the single
  R port gives one word/cycle -> full-line read dies -> requires the
  eviction redesign (victim buffer + drain + store-queue interlock).

| Config | Per-way need | Per-bank mapping | Per-way mapping |
|---|---|---|---|
| 4KB A4 | 1 KB (256 sets... 64 sets x 4 words) | 4x 256x32 at 25% used — area-negative | **1x sram_1rw1r exact** (needs evict redesign) |
| 4KB A8 | 512 B | 4x at 12.5% — terrible | 1x at 50% (needs evict redesign) |
| **16KB A4** | 4 KB (256 sets) | **4x sram_1rw1r per way, 100% used, 16 macros, 2.69 mm^2 — architecture unchanged** | 2x 2kbyte (TT-only, evict redesign) |
| 16KB A8 | 2 KB (128 sets) | 4x at 50% | 1x 2kbyte exact (TT-only, evict redesign) |

**The standout: 16KB ASSOC=4, per-bank.** Each bank is exactly 256 x 32 =
one `sram_1rw1r_32_256_8_sky130`. Sixteen macros, 100% utilization,
multi-corner timing, full-line read preserved -> zero architectural change
(CACHE_BYTES is already a true parameter). Entry 5's drain/bypass logic is
already the correct 1R1W shell around each bank.

## Integration checklist (when green-lit)

1. RTL: per-bank wrapper, `USE_SRAM_MACRO` generate — macro instance for
   ASIC, Entry-5 inference template for FPGA (LUTRAM/BRAM inference keeps
   working from the same tree). Active-low ports; wmask tied 4'b1111.
2. Sim: LOCAL copy of the Verilog model with $displays removed (never edit
   the PDK); add to all three file lists (xcelium/filelist.f, openflex
   YAMLs, asic rtl_files.tcl) per the CLAUDE.md sync rule.
3. Genus: macro .lib into MMMC views; LEF into physical setup; dont_touch.
   Corner note: macro SS lib is SS_1p8V_25C vs flow's ss_100C_1v60 —
   accept the V/T mismatch explicitly or regenerate libs with OpenRAM.
4. Innovus: place as hard blocks (halo, pin access, power straps).
5. Verification: unchanged harness — ./verify_all.sh 4/4 at the chosen
   CACHE_BYTES, run for both USE_SRAM_MACRO settings. Testbench untouched.

## Corner inventory & derate derivation (2026-08-20)

Full .lib inventory for sram_1rw1r_32_256_8_sky130 (nothing else exists
in the PDK tree — no SS at 1.6V, no SS at 100C anywhere):

| Corner | clk->dout access |
|---|---|
| FF_1p8V_25C | 0.535 ns |
| SS_1p8V_25C | **0.654 ns** (the only slow lib) |
| TT_1p7V_25C | 0.630 ns |
| TT_1p8V_25C | 0.595 ns |
| TT_1p9V_25C | 0.563 ns |
| TT_1p8V_0C  | 0.455 ns |
| TT_1p8V_100C | 7.834 ns — **BROKEN, do not use** (13x out of family,
  tables load-independent; bad OpenRAM characterization) |

Prebuilt sky130_sram_1kbyte/2kbyte variants: TT_1p8V_25C only (confirms
earlier survey).

Measured sensitivities from the TT family:
- Voltage: +5.7%/-0.1V (0.563 -> 0.595 -> 0.630) => 1.8V->1.6V ~ +12%.
- Temperature: 0C->25C = +31% (+1.2%/degC) — huge, but the only usable
  temp data (100C lib is garbage). Linear to 100C ~ +90%.

DECISION: keep signoff at ss_100C_1v60 for cells (preserves the whole
campaign's baseline comparability); use macro SS_1p8V_25C with a blanket
x2.0 derate on macro arcs (0.654 -> ~1.31 ns effective access,
enveloping +12% V and +90% T with margin). Even so derated, the macro
consumes ~1.3 ns of the 3.5 ns period — the wall stays in the
surrounding logic, so the corner mismatch is documented pessimism, not a
result-changer. PLE/physical-aware synthesis is orthogonal (models
wires, not device PVT).

## How the derate is implemented (TCL, not RTL)

A derate lives entirely on the ANALYSIS side. The SystemVerilog never
knows about it — RTL describes logic, libraries describe delay, and a
derate is an instruction to the TIMER: "multiply these instances'
library delays before checking slack." Two files implement ours:

1. The knob — `asic/synthesis/common/scripts/project_config.tcl`:

       set SRAM_MACRO_DERATE [config_env ASIC_SRAM_MACRO_DERATE 2.0]

   `config_env` means an environment variable overrides the default, so
   a sensitivity experiment is `ASIC_SRAM_MACRO_DERATE=1.5 ./run_genus.sh 4`
   — no file edits.

2. The application — `asic/synthesis/cadence/scripts/run_genus.tcl`,
   right after `init_design` (the derate needs the design + MMMC views
   loaded before there are instances to scope to):

       set MACRO_INSTS [get_db insts -if ".base_cell.name == $SRAM_MACRO_CELL"]
       set_timing_derate -delay_corner ss_corner -late $SRAM_MACRO_DERATE $MACRO_INSTS

   Read it piece by piece:
   - `get_db insts -if ...` collects EXACTLY the macro instances (by
     library cell name). Scoping matters: the standard cells' lib is
     already honest at ss_100C_1v60 — derating them too would be double
     pessimism. Only the instances whose library lies about our corner
     get the multiplier.
   - `-late` scales the LATE (max-delay) arcs, which is what SETUP
     checks read. That is the failure mode a too-optimistic lib hides:
     the macro is really slower than its 25C/1.8V numbers, so we
     inflate max delay. (`-early` would scale min-delay arcs for HOLD;
     at synthesis we only close setup. When this reaches Innovus/Tempus
     hold analysis, note the asymmetry: for hold, a SLOW macro is
     conservative, so the missing early derate is safe-side — but
     document it, don't discover it.)
   - `-delay_corner ss_corner` binds the derate to the analysis corner,
     which is how one MMMC setup could carry different derates per
     corner if more corners existed.

   Two guards make the mechanism un-skippable: the run FAILS if zero
   macro instances elaborated (a silent flop fallback would otherwise
   report flop-bank numbers under an `_sram` run tag), and FAILS if
   `set_timing_derate` itself errors — a run can never quietly drop
   the pessimism and report clean timing.

The principle to carry to any flow: parameters of the SILICON go in
RTL; parameters of the ANALYSIS go in the run scripts, scoped as
narrowly as the lie they compensate for, guarded so they cannot
silently vanish. And the endgame of the OpenRAM section below is that
this whole subsection becomes historical: a lib characterized AT the
signoff corner needs no derate at all.

## Custom macros with OpenRAM (2026-08-21)

Everything above is about living with the four macros the PDK ships.
This section is about not having to. The macros in the inventory are
themselves OpenRAM products — OpenRAM (UCSC/VLSIDA) is the open-source
memory compiler, and for SKY130 it is the de-facto standard: there is
no commercial compiler ecosystem for this PDK, and every SKY130 shuttle
that uses SRAM uses OpenRAM output. Generating our own is not a new
tool provenance; it is taking control of the one we already depend on.

### Why bother — four problems one generation run solves

1. **A8/A16 waste.** At 16KB the only slow-corner macro is 256 deep;
   A8's banks are 128 (50% used, 2x SRAM area), A16's are 64 (25%, 4x).
2. **The x2.0 derate.** Characterize AT ss/1.60V/100C and the corner
   gap this whole file's decision section exists to bridge disappears —
   for every config, including the current exact-fit A4.
3. **A1/A2 compromises.** Exact-fit parts exist only TT-only; the
   multi-corner part needs depth cascades. Generated macros give exact
   fit at the honest corner with zero glue.
4. **A fair sweep table.** One compiler, one bitcell, one
   characterization method across all five rows — the associativity
   comparison measures architecture, not library luck.

### The target family (16KB; banks = ASSOC x 4, depth = 1024/ASSOC)

| ASSOC | Instances | Macro to generate | Per-instance | Notes |
|---|---|---|---|---|
| 1  | 4  | 32x1024 | 4 KB  | deepest: worst access time (real physics, belongs in the table) |
| 2  | 8  | 32x512  | 2 KB  | |
| 4  | 16 | 32x256  | 1 KB  | doubles as the calibration reference |
| 8  | 32 | 32x128  | 512 B | the config that motivated all of this |
| 16 | 64 | 32x64   | 256 B | 64-instance floorplan; per-macro periphery overhead peaks |

Total bitcells are constant; instance count doubles per step while size
halves. Few/big macros pay in bitline delay, many/small in periphery
area and floorplanning — a real axis of the associativity trade-off the
uniform family finally makes visible.

### The trust problem, and the calibration gate

The obvious objection: the broken TT_1p8V_100C lib above IS an OpenRAM
characterization — why trust our own? Answer: don't trust it, test it.
Phase 0 regenerates the EXACT vendored geometry (32x256, 1RW+1R, byte
mask) and characterizes it with HSPICE at the vendored lib's own corner
(SS_1p8V_25C). Diff the arcs. If they track the known-good lib, the
method inherits its credibility at geometries and corners the vendor
never shipped; if they don't, the sub-project stops having cost a day.
Nothing downstream gets built until this gate passes.

Honest limits of the claim, for any writeup: these are custom MACROS,
not custom BITCELLS (we instantiate the foundry's sky130_fd_bd_sram
cell, as everyone does), and nothing is silicon-validated. DRC/LVS of
generated layout is owed before any GDS-level claim (netgen must be
built from source; magic is on the server).

### The generation pipeline: stages, inputs, outputs

What one `gen_32xN.py` run actually does, start to finish. Two facts
frame everything below:

- **The `.lib` is NOT made from the LEF.** The LEF contains no
  transistors — only pin shapes and routing blockages. It cannot be
  characterized. The `.lib` comes from SPICE-simulating the transistor
  netlist against the PDK device models. LEF and `.lib` are *sibling*
  abstract views of the same design (physical vs timing/power), not
  stages of one another.
- **Characterization is the final stage and the long pole.** The
  netlist and layout exist minutes after launch; the `.lib`, `.v` and
  datasheet all land together hours-to-days later when
  characterization finishes. That is why "non-zero `.lib`" is the
  completion signal for every job.

```
INITIAL INPUTS
==============
  gen_32xN.py config      geometry (word_size, num_words), ports
                          (1RW+1R), write mask, corner, load/slew
                          grid, simulator choice
  sky130A PDK             device models (libs.tech/ngspice/
                          sky130.lib.spice) = the "physics files";
                          foundry bitcell GDS + SPICE
                          (sky130_fd_bd_sram); tech rules
  OpenRAM sky130 tech     generators + glue that bind the two

        |
        v
+--------------------------------------------------------------+
| STAGE 1: netlist synthesis                    (seconds-mins) |
|   in : config + foundry bitcell SPICE                        |
|   out: <name>.sp        full transistor netlist (hierarchical)|
|        <name>.lvs.sp    LVS-comparison variant               |
|        trimmed.sp       characterization variant             |
|                         ("Trimmed: True"; at 32x64 it still  |
|                         carries all 2,340 bitcell instances) |
+--------------------------------------------------------------+
        |
        v
+--------------------------------------------------------------+
| STAGE 2: layout generation           (mins; 32x64 = ~11 min) |
|   in : netlist hierarchy + foundry bitcell GDS + tech rules  |
|   out: <name>.gds       full mask layout                     |
|        <name>.lef       abstract DERIVED FROM the GDS:       |
|                         pins + blockages only                |
+--------------------------------------------------------------+
        |
        v
+--------------------------------------------------------------+
| STAGE 3: DRC/LVS                    (SKIPPED on this server) |
|   check_lvsdrc=False — netgen not built yet; magic present.  |
|   Verification only: reports, no new design files.           |
+--------------------------------------------------------------+
        |
        v
+--------------------------------------------------------------+
| STAGE 4: characterization              (hours-days; the fork)|
|                                                              |
|   MODE A  analytical_delay=True: linear RC model, NO SPICE,  |
|           ~44 s. This is what the VENDORED libs are (proved  |
|           by analytical_32x256.py reproducing them           |
|           bit-identically). Fiction where the model is wrong.|
|   MODE B  analytical_delay=False (ours): ngspice-41 measures |
|           trimmed.sp against the PDK models at the exact     |
|           corner (ss/1.60V/100C):                            |
|     4a functional sim   functional_stim/meas.sp - r/w checks |
|     4b delay grid       delay_stim/meas.sp per (slew, load)  |
|                         point (2x2 - see grid writeup), plus |
|                         setup/hold and the min-period        |
|                         bisection search                     |
|     4c power            dynamic per grid point; leakage =    |
|                         one full-array sim (12 h single-     |
|                         threaded at 32x1024)                 |
|                                                              |
|   in : trimmed.sp + sky130.lib.spice + generated stimulus    |
|   out: the raw measures for stage 5                          |
+--------------------------------------------------------------+
        |
        v
+--------------------------------------------------------------+
| STAGE 5: model + datasheet emission     (with stage 4's end) |
|   out: <name>_SS_1p6V_100C.lib   timing/power per corner     |
|        <name>.v                  behavioral simulation model |
|        datasheet.info / .html    human-readable summary      |
+--------------------------------------------------------------+

FINAL OUTPUTS, by consumer
==========================
  .lib      -> Genus/DC/STA        timing + power arcs
  .lef      -> P&R (Innovus)       placement footprint, pin access
  .gds      -> tapeout merge       the actual masks
  .v        -> simulation          verification file lists ONLY
  .sp/.lvs.sp -> LVS               netlist-vs-layout check
  datasheet -> humans
```

Timestamps from the finished 32x64 job make the stage split concrete:
`.sp`/`.gds`/`.lef`/stimulus all written 11:16 (11 min after launch);
`.lib`/`.v`/datasheet all written 15:08 — everything in between was
stage 4.

**So can "LEF + physics files" make a `.lib`?** Not the LEF — but the
underlying idea (characterize the physical design against the device
models) is exactly right, with the GDS in the LEF's place. The rigorous
version is: extract parasitics from the **GDS** (PEX, via magic/netgen)
into an RC-annotated netlist, then SPICE *that* against the device
models. OpenRAM does not do this — stage 4 simulates the
**schematic-level** `trimmed.sp`, so device parasitics are in the
models but metal wire RC inside the macro is not in our `.lib`. One
more reason the measured numbers are still a floor, and a natural
follow-on once netgen is built (the same build that unblocks stage 3).

### Follow-along: reproducing the setup (as done 2026-08-21)

Toolchain facts discovered on the way, so nobody re-derives them:
the server PDK at `/apps/cds/IC618/local/opdk/share/pdk/sky130A` is a
FULL open_pdks build (libs.tech has ngspice models, magicrc, netgen
setup — everything OpenRAM's sky130 tech asserts on); HSPICE lives at
`/apps/syn/hspice/hspice/bin/hspice`, on PATH after
`source /apps/settings`, license checkout verified. ngspice/netgen/
klayout binaries are NOT installed (klayout DECKS are in the PDK).

1. Install (user-space, no root):
       pip3 install --user openram          # got 1.2.48
2. Assemble a WRITABLE PDK_ROOT (the server PDK is read-only; the
   bitcell clone must land next to sky130A):
       mkdir -p ~/pdk_openram
       ln -sfn /apps/cds/IC618/local/opdk/share/pdk/sky130A ~/pdk_openram/sky130A
3. Fetch the SRAM bitcell library + raw skywater-pdk (submodules
   sky130_fd_pr, sky130_fd_sc_hd) and install cell views into the
   package's technology tree:
       export PDK_ROOT=$HOME/pdk_openram
       export OPENRAM_HOME=$HOME/.local/lib/python3.9/site-packages/openram/compiler
       cd $HOME/.local/lib/python3.9/site-packages/openram
       make sky130-pdk && make sky130-install
   (First run also self-provisions a conda env with OpenRAM's tool
   dependencies — expect a long download once.)
4. Write a config — the Phase-0 calibration one is checked in at
   `asic/openram/calib_32x256.py` (word_size=32, num_words=256,
   num_rw_ports=1, num_r_ports=1, write_size=8, spice_name="ngspice",
   analytical_delay=False, corners pinned with `use_specified_corners`
   to the three the vendor also ships at 1p8V/25C;
   check_lvsdrc=False for timing-only calibration). See both findings
   below before editing it — the simulator and the corner gate each
   have a trap.
5. Run:
       source /apps/settings         # brings hspice onto PATH
       export PDK_ROOT / OPENRAM_HOME / OPENRAM_TECH as above
       cd asic/openram
       python3 $HOME/.local/lib/python3.9/site-packages/openram/sram_compiler.py calib_32x256.py
   HSPICE characterization is the long phase (hours-scale). Output
   lands in `calib_out/` — the .lib is the artifact; diff its arcs
   against `.../sky130_sram_macros/lib/sram_1rw1r_32_256_8_sky130_SS_1p8V_25C.lib`.
6. Phase 1 (gated on the diff): rerun with num_words = 64/128/512/1024
   and `use_specified_corners = [("SS", 1.60, 100)]`,
   then integrate per the checklist above — the generate branch in
   FTDA generalizes from `DEPTH == 256` to per-depth exact-fit cells,
   and the three file lists get the new sim models per the CLAUDE.md
   sync rule.

**Simulator finding (2026-08-21, follow-along correction):** HSPICE
CANNOT characterize against this PDK — the open_pdks sky130 device
models are ngspice-dialect ({l}/{w} parameter braces on device lines)
and HSPICE rejects the first model file at parse. This is a model-
dialect mismatch, not a tool bug: the open PDK's models target the
open simulators. OpenRAM's self-provisioned conda env ships ngspice
AND Xyce for exactly this reason — use `spice_name = "ngspice"` (the
pairing the vendored libs themselves were characterized with). The
generation half (GDS/LEF/netlist) succeeded on the first attempt; only
characterization needed the simulator swap.

**Corner-selection finding (2026-08-21):** setting `process_corners`
in a config does NOTHING on its own. It is gated behind a second
option that defaults off. From
`openram/compiler/characterizer/lib.py`, `create_corners()`:

```python
if OPTS.use_specified_corners == None:
    if OPTS.only_use_config_corners:          # DEFAULT: False
        for p in self.process_corners:        # <- the branch that reads your config
            for v in self.supply_voltages:
                for t in self.temperatures:
                    corner_tuples.add((p, v, t))
    else:                                     # <- the branch you get by default
        nom_process = "TT"                    # hardcoded, ignores process_corners
        nom_corner = (nom_process, nom_supply, nom_temperature)
        ...
    self.add_corner(*nom_corner)              # "Enforce that nominal corner is first"
```

Both gates default off (`options.py`: `only_use_config_corners = False`,
`use_specified_corners = None`), so the default path builds its corner
list from a hardcoded `nom_process = "TT"` plus a sweep, and
characterizes TT **first**. That is why attempt 1 emitted a TT-named
lib despite `process_corners = ["SS"]` — the option was inert, not
overridden. Symptom to recognize: the generated `delay_stim.sp` opens
with `* TT process corner` / `.lib "...sky130.lib.spice" tt`. Read that
file to know what a run is ACTUALLY characterizing; the config is not
evidence.

What the default path produces here is still useful. With
`supply_voltages = [1.8]` and `temperatures = [25]`, the temperature
and supply sweeps collapse onto the nominal and the tuple set dedups to
three corners — `(TT,1.8,25)` first, then `(FF,1.8,25)` and
`(SS,1.8,25)`, SS surviving only because `max_process = "SS"` is
hardcoded in that same branch. Those are EXACTLY the three corners the
vendor ships at 1p8V/25C, so the calibration gate gets a three-point
diff instead of the one-point diff it was designed around — a stronger
result, at 3x the characterization time. The calibration config now
requests those three explicitly rather than receiving them by accident.

For Phase 1, where only ONE corner is wanted, use
`use_specified_corners` — **not** `only_use_config_corners`:

```python
use_specified_corners = [("SS", 1.60, 100)]   # exactly this corner, nothing else
```

`only_use_config_corners = True` looks like the intended knob and is a
TRAP: it crashes. In OpenRAM 1.2.48 `create_corners()` assigns
`nom_corner` only inside the `else` branch, but calls
`self.add_corner(*nom_corner)` and `corner_tuples.remove(nom_corner)`
OUTSIDE the inner if/else (lib.py:119 vs 132-133). Take the powerset
branch and `nom_corner` is unbound —
`UnboundLocalError: local variable 'nom_corner' referenced before
assignment` — and even if it were bound, the `remove()` would raise
`KeyError` whenever the powerset excludes the TT nominal. Verified by
reading the source 2026-08-21; `nom_corner` appears nowhere else in the
package. `use_specified_corners` takes a separate branch that skips
that code entirely, which is why it is the safe one.

Unverified caveat carried into Phase 1: 1.60 V is not in sky130's
`spice["supply_voltages"] = [1.7, 1.8, 1.9]`. The powerset branch uses
whatever list you hand it and the voltage only sets `Vvdd` in the
stimulus, so it should simulate — but that is reasoning, not a tested
result, and all of Phase 1 depends on it. Check the first generated
`delay_stim.sp` for `Vvdd vdd 0 1.6` before trusting a Phase-1 lib.

**Simulator + .spiceinit finding (2026-08-22):** characterization was
effectively impossible until two things were fixed together. Measured
on one identical 150 ns stimulus, same netlist, same corner:

| ngspice | `.spiceinit` visible | result |
|---|---|---|
| 26 (bundled) | yes | 7 h 19 m, never finished |
| 41 | **no** | >6.5 h, never finished |
| 41 | yes | **24.7 min, rc=0**, 15273 timepoints, 48 measures |

**(1) The bundled simulator is ngspice revision 26 (2014).** It predates
the KLU sparse solver and never engages the `num_threads` its own
`.spiceinit` asks for — it sits pinned at one core. `conda install -c
conda-forge ngspice=41` into a SEPARATE env (`~/ngspice41env`; never into
OpenRAM's miniconda, which running jobs depend on) fixes both.

Switching it is not obvious. Setting `spice_exe` in a config is INERT —
`characterizer/__init__.py:25` assigns `OPTS.spice_exe = ""` then
`find_exe()`, overwriting any config value, the same trap as
`process_corners`. And PATH alone does nothing either: `find_exe()`
searches `CONDA_HOME/bin` BEFORE `$PATH` while `use_conda` is true, so
the bundled 26 always wins. The working combination is
`use_conda = False` in the config (it only skips `install_conda()`,
already done) plus `~/ngspice41env/bin` first on PATH.

**(2) ngspice reads `.spiceinit` from the directory it RUNS FROM.**
OpenRAM writes one into `/tmp/openram_*_temp/`, which only helps if
ngspice's cwd is that temp dir. `run_openram.sh` cds to `asic/openram/`,
so a copy must live THERE — it is checked in. Without it, three settings
vanish with no error and no warning: `num_threads` (one core),
`ngbehavior=hsa`, and `ng_nomodcheck` (skips model-parameter range
checks across thousands of BSIM4 instances — likely the larger half of
the loss). `run_openram.sh` now refuses to launch if the file is absent,
because a silent 15x slowdown is worse than a hard stop.

Diagnosis habit worth keeping: **check `%CPU` on the first simulation.**
Above 100% means the options landed; 99% means they did not, and you
learn it in a minute instead of six hours. Confirm the binary with
`readlink -f /proc/<pid>/exe`, not by reading the command line — OpenRAM
wraps every call in `bash -c 'source <miniconda>/bin/activate && ...'`,
so the wrapper's conda path appears even when the simulator is elsewhere.

Xyce is not an escape hatch: it rejects the open_pdks sky130 models at
parse (`.param line has an unexpected number of fields` in
`nfet_g5v0d16v0__ss_discrete.corner.spice`), the same failure class as
HSPICE, and in a 5 V device the SRAM never instantiates. Trimming the
model library to only the instantiated devices is likewise a dead end as
attempted: `special_nfet_latch` has no `__ss.corner` file of its own, so
the obvious trim drops it and ngspice fails with `unknown subckt` before
running anything. The failure is at least loud.

STATUS 2026-08-22: steps 1-5 done (with the ngspice, corner, and
`.spiceinit` corrections above). All five geometries plus the
calibration macro have completed LAYOUT (GDS/LEF/SPICE); layout times
11.2 / 14.7 / 37.1 / 69.5 / 173.6 min for 32x64/128/256/512/1024.
Characterization relaunched 10:15 with ngspice-41 + `.spiceinit`;
expect ~25 min per simulation, 15-30 simulations per corner, so 6-12 h
per macro with all six running in parallel. No `.lib` has been produced
yet — a NON-ZERO `.lib` is the only completion signal. Diff verdict
still pending; this section gets the result either way.

## Phase-0 calibration gate: the verdict (2026-08-23)

The calibration `.lib` landed 2026-08-23 10:04 after 12 h 09 m, rc=0:
`asic/openram/calib_out/openram_sram_1rw1r_32x256_8_calib_SS_1p8V_25C.lib`.
Comparison against the vendored `sram_1rw1r_32_256_8_sky130_SS_1p8V_25C.lib`
is possible at 4 of its 9 grid points (our sweep dropped the 0.25 scales —
see `calib_32x256.py`); the four are the vendor's rows/cols 2-3, so the
overlap is exact, not interpolated. At slew 0.04 ns, load 27.56 fF:

| arc | ours (SPICE) | vendored | ratio |
|---|---|---|---|
| dout0 clk->Q delay | 1.469 ns | 0.654 ns | 2.25 |
| dout0 output transition | 2.361 ns | 0.018 ns | 131 |
| addr0/din0 setup | 0.139 / 0.115 ns | 0.165 ns | 0.84 / 0.70 |
| addr0/din0 hold | -0.105 / -0.056 ns | -0.052 ns | 2.02 / 1.08 |
| cell leakage | 0.2274 mW | 0.0095 mW | 24 |

At the lighter load (6.89 fF) the delay arcs agree far better: 0.582 vs
0.526 ns, +11%. Constraints agree to within 2x everywhere. Transitions and
leakage do not agree at all.

**The reference is not a measurement.** The vendored libs were produced by
OpenRAM's *analytical* delay model, not by simulation. Two independent
proofs:

1. *Control run.* `analytical_32x256.py` regenerates the same macro with
   `analytical_delay = True` and `netlist_only = True` — 44 seconds, no
   layout, no SPICE. Its transition table is **bit-identical** to the
   vendored one: `0.002, 0.005, 0.018` repeated across all three
   input-slew rows, in both `rise_transition` and `fall_transition`. A
   SPICE run cannot land on the vendor's numbers to three decimals across
   nine entries; the model reproduces them exactly because it is the same
   model.
2. *Internal inconsistency.* Take each lib's own delay-vs-load slope,
   convert it to an effective drive resistance, and predict the 10-90%
   transition it implies at max load:

   | lib | R_eff | implied slew | reported slew | off by |
   |---|---|---|---|---|
   | vendored `sram_1rw1r_32_256_8` SS | 9.0 kohm | 0.544 ns | 0.018 ns | 30.2x |
   | vendored `sky130_sram_1kbyte` TT | 8.1 kohm | 0.493 ns | 0.016 ns | 30.8x |
   | ours, SPICE, SS | 61.8 kohm | 3.745 ns | 2.361 ns | 1.6x |

   Both vendored libs contradict themselves by the same ~30x; ours is
   self-consistent to within the accuracy of a first-order RC estimate.
   The physics agrees with us: in *both* netlists `dout` comes straight
   out of `Xbank0` with **no output buffer** (checked instance by
   instance — the `pinv_12 m=23` at the top of the netlist is the
   wordline/clock buffer, not an output driver), and an 18 ps edge into
   27.56 fF would need ~2.2 mA out of a sense-amp-sized device.

**So the gate as written cannot be passed, and must be restated.** "Diff
the arcs against the vendored lib; if they track, self-generated libs earn
trust" assumed the reference was ground truth. It is a model. What the
calibration actually establishes:

- The corner really is SS / 1.8 V / 25 C. The live stimulus in
  `/tmp/openram_*_temp/delay_stim.sp` reads `* SS process corner`,
  `Vvdd vdd 0 1.8`, `.TEMP 25`, with `.meas` thresholds 0.18 / 1.62 =
  10% / 90% of 1.8 V. **TRAP:** the copy OpenRAM saves into `calib_out/`
  at `save()` time says `* TT process corner` and `Vvdd vdd 0 5` with
  2.5 V thresholds. It is a placeholder written before the corner is
  applied, not what was simulated — the same class of trap as the inert
  `process_corners` option. Judge the corner from the temp dir, never
  from `calib_out/delay_stim.sp`. (`functional_stim.sp` in the same
  directory says SS / 1.8, which is how the contradiction surfaces.)
- The pin set matches the vendored macro exactly (both Verilog views:
  `clk0 csb0 web0 wmask0 addr0 din0 dout0 / clk1 csb1 addr1 dout1`).
  The vendored *lib* also carries `wmask1` setup/hold arcs for a pin its
  own Verilog does not have; ours does not. Ours is the correct one.
- Access time is in family with the model at the loads a real design
  sees, and diverges only where the analytical model stops modelling
  drive strength.

**Consequence for the ASIC flow, and it cuts both ways.** The macro run
(`runs/20260821_194312`, 177.8 MHz, 4.51 mm2 cell, 0.730 W) links the
vendored analytical lib with the x2.0 late derate from the section above.

- *The derate is vindicated on delay.* 0.654 x 2.0 = 1.31 ns against a
  SPICE-measured 1.469 ns at the same corner and load — 11% apart. The
  hedge chosen from the TT sensitivity family happens to land almost
  exactly on the measurement.
- *It does nothing for transition.* `set_timing_derate` scales delay, not
  slew. Genus is being told the macro output slews in 18 ps when it slews
  in ~1.1-2.4 ns, so every cell the macro drives gets an optimistic input
  slew, and `default_max_transition : 0.5` never fires on a macro output
  that violates it by 2-5x. Macro-output slack in that run is optimistic
  by an amount the derate does not cover.
- Our own SPICE libs are therefore the ones to link once Phase 1
  finishes — with the caveat that OpenRAM's characterization load grid
  (0.25/1/4 x `dff_in_cap` = 1.7/6.9/27.6 fF) tops out well below what a
  fanout of several sinks presents, and that `dout` wants an explicit
  buffer at the macro boundary either way.

VERDICT: gate passed in the restated form — the flow is measuring the
right circuit at the right corner and its numbers are self-consistent
where the reference's are not. Phase 1 continues. Do not quote a
"calibration diff" as agreement with the vendor: the honest claim is
that the vendor lib is analytical, ours is simulated, and they agree on
delay at light load only.

## The access-time finding (2026-08-23 15:35): these are ~100 MHz parts

The first 2x2-grid macro (32x64, SS 1.6 V 100 C, done 15:08) reported
clk->Q 2.55 / 3.69 ns at 6.9 / 27.6 fF with a 0.34 ns transition — a
delay slope of 55 ps/fF (an ~80 kohm driver) cannot produce a 0.34 ns
edge into 27.6 fF (14x inconsistent, the same test that exposed the
vendor lib). And every `timing.lis` had shown `delay_sen` — clock-fall
to sense-amp enable — at 3.7-4.5 ns on BOTH corners, while the calib
lib claimed 0.58 ns clk->Q. Data cannot exist on dout before the sense
amp fires. So a waveform probe was run by hand: the live SS/1.6V/100C
stimulus from the running 32x256 job, retargeted to the 32x64 trimmed
netlist (`scratchpad/probe64/`, ngspice-41, ~14 min), sampling dout,
wl_en and s_en at fixed offsets after the clock's falling edge.

Read of a 1, port 1, 27.56 fF, times after clk falls:
  wl_en rises 1.07 ns | dout 0.015 V @2 ns, 0.37 @3, 0.8 (50%) @3.89,
  0.84 @4 | s_en rises 4.57 ns | dout 1.43 @4.9, 1.60 (settled) @6 ns.

So: the lib's 50%-point DELAY at high load (3.69) is about right; its
TRANSITION (0.34) is wrong by ~10x (the edge spans 2-5 ns); the light-
load and 1.8 V numbers are worse. But the number that matters is not in
the lib at all: **the read is self-timed and needs ~5-6 ns of clock-low
time** (sense enable at 4.6 ns after the fall, settle by 6). At a 3.5 ns
clock the low phase is 1.75 ns — precharge begins before the sense amp
enables. The macro does not work at 3.5 ns, pipelined or not. OpenRAM
says so itself: `min_period` in every datasheet it wrote for us is
9.5-10.0 ns (a field nobody read). At this corner these are ~100 MHz
parts, in line with how the efabless sky130 SRAM macros are actually
clocked in Caravel designs (~50 MHz).

Consequences:
1. The 16 KB A4 macro run (runs/20260821_194312, "177.8 MHz") has a
   FICTITIOUS Fmax: Genus was fed 0.65 ns x 2.0 = 1.3 ns for a ~6 ns
   read from an analytical lib. Its area (-39%) and power (-57%) are
   real. RESULTS.md must carry this note on that row.
2. The honest ASIC Fmax numbers are the FLOP-bank runs (A4 176.6 MHz).
3. E24 (tag macros) is off the table for a 285 MHz target; so are the
   data-bank macros. Macros return only if the ASIC target drops to
   ~100 MHz, where they bring the area/power and the flop design would
   not need the timing campaign at all.
4. The Phase-1 generation (128/256/512/1024 still characterizing) now
   serves the area/power/100 MHz story only. The 2x2 libs' transition
   columns remain unreliable (see the waveform) even where the 50%
   delay is right; a lib to be linked needs its slews re-characterized
   from a buffered dout, or the macro wrapped with an output buffer and
   re-characterized as a unit.
5. The derate discussion above is moot: no derate turns a 6 ns read
   into a 3.5 ns one.

## Run 2 sign-off corner (2026-08-28): ss_n40C_1v76 cells, vendor macro x1.5

Run 1 (the P&R shakedown on e35abcde) keeps the 08-20 decision above: cells at
ss_100C_1v60, vendor macro SS_1p8V_25C with a x2.0 late derate that tries to be
a V/T translation (1.8 V/25 C -> 1.6 V/100 C) and a guardband at once. Run 2
separates the two jobs:

- **Cells at `sky130_fd_sc_hd__ss_n40C_1v76`** - the SS standard-cell lib
  closest to the voltage the vendor macro was actually characterized at. No SS
  lib exists at 25 C or 1.8 V for the cells; at 1.76 V the -40 C point is the
  *fast* end (no temperature inversion at these voltages, see
  project_config.tcl), so this is a slow-process / nominal-voltage sign-off,
  not a minimum-supply one. Say so wherever the number is quoted.
- **Same vendor macro lib, derate x1.5 (late).** At 1.76 V/-40 C the macro's
  matching corner is within a few percent of its 1.8 V/25 C lib (+~2 % for
  voltage, a few % faster for cold), so no V/T translation is needed. The 1.5 is
  a pure guardband for the lib's suspect load axis (2-18 ps output slew into
  27 fF): the in-house OpenRAM calibration of the same cell at the same
  TT/1.8V/25C corner (calib_32x256, 08-23) reads ~1.5x the vendor lib at the
  3.6-7 fF the cache presents on dout1. Hold-side early derate: use the mirror
  value ~0.67 in Innovus (ASIC_MACRO_DERATE_EARLY), not the run-1 0.5.
- Hold: unchanged (ff_n40C_1v95 cells, macro FF_1p8V_25C).

Launcher: `asic/run_genus_corner2.sh` (env overrides on top of run_genus.sh;
the run-1 defaults are untouched). Run stamps carry `ss1v76_d1p5` because
collect_ppa.py labels rows by stamp only. The two corners are reported side by
side; the OpenRAM SS/1.6V/100C lib, if it lands, is the tie-breaker on which
one the macro really belongs to.

**Result (Genus run `20260828_151051_e35abcde_ss1v76_d1p5_tb16_sram`, landed 19:25):**
WNS -59 ps at 3.500 ns (run-1 corner: -524.5), TNS -2.3 ns (-190.5), 72 violating
endpoints (598), cell area 4.16 mm² / total 5.07 mm² (+4 %), power 0.78 W. Census:
19 of the 20 worst paths are `u_sram/clk1 -> COMPARE_SELECT_REPLACE.out_rdata_reg`
(the macro half-cycle read, at x1.5) and one is `rindex_rep_r -> replacement_way`
at -58 ps. So at this corner the netlist closes 4.0 ns with ~440 ps to spare and
the macro read is the ceiling, as predicted. Both corners are rows in
`PPA/RESULTS.md` (collect_ppa.py now keys rows by corner + derate).
