# ASIC synthesis PPA results

The table below is regenerated from each run's `reports/` by:

```bash
cd asic && ./collect_ppa.py --tool genus
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

## Current state (2026-08-22)

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
| 1 | flops | ss_100C_1v60 | 4 | 2.000 | -1.381 | 295.7 | 14.3 | 2,287,635 | 2,287,635 | 282,515 | 46,585 | 0 | 1.212 | 43,864 |
| 2 | flops | ss_100C_1v60 | 4 | 2.000 | -1.272 | 305.6 | 13.7 | 2,423,165 | 2,423,165 | 286,570 | 47,334 | 0 | 1.239 | 45,566 |
| 4 | flops | ss_100C_1v60 | 16 | 3.500 | -1.844 | 187.1 | 22.2 | 4,478,379 | 5,633,973 | 187,334 | 34,919 | 16 | 0.719 | 15,518 |
| 4 | flops | ss_100C_1v60 | 16 | 3.500 | -2.163 | 176.6 | 23.5 | 7,387,209 | 9,814,943 | 693,356 | 166,079 | 0 | 1.703 | 180,675 |
| 4 | SRAM macros | ss_100C_1v60 / macro x2 | 16 | 3.500 | -0.489 | 250.7 | 16.6 | 4,184,426 | 4,755,453 | 143,138 | 34,924 | 16 | 0.701 | 688 |
| 4 | SRAM macros | ss_n40C_1v76 / macro x1.5 | 16 | 3.500 | -0.059 | 281.0 | 14.8 | 4,164,468 | 5,068,596 | 142,782 | 34,804 | 16 | 0.782 | 72 |
| 4 | SRAM macros | tt_025C_1v80 / macro x2 | 16 | 3.500 | -0.005 | 285.3 | 14.5 | 4,116,970 | 4,959,998 | 117,208 | 34,880 | 16 | 0.806 | 5 |
| 8 | flops | ss_100C_1v60 | 4 | 3.500 | -2.288 | 172.8 | 24.0 | 2,418,876 | 3,556,928 | 237,499 | 49,800 | 0 | 0.621 | 48,431 |
| 16 | flops | ss_100C_1v60 | 4 | 2.000 | -1.255 | 307.2 | 13.5 | 2,709,735 | 2,709,735 | 336,337 | 52,874 | 0 | 1.447 | 49,380 |

_No configuration closes timing at its target; worst is ASSOC=8 at -2.288 ns._
