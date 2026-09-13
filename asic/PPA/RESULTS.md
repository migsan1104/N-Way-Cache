# ASIC synthesis PPA results

The table below is regenerated from each run's `reports/` by:

```bash
cd asic && ./collect_ppa.py --tool genus                                    # every configuration
cd asic && ./collect_ppa.py --tool genus --cache-kb 16 --corner ss_n40C_1v76 --png ..   # the uniform sweep + README chart
```

**Do not add `--markdown PPA/RESULTS.md` to that command.** It opens this file
with mode `"w"` and writes only the tables, so every note on this page - the
comparability warnings, the current-state section - is destroyed. Regenerate
the table, then paste it in under the prose.

`collect_ppa.py` emits one row per **(associativity, configuration)**, taking
the newest completed run of each. A run is only collectable once its final
`qor.rpt` exists, so a run still in flight never shadows a finished one.
"Configuration" currently means the data-bank realisation - flops or SRAM
macros - because those two builds of the same associativity share one `runs/`
directory. Before 2026-08-22 the collector kept only the newest run per
associativity outright, which meant the 16 KB ASSOC=4 macro run displaced the
flop-bank run that the macros-vs-flops comparison depends on.

**Read the "Cache (KB)" and "Target (ns)" columns before comparing rows.**
The table below is NOT a uniform sweep: it is whatever the newest completed
run of each configuration happens to be, and right now those runs come from
different eras. Only the **two ASSOC=4 rows are at the project's 16KB
capacity target**; the other four are leftover 4KB runs, two of them at a
2.000 ns target rather than 3.500 ns. Rows are comparable to each other only
where capacity, target, and data-bank realisation match - which is why the
two ASSOC=4 rows are the only clean comparison on this page.

Numbers are placement-based estimates (PLE), not post-P&R: treat every slack
as a floor. See `PHYSICAL_DESIGN.md` §4 (synthesis stages) and §8 (wire
modeling).

> **Every row below was synthesised with `set_output_delay 0.700`.** That was
> changed to **0.300** in `synthesis/common/constraints/golden.sdc` on
> 2026-08-22 (derivation in the file). Any run from that date forward gets
> 400 ps of relief on output-bounded paths, so its WNS is **not comparable to
> these rows** wherever a port path is involved. Reg-to-reg paths are
> unaffected and stay comparable. Re-baseline before quoting a delta.


> **2026-08-23 — the SRAM-macro row's Fmax is not real.** A hand-run SPICE
> waveform on an OpenRAM macro at the signoff corner shows the self-timed
> read needs ~5-6 ns of clock-low time (sense enable 4.6 ns after the
> falling edge; OpenRAM's own `min_period` for every macro it built is
> 9.5-10 ns). The vendored lib Genus linked is analytical and claims
> 0.65 ns; the x2.0 derate does not bridge a 0.65 -> 6 ns gap. The
> macro row's **area and power are real; its WNS/Fmax is an artifact.**
> Treat the flop-bank rows as the ASIC frequency numbers. Full writeup:
> `asic/MACROS.md`, "The access-time finding".

## Current state (2026-09-12): the uniform 16 KB sweep

`asic/sweep_corner2.sh` (launched 2026-09-11 18:31, done 00:47) re-ran every associativity at
the **signoff recipe of the P&R netlist**: `ss_n40C_1v76`, 3.500 ns, `TAG_BANK_DEPTH=16`,
fanout limit 32, no cap blanket, replicas free to merge, flop data banks. Runs are
`runs/20260911_183125_e37_nocap_fo32_ss1v76_tb16_flops` under each `assoc_N/`. Together with
the ASSOC=4 macro build that went to P&R this is the first table on this page whose rows are
all comparable to each other; README §4.5 carries the short form and the chart.

