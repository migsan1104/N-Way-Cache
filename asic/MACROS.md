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
