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
   num_rw_ports=1, num_r_ports=1, write_size=8, spice_name="hspice",
   analytical_delay=False, corners = SS/1.8V/25C to match the vendored
   lib; check_lvsdrc=False for timing-only calibration).
5. Run:
       source /apps/settings         # brings hspice onto PATH
       export PDK_ROOT / OPENRAM_HOME / OPENRAM_TECH as above
       cd asic/openram
       python3 $HOME/.local/lib/python3.9/site-packages/openram/sram_compiler.py calib_32x256.py
   HSPICE characterization is the long phase (hours-scale). Output
   lands in `calib_out/` — the .lib is the artifact; diff its arcs
   against `.../sky130_sram_macros/lib/sram_1rw1r_32_256_8_sky130_SS_1p8V_25C.lib`.
6. Phase 1 (gated on the diff): rerun with num_words = 64/128/512/1024
   and corners = ss/1.60V/100C (+ TT_1p8V_25C as a cross-check lib),
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

STATUS 2026-08-21: steps 1-5 done (with the ngspice correction above);
calibration characterization re-launched. Diff verdict pending — this
section to be updated with the result either way.
