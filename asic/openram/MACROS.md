
## Characterization grid: why the family is 2x2 (2026-08-23)

The 32x64 job died 2 h in at the first point of its load/slew sweep — slew
0.00125 ns, load 1.7225 fF, the (0.25, 0.25) scale point — with the same
`delay.py:1359 "Couldn't run a simulation"` that had killed the
calibration's first attempt 8 h in. Diagnosed from the surviving
`/tmp/openram_*_temp/timing.lis`; two separate defects, one per axis.

**Slew 0.25 — a measurement coin flip, not a circuit failure.** The read
was correct: Q, Q̄ and dout all measured at the right value on both ports
in both read cycles. What failed was

    delay_sen1 = -inf   targ=190.4n   trig=inf

OpenRAM puts that measure's `TD` exactly at the instant the clock's
falling edge *starts* (`get_delay_measure_variants` adds `period/2` to
the cycle start), and at this slew the edge is 1.25 ps wide. ngspice did
not report the crossing after TD, though the `delay_hl1` measure — same
edge, TD half a period earlier — found it. `parse_spice_list` cannot
match `-inf` (its regex wants digits) and returns `"Failed"`,
`check_sen_measure` rejects the non-float, `run_delay_simulation`
returns False, assert. Tally across three runs: 3 misses in 6
port-trials at this point (32x64 port 1, calibration attempt 1 port 0,
32x128 neither) and zero misses in the dozens of sims at slews
0.005/0.04. A 5-line standalone ngspice deck with the same PULSE and
TD does *not* miss, so the exact numerical trigger is the full
circuit's timestep placement around the breakpoint, not the `.meas`
semantics alone — but the point is moot: no sky130 gate produces a
1.25 ps edge, so the row carries no information.

**Load 0.25 — a silently wrong column.** The 32x128 run *passed* the
point, and its lib is the evidence against it. `cell_rise` on dout0 at
1.7 / 6.9 / 27.6 fF reads **2.616 / 0.318 / 1.809 ns**; dout1 reads
2.834 / 0.097 / 1.400. At 1.7 fF the output moved before `s_en` fired,
`delay_hl` came back negative, and `check_valid_delays` took its
"captured precharge" branch: it substitutes `delay_lh` (measured on the
other read cycle) and reports success. Genus interpolating that column
would see 2.6 ns for a macro driving a single gate. A lib containing it
must not be linked. That run is archived at
`macros_out/32x128_fullgrid_20260822/` for the record.

**Decision (user, 2026-08-23 11:05):** the whole family characterizes on
`load_scales = [1, 4]`, `slew_scales = [1, 8]` — 2x2 tables, identical
to the calibration macro. 32x64 relaunched 11:05; 32x256/512/1024 killed
~25 h into their min-period searches (neither bad point had been reached
yet) and relaunched 11:08; 32x128 relaunched 11:10. Six tmux sessions
(`gen64` … `gen1024`). Expected: layout 11-174 min, then roughly half
the characterization time of the full grid.

Two things this leaves on the table, both for the integration phase:
the grid tops out at 27.56 fF, below what a 64:1 mux input presents,
so Genus will extrapolate above it; and the precharge-before-`s_en`
behaviour at light load is a real property of an unbuffered `dout` —
the output wants a buffer at the macro boundary regardless of which lib
is linked.

## PARKED 2026-08-24 — the 32x64 access-time anomaly

Measured at SS/1.6V/100C, load 6.89/27.56 fF, slew 0.005/0.04 ns:

| macro | words_per_row | cell_rise (min load -> max load) |
|---|---|---|
| 32x64  | 1 | **2.550 -> 3.688 ns** (dout1: 2.743 -> 3.886) |
| 32x128 | 2 | **0.318 -> 1.809 ns** |

A 64-deep macro cannot legitimately be 8x slower than a 128-deep one.
Two facts gathered before parking:
 - The configs are IDENTICAL apart from num_words/paths (diffed), but
   the datasheets show different array organization: words_per_row 1
   vs 2. The 64 got no column mux.
 - 2.55 ns sits right next to the 2.616 ns "captured precharge"
   artifact value documented in gen_32x64.py's own header for the
   32x128 run's DROPPED 1.7 fF column (dout moves before s_en, OpenRAM
   silently substitutes delay_lh for delay_hl). Hypothesis: the 64's
   KEPT grid points hit that same pathology, i.e. its lib is bad.

To finish the check when it matters: inspect the 32x64 delay measures
for an hl->lh substitution at the kept load points (macros_out/32x64/
delay_meas.sp + the run's timing.lis), and compare against the 128's
clean points. Re-characterize with a shifted grid if confirmed.

NOT BLOCKING: nothing binds the 64. A4 binds 32x256. Parked by user
2026-08-24 until the 32x256 characterization lands - that is the lib
that decides whether the macro-DOUT co-wall at WNS -729 (13-20 paths,
currently a x2.0-derated 1.31 ns vendored 1.8V number) is real or
fiction.