| ASSOC | Data banks | WNS (ns) | Fmax (MHz) | Hit latency (ns) | Cell area (um^2) | Cells | Flops | Power (W) | Violating paths | Worst path (start -> end) |
|---:|:---|---:|---:|---:|---:|---:|---:|---:|---:|:---|
| 1 | flops | -0.405 | 256.1 | 16.5 | 6,700,063 | 629,889 | 162,633 | 2.176 | 45,452 | `way0 rindex_rep_r -> way0 rline_raw_r` |
| 2 | flops | -0.242 | 267.2 | 15.7 | 6,447,024 | 538,155 | 164,558 | 2.154 | 43,952 | `way0 rindex_rep_r -> way0 rline_raw_r` |
| 4 | flops | -0.316 | 262.0 | 15.8 | 6,385,941 | 533,093 | 166,569 | 2.146 | 1,332 | `way0 rindex_rep_r -> way2 rline_raw_r` |
| 4 | SRAM macros x1.5 | -0.049 | 281.8 | 14.7 | 4,198,527 | 135,816 | 35,280 | 0.795 | 99 | (see MACROS.md) |
| 8 | flops | -0.224 | 268.6 | 15.4 | 6,669,086 | 579,006 | 169,182 | 2.194 | 6,918 | `way0 rindex_rep_r -> way5 word_valid_raw_r` |
| 16 | flops | -0.128 | 275.6 | 15.0 | 6,584,580 | 546,584 | 173,179 | 2.275 | 935 | `way1 byp_alloc_r -> PLRU next_bits_r` |

- **Fmax is flat in associativity on the ASIC (256-276 MHz, 8 % spread) where the FPGA is
  U-shaped (270-327 MHz, 21 %).** Every flop-bank row except 16-way has the same wall: the S0
  registered set index fanning out to the per-way flop tag/flag array read, a sets:1 mux.
  Doubling the ways halves the sets per way (1024 at 1-way, 64 at 16-way) so the mux shrinks,
  while the way compare/select and PLRU widen by the same factor; the two nearly cancel. At
  16-way the array read is finally cheap enough that the PLRU update becomes the worst path.
- **Area and flop count barely move** (6.4-6.7 mm^2 cells, 163-173k flops): the tag and data
  bits are fixed by the 16 KB capacity; more ways only add tag width and PLRU state. The 1-way
  outlier (630k cells) is decode: 1024 sets of write-enable and read-mux logic per bank.
- **Violating-path count is not a quality metric here**: 1-way and 2-way have the deepest
  arrays, so tens of thousands of read endpoints sit within the same ~400 ps of the target.
- **Macros at ASSOC=4**: -34 % cell area, -74 % cells, -63 % power, +8 % Fmax versus the flop
  build at the same corner. The Fmax gain is small because the tag array stays in flops; see
  "The access-time finding" in `asic/MACROS.md` before quoting the macro row's WNS at all.
- The 2026-08-22 section below is kept as history; its "owed" A1/A2/A8/A16 rows are these.

## Earlier state (2026-08-22)

- **ASSOC=4, 16KB, E9-E19a RTL** is measured both ways, and the macro run is
  the newer of the two:
  - flop banks — `runs/20260821_132313`, 6h18m: WNS -2.163 => **176.6 MHz**,
    7.39 mm^2 cell, 9.81 mm^2 total, 693,356 cells, 166,079 seq, 1.703 W.
  - SRAM macros — `runs/20260821_194312`, 3h14m, 16 macros bound: WNS -2.125
    => **177.8 MHz**, 4.51 mm^2 cell, 5.51 mm^2 total, 194,340 cells,
    34,511 seq, 0.730 W.
  - Macros are worth **-39% cell area, -44% total area, -72% cell count,
    -57% power — and +0.7% Fmax.** They buy area and power, not frequency,
    because the wall is not in the data banks (see below).
- Against the same 16KB flop-bank configuration on Entries 1-8 RTL
  (`runs/20260820_042842`: WNS -2.656, 8.24 mm^2 cell, 1.791 W), the
  optimization campaign is worth **+493 ps (+8.7% Fmax), -10.4% cell area,
  -18.2% total area, -4.9% power**.
