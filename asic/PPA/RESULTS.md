# ASIC synthesis PPA results

Regenerated from each run's `reports/` by:

```bash
cd asic && ./collect_ppa.py --tool genus --markdown PPA/RESULTS.md
```

`collect_ppa.py` reads the newest run per associativity that has a final
`qor.rpt`, so a run still in flight never shadows the last completed one.

**Read the "Cache (KB)" and "Target (ns)" columns before comparing rows.**
The table below is NOT a uniform sweep: it is whatever the newest completed
run per associativity happens to be, and right now those runs come from
different eras. Only **ASSOC=4 is at the project's 16KB capacity target**;
the other four rows are leftover 4KB runs, two of them at a 2.000 ns target
rather than 3.500 ns. Rows are comparable to each other only where capacity
and target match.

Numbers are placement-based estimates (PLE), not post-P&R: treat every slack
as a floor. See `PHYSICAL_DESIGN.md` §4 (synthesis stages) and §8 (wire
modeling).

## Current state (2026-08-21)

- **ASSOC=4, 16KB, flop banks, E9-E19a RTL** is the live measurement:
  WNS -2.163 ns @ 3.500 ns => **176.6 MHz**, 7.39 mm^2 cell area, 1.703 W.
  Run `PPA/genus/assoc_4/runs/20260821_132313`, 6h18m.
- Against the same configuration on Entries 1-8 RTL
  (`runs/20260820_042842`: WNS -2.656, 8.24 mm^2 cell, 1.791 W), the
  optimization campaign is worth **+493 ps (+8.7% Fmax), -10.4% cell area,
  -18.2% total area, -4.9% power**.
- The worst path is `MSHR_REQ_ARBITER_order_head_r_reg[0]/CLK ->
  mem_req_wdata[2]` — Entry 18's grant-time victim read. It held WNS through
  mapping, serial opt, eight partitioned opt jobs, and reassembly, which is
  what marks it structural rather than something opt could have fixed.
- A1/A2/A8/A16 at 16KB are **owed**; so is the macro-vs-flop pair
  (`ASIC_SRAM_MACRO=1 ./run_genus.sh 4`, launched 19:43).

### Cadence Genus

| ASSOC | Cache (KB) | Target (ns) | WNS (ns) | Achievable Fmax (MHz) | Hit latency (ns) | Cell area (um^2) | Total area (um^2) | Cells | Sequential | Macros | Total power (W) | Violating paths |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 4 | 2.000 | -1.381 | 295.7 | 14.3 | 2,287,635 | 2,287,635 | 282,515 | 46,585 | 0 | 1.212 | 43,864 |
| 2 | 4 | 2.000 | -1.272 | 305.6 | 13.7 | 2,423,165 | 2,423,165 | 286,570 | 47,334 | 0 | 1.239 | 45,566 |
| 4 | 16 | 3.500 | -2.163 | 176.6 | 23.5 | 7,387,209 | 9,814,943 | 693,356 | 166,079 | 0 | 1.703 | 180,675 |
| 8 | 4 | 3.500 | -2.288 | 172.8 | 24.0 | 2,418,876 | 3,556,928 | 237,499 | 49,800 | 0 | 0.621 | 48,431 |
| 16 | 4 | 2.000 | -1.255 | 307.2 | 13.5 | 2,709,735 | 2,709,735 | 336,337 | 52,874 | 0 | 1.447 | 49,380 |

_No configuration closes timing at its target; worst is ASSOC=8 at -2.288 ns._