- **Why macros did not move Fmax.** In the macro run's own `timing.rpt` the
  worst 20 paths are four cones tied within 2 ps at -2125. The deepest is
  `MSHR_FILE_REFILL_MUX_refill_set_id_reg -> FLAG_TAG_DATA_ARRAY_refill_bank_pending_r`
  at 30 stages / 5266 ps: 774 ps of CLK->Q, ~1720 ps distributing the address
  to four ways, then ~2770 ps of decode. That back half is the Entry-4 refill
  guard reading the **tag** array - which is still flops - and comparing 20
  bits. Macros replaced the *data* banks, so they were never going to touch
  it. The other three cones are `order_head_r -> mem_req_wdata` (Entry 18's
  grant-time victim read) and two `cpu_req_addr -> alloc_wen/cpu_write_wen`
  S0 grant cones.
- A1/A2/A8/A16 at 16KB are still **owed**.

### Cadence Genus

| ASSOC | Data banks | Corner | Cache (KB) | Target (ns) | WNS (ns) | Achievable Fmax (MHz) | Hit latency (ns) | Cell area (um^2) | Total area (um^2) | Cells | Sequential | Macros | Total power (W) | Violating paths |
|---:|:---|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | flops | ss_n40C_1v76 | 16 | 3.500 | -0.405 | 256.1 | 16.5 | 6,700,063 | 10,234,145 | 629,889 | 162,633 | 0 | 2.176 | 45,452 |
| 2 | flops | ss_n40C_1v76 | 16 | 3.500 | -0.242 | 267.2 | 15.7 | 6,447,024 | 10,119,087 | 538,155 | 164,558 | 0 | 2.154 | 43,952 |
| 4 | flops | ss_100C_1v60 | 16 | 3.500 | -1.844 | 187.1 | 22.2 | 4,478,379 | 5,633,973 | 187,334 | 34,919 | 16 | 0.719 | 15,518 |
| 4 | flops | ss_100C_1v60 | 16 | 3.500 | -2.163 | 176.6 | 23.5 | 7,387,209 | 9,814,943 | 693,356 | 166,079 | 0 | 1.703 | 180,675 |
| 4 | flops | ss_n40C_1v76 | 16 | 3.500 | -0.316 | 262.0 | 15.8 | 6,385,941 | 8,838,192 | 533,093 | 166,569 | 0 | 2.146 | 1,332 |
| 4 | SRAM macros | ss_100C_1v60 / macro x1 | 16 | 3.500 | -3.145 | 150.5 | 27.6 | 4,670,962 | 5,391,357 | 144,501 | 34,804 | 16 | 0.398 | 693 |
| 4 | SRAM macros | ss_100C_1v60 / macro x2 | 16 | 3.500 | -0.489 | 250.7 | 16.6 | 4,184,426 | 4,755,453 | 143,138 | 34,924 | 16 | 0.701 | 688 |
| 4 | SRAM macros | ss_n40C_1v76 / macro x1.5 | 16 | 3.500 | -0.049 | 281.8 | 14.7 | 4,198,527 | 5,137,347 | 135,816 | 35,280 | 16 | 0.795 | 99 |
| 4 | SRAM macros | tt_025C_1v80 / macro x2 | 16 | 3.500 | -0.005 | 285.3 | 14.5 | 4,116,970 | 4,959,998 | 117,208 | 34,880 | 16 | 0.806 | 5 |
| 8 | flops | ss_100C_1v60 | 4 | 3.500 | -2.288 | 172.8 | 24.0 | 2,418,876 | 3,556,928 | 237,499 | 49,800 | 0 | 0.621 | 48,431 |
| 8 | flops | ss_n40C_1v76 | 16 | 3.500 | -0.224 | 268.6 | 15.4 | 6,669,086 | 9,563,616 | 579,006 | 169,182 | 0 | 2.194 | 6,918 |
| 16 | flops | ss_n40C_1v76 | 16 | 3.500 | -0.128 | 275.6 | 15.0 | 6,584,580 | 9,244,567 | 546,584 | 173,179 | 0 | 2.275 | 935 |

_No configuration closes timing at its target; worst is ASSOC=4 at -3.145 ns._
