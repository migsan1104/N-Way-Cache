# Tempus — signoff static timing analysis

Assume Tempus has never been touched before. This file is what it is, why this
project runs it, how our script works, and what the first real run said.

## What Tempus is

Cadence's dedicated signoff STA engine. Static timing analysis: no simulation,
no vectors — the tool builds a graph of every timing arc (cell delays from the
`.lib`, wire delays from parasitics) and computes, for every path, latest
arrival vs. required time. Setup = data must beat the capture edge; hold =
data must not arrive too soon after the previous one.

Innovus has a timer too (`timeDesign`), so why a second tool? Because the
implementation timer's job is to be *fast* — it runs thousands of times inside
`place_opt_design` — and it grades its own homework: it times the design
against the same wire *estimates* it optimised against. Tempus is the
independent second opinion with better inputs:

- a **frozen netlist** (`outputs/<tag>_pnr.v`),
- **extracted parasitics** — a SPEF per RC corner, from Quantus with the
  in-house validated techfile (`../quantus/quantus.md`), not a LEF-based guess,
- full-accuracy delay calculation (long-RC nets, slew propagation, SI).

Rule for this project: **Innovus numbers steer, Tempus-on-Quantus numbers get
quoted.**

## Context in this project

Signoff is the third flow of the ASIC track (synthesis → PnR → signoff, see
`../README.md`). Tempus closes the timing side: after the PnR flow's stage 06
export, the netlist + SPEFs come here and Tempus produces the number that
would go on a datasheet. If it finds violations, the fix path is the ECO loop
(`asic/ECO.md` §3): Tempus chooses the fixes (`opt_signoff`), Innovus applies
them (`ecoPlace`/`ecoRoute`), Quantus re-extracts, Tempus re-times.

## How our script works (`sta.tcl`)

The critical design decision: **corners cannot drift.** `sta.tcl` sources the
P&R run's own `innovus_config.tcl` and hands `init_design` the same
`mmmc.tcl` Innovus used — same libs, same derates (including the per-instance
SRAM-macro derates via `pnr_apply_macro_derates`), same ±10 % RC spread.
Tempus and Innovus share the MMMC/SDC infrastructure, which is what makes
that reuse possible.

Inputs it picks up from `$SIGNOFF_PNR_DIR/outputs/`:

- `${RUN_TAG}_pnr.v` — the post-route netlist
- `${RUN_TAG}_pnr.spef` — Quantus rc_slow SPEF
- `${RUN_TAG}_pnr_rc_fast.spef` — Quantus rc_fast SPEF (falls back to the
  slow one if absent)

Run it (fresh shell — the PnR `env.sh` is REQUIRED, it pins
`ASIC_SRAM_MACRO=1` and friends; skipping it mis-derives `RUN_TAG` and the
script errors on a missing netlist, found 2026-08-30):

```bash
bash -lc 'source /apps/settings && \
          source <repo>/asic/PnR/innovus/env.sh && \
          source <repo>/asic/signoff/env.sh && \
          cd <repo>/asic/signoff/tempus && \
          tempus -no_gui -files sta.tcl -log $SIGNOFF_RESULTS/tempus/tempus'
```

Outputs in `$SIGNOFF_RESULTS/tempus/` (results are keyed by P&R run so a
number can never be mismatched with its GDS): `summary.rpt` (the WNS/TNS/
violation-count table per path group), `setup.rpt` / `hold.rpt` (worst 50
paths each), `census.rpt` (1000-path summary, the format `asic/census.py`
groups into cones), `violators.rpt`.

## First real run (v2 shakedown, 2026-08-30 — flow test, junk design)

Ran in ~5 min on the v2 ring design (the run-1 floorplan that failed; the
point was exercising the flow, not the number):

| | Tempus (Quantus SPEF) | Innovus `timeDesign -signoff` (LEF RC) |
|---|---|---|
| setup WNS | **-18.15 ns** | -10.78 ns |
| setup TNS / viols | -194,889 ns / 36,665 | -25,988 ns / 22,144 |
| hold | clean (+0.127) | clean (+0.002) |

Lessons on record:

1. Both engines agree on *which* paths fail (way flag-read → central compare;
   macro `dout1` half-cycle → victim line) but disagree by ~7 ns on *how
   badly*. v2's critical paths are half-die wires with 22-buffer chains —
   exactly where a LEF estimate is most optimistic and real extraction hurts
   most. Expect the gap to shrink on a healthy floorplan (short wires are
   where estimate and extraction agree).
2. So Innovus's internal signoff timing on this design runs **optimistic**.
   Never quote it as the result.
3. Caveat to carry: the Quantus techfile is validated for signal-width wires
   (≤ ~2 µm); wider nets are extrapolated. Check the worst paths don't hinge
   on wide-net parasitics before quoting a close number.

## Next

- Re-run on the v3 winner after its stage 06 export (same command, new run's
  env). That one is the quotable number, at the corner-2 setup
  (ss_n40C_1v76 + macro ×1.5 — `asic/MACROS.md` "Run 2 sign-off corner").
- If hold (or small setup) violations appear: first ECO exercise, per
  `asic/ECO.md` §3 / Status.

## sta.tcl I/O virtual clock (2026-09-02)
Latency-matched vclk_io added for port timing; validation on iter7 caught two
bugs (period query dialect; single-corner latency minting fake reg2out hold
-7.8) - both fixed, late/early latencies now auto-measured per view (11.901 /
4.318 on iter7). OPEN ITEM: this run's REG2REG setup (-5.919 / 37,180 vio)
disagrees with the 09-01 corrected run (-4.291 / 16,936) on the same stamp +
branch - diff tempus.log vs tempus_vclk.log before quoting either.

## The exported-SDC source-latency split (2026-09-04) - READ before quoting any hold number

Every Tempus hold number before today was wrong (armC +5.145, iter16b
pass 1 +4.608). Cause: Innovus CTS (`update_io_latency`) sets a negative
source latency on `clk`; `write_sdc -view setup_view` exports only the
`-max` values, `-view hold_view` only the `-min` values, and `sta.tcl`
loaded the setup SDC into both views. Tempus uses max-qualified latency
for the capture clock and min-qualified for launch, so a one-kind view is
inconsistent. Loading both SDCs in one mode is also wrong (second
`create_clock` overwrites `clk`, TCLCMD-1594, and setup collapsed to
-4.8). Fix in `sta.tcl`: constraint mode `func` = setup SDC + every
`-source ... -max` line mirrored as `-min`; mode `func_hold` = hold SDC +
every `-min` mirrored as `-max`, attached to `hold_view` via
`update_analysis_view` BEFORE `set_interactive_constraint_modes`
(TCLCMD-1047 otherwise). New knobs: `SIGNOFF_TEMPUS_TAG` (output dir
suffix, used by `run_two_corner.sh`) and `SIGNOFF_PERIOD` (what-if period:
rewrites `create_clock` in SDC copies under `$out`). Full story:
`../WALKTHROUGH_2026-09-04.md` section 4. Also: Tempus drops to an
interactive prompt on a script error under tmux - feed `< /dev/null` or
send `exit`.

## 2026-09-07 12:05 - SI signoff rerun on the iter19b VSS-ECO package (v7)

`run_si_pass.sh` both ss corners, SIGNOFF_PERIOD=3.333, SIGNOFF_TAG_SUFFIX=_v7
(`results/<19b>/tempus_ss_*_d1.5_si_v7/`). The seven VSS ECOs rerouted
~450 signal nets (94 + 16 + 10 + 183 + 21 + 17 + 10 + 4 + 2 + windowed
rip-ups) around the new PG shapes with TD/SI off; this is the check that
they did not cost the 300 MHz signoff.

| corner | metric | pre-ECO (00:05) | v7 |
|---|---|---|---|
| ss_n40C_1v76 | worst setup (reg2out) | +0.891 | +0.880 |
| | reg2reg | +2.959 | +2.961 |
| | hold | +0.004 | +0.004 |
| ss_100C_1v60 | worst setup (reg2out) | +0.789 | +0.723 |
| | reg2reg | +1.440 | +1.442 |
| | hold | +0.004 | +0.004 |
| both | violators | 0 | 0 |

The reroutes cost 11 and 66 ps on the worst reg2out path; reg2reg and hold
are unchanged. 300 MHz stays closed in SI signoff on the package that also
passes IR (VSS 29 mV) and EM (VSS 1.010, VDD 1.001).

## 2026-09-07 14:00 - SI signoff rerun on the v8 package (right-channel stripes)

`run_si_pass.sh` both ss corners, SIGNOFF_PERIOD=3.333, SIGNOFF_TAG_SUFFIX=_v8,
on the 13:38 export of 07_vssfix.enc (ECO v8). 0 violators both corners.

| corner | reg2reg | reg2out | in2reg (all) | in2reg (data ports) | hold |
|---|---|---|---|---|---|
| ss_n40C_1v76 | +2.959 | +0.880 | +3.086 (rst) | +3.720 (cpu_resp_ready) | +0.004 |
| ss_100C_1v60 | +1.440 | +0.723 | +2.045 (rst) | +2.245 (cpu_resp_ready) | +0.004 |

reg2out identical to v7 (+0.880 / +0.723); reg2reg worst path +1.440 vs +1.131 on
v7 (the top-1 path moved; both corners' worst-50 are the same cones). sta.tcl now
also writes `in2reg.rpt`, `in2reg_data.rpt` (inputs minus rst) and
`clock_summary.rpt` (report_clock_timing -type summary).

### The I/O clock model is not latency-matched (found 2026-09-07 13:30-14:00)

`clock_summary.rpt` shows the propagated tree at n40C spans network latency
~0.45 ns (RESPONSE_UNIT FIFO pointer flops, the reg2out launchers) to ~9.6 ns
(tag banks); 2.35 to ~11 ns at 100C. The virtual I/O clock's "auto" latency
(2.282 / 4.714) came from `report_clock_timing -type latency`, which prints a
single row - it is NOT the tree maximum. Consequences, read straight off the
path reports: reg2out captures 2.4 ns after the FIFO-pointer launch clock
(worst path is 4.67 ns of logic at 100C - rd_ptr -> 8:1 FWFT mux -> hit/miss
select -> cpu_resp_rdata - which a zero-skew model cannot close at 3.333 ns);
in2reg (rst -> allocated_mem) captures at 10.584 ns against a 4.714 launch.
The exported SDC also carries Innovus's update_io_latency source latency on
clk (-7.33 ns setup / -2.97 hold); path reports do not show it applied to the
launch/capture arrivals. ~~Core reg2reg is unaffected (both ends propagated,
CPPR).~~ **WRONG, corrected 2026-09-07 17:30:** the source latency is applied
to the launch clock only, in Tempus AND in Innovus, so every reg2reg setup
path was 7.3 ns optimistic. Stripped rerun (`_v8_strip`, n40C): reg2reg
-3.899, in2reg -3.599, reg2out +0.876, i.e. ~7.2 ns / ~138 MHz. Full write-up
and the flow fix: `asic/PnR/innovus/CTS.md` §5 "The 7.331 ns gift". Innovus's own CTS report on 19b: latency 0.139 to 2.501 ns at the CTS
corner (skew 2.36) - the tree is skewed at CTS already, x4 at signoff RC.
Next: pessimistic what-if (ASIC_IO_VCLK_LATENCY = tree max, _EARLY = tree
min, per corner), then decide between CTS rebalancing / boundary-register
skew group and a registered Response_Unit output.

## 2026-09-07 18:45 - HONEST signoff of the 19b v8 package: 9.1 ns (110 MHz) at ss_n40C_1v76

After the source-latency finding (`asic/PnR/innovus/CTS.md` section 5 "The
7.331 ns gift") every earlier number in this file from the route stage on is
void. Re-signoff: `run_si_pass.sh <19b> ss_n40C_1v76:1.5` with
`SIGNOFF_PERIOD` what-ifs, the exported clk source latency stripped (default
now), reference-pin I/O model (`ASIC_IO_REF_PIN=inreg_valid_r_reg/CLK`),
SI on, macro x1.5. n40C only by decision (the 100C corner with the macro
derate is not a meaningful corner for this package); 100C stripped reg2reg at
3.333 was -5.428 for the record.

| period | tag | reg2reg | reg2out | in2reg (all) | in2reg (data) | hold | violators |
|---|---|---|---|---|---|---|---|
| 3.333 | `_v8_refpin_dbg2` | -3.899 | -0.625 | - | -1.542 | +0.004 | many |
| 7.3 | `_v8_p7p3_refpin` | -0.867 | +3.271 | +1.358 | +2.046 | +0.004 | 30 |
| **9.1** | **`_v8_p9p1_refpin`** | **+0.105** | +5.071 | +3.132 | +3.846 | +0.004 | **0** |

The path that sets the period from 7.3 ns up is the SRAM read: the OpenRAM
macro launches `dout1` on the falling edge (half-cycle path), 0.858 ns access
(x1.5) + 3.6 ns of never-optimized logic into
`COMPARE_SELECT_REPLACE_out_rdata_reg` (CTS.md section 5, "the other 250 MHz
blocker"). Slack on that path moves 0.5 ns per 1 ns of period, so 9.0 ns
would still close by ~0.05 ns; 9.1 is quoted for the 0.1 ns margin.
**Quote: 19b v8 GDS, 110 MHz, SI signoff, ss_n40C_1v76, macro x1.5, 0
violators, hold +0.004.** Post-layout SDF GLS at 7.3 ns is running as the
simulation cross-check (it failed at 185 ns at 3.333 ns).

**Correction to the 2026-09-06 "300 MHz misses are physical" list (added 2026-09-07 19:25).**
The three I/O violations that motivated iter21's RTL changes (port -> way-replica
fanout -0.457, rst tree -0.450, miss-FIFO -> cpu_resp_rdata -0.084) were measured
with the one-sided clk source latency in place and a single-latency virtual I/O
clock (CTS.md section 5). Internal paths received ~7.3 ns they did not have, port
paths did not, so "only I/O fails" was the artefact's signature, not a finding.
What survives an honest model: the registered reset is free and correct
regardless; the response-data output path is 4.67 ns of logic on 19b, which does
not fit 4.0 ns minus the 0.3 ns budget under any clock model, but part of that
length is never-optimized repeater bloat, so whether the skid buffer is required
at 250 MHz is decided by iter22's honest post-route number, not by the 09-06 list.

## 2026-09-11 - iter26b SIGNED OFF: 188.7 MHz (5.3 ns), ss_n40C_1v76, SI, on the real export

The package is `runs/<26b>/checkpoints/05_tagskew10.enc`, exported 2026-09-11
01:48 as "pass 5" of the chain (`runs/<26b>/outputs/`, the GDS the README
hero image renders). It is the iter26b route (E35 netlist, quad floorplan
with 260 um way channels, ctsA tree, 4.0 ns P&R target) plus four ECOs on
the routed database, in order: antenna diodes legalized (`05_antenna_final6`),
PG via arrays on all edges (`05_pgvia7` / `05_pgvia9`, voltus.md), 160
`clkdlybuf4s25_1` on the SRAM-read capture registers (`05_clkskew8`) and
176 more on the tag-read registers `rtag_raw_r` / `refill_rd_tag_r`
(`05_tagskew10`, plus 6 diodes). Tempus setup: `sta.tcl` with
`SIGNOFF_PERIOD` what-ifs, SI on, Quantus SPEF, reference-pin I/O model
(`inreg_valid_r_reg/CLK`, input delay 0.700, output 0.300), reg2out hold
timed, exported clock source latency stripped, uncertainty 0.10 / 0.05,
macro derate x1.5 late / x0.67 early. Results in
`results/<26b>/tempus_si_p5p3_refpin_hold_tagskew10/` and `..._p5p5_...`.

| period | reg2reg | reg2out | in2reg | hold | reg2out hold | violators |
|---|---|---|---|---|---|---|
| **5.3 ns (188.7 MHz)** | **+0.015** | +1.118 | +0.944 | +0.075 | +0.487 | **0** |
| 5.5 ns (181.8 MHz) | +0.010 | +1.319 | +1.144 | +0.075 | +0.491 | 0 |

Worst path at both periods: the OpenRAM half-cycle read, `GEN_WAYS[2]
...g_bank[1].u_sram/dout1[11]` (launched by the falling edge, arrival 5.899
at 5.3) into `COMPARE_SELECT_REPLACE_out_rdata_reg[20]`. The 5.3 slack being
*larger* than the 5.5 slack on the same path is SI: crosstalk windows move
with the period, so 10-15 ps here is noise, not margin. Quote 188.7 MHz
with "closes by 15 ps"; 182 MHz (5.5) is the conservative headline, and the
pgvia9 export (pass 4, no tag-skew ECO) independently closes 5.5 at +0.011
with its own clean KLayout/LVS/Voltus, so 182 MHz is a fully proven fallback.

### How the ECOs bought the last 0.6 ns (Tempus SI, real exports, same period rows)

| export | 5.3 | 5.5 | 5.88 | 6.0 | 6.667 |
|---|---|---|---|---|---|
| final6 (diodes only, pass 2) | - | -0.179 | +0.002 | +0.017 | +0.236 |
| clkskew8 (+160 SRAM-capture delay cells, pass 3) | - | +0.010 | +0.200 | +0.260 | - |
| pgvia9 (+PG vias, pass 4) | -0.010 | +0.011 | +0.200 | +0.260 | - |
| **tagskew10 (+176 tag-read delay cells, pass 5)** | **+0.015** | +0.010 | - | - | - |

The 5.0 ns what-if on clkskew8 (-0.310, 61 violators) showed the next wall:
once the SRAM path is skewed, the full-cycle tag-array read
(`rindex_rep_r_reg -> rtag_raw_r_reg`, 3.78 ns of replica fanout) and
`refill_set_id -> refill_rd_tag_r` take over. The tag-skew ECO borrows
from those registers' downstream slack (+0.135 at 5.0 into the PLRU and
`alloc_wen`) and is what turns pgvia9's -0.010 at 5.3 into +0.015. Below
5.3 the honest fix is RTL (E39: register the macro output inside its valid
window, +1 cycle hit latency), not another ECO.

### Are setup and hold timed at the right corners? (asked 2026-09-11)

Yes, checked on the pass-5 reports and log rather than the script:

- Every setup report (`reg2reg.rpt`, `reg2out.rpt`, `in2reg.rpt`,
  `setup.rpt`) says `Analysis View: setup_view` = delay corner `ss_corner`
  = library set `ss_libs` (`sky130_fd_sc_hd__ss_n40C_1v76` + macro
  `SS_1p8V_25C`) + RC corner `rc_slow` (100 C, R and C x1.10) with the
  x1.5 *late* derate on the 16 macro instances.
- Every hold report (`hold.rpt`, `reg2out_hold.rpt`) says `Analysis View:
  hold_view` = `ff_corner` = `ff_libs` (`sky130_fd_sc_hd__ff_n40C_1v95` +
  macro `FF_1p8V_25C`) + `rc_fast` (-40 C, R and C x0.90) with the x0.67
  *early* derate. `set_analysis_view -setup {setup_view} -hold {hold_view}`
  is in the log, and the `report_timing -early` calls are what write the
  hold files.

Two honest limits of that split. Both RC corners read the same Quantus
SPEF (`*_pnr.spef`; no `_rc_fast.spef` was extracted), so the only RC
spread between the corners is the +/-10 % scaling in `mmmc.tcl` - hold is
timed with fast cells on slow-corner-derived wires scaled down 10 %, which
flatters hold slightly. And hold is timed at the fast corner only; a full
signoff would also time hold at `ss_corner` (cold, slow) where clock-tree
insertion delay grows. On this tree (balanced, 3.6 ns insertion, 0.35 ns
target skew) the +0.075 hold margin is the same on every export since the
CTS fix, so neither limit changes the conclusion; both are listed so the
next flow pass can close them (extract a second SPEF at -40 C; add
`set_analysis_view -hold {hold_view setup_view}`). The 806 "nets missing in
SPEF" the log reports are all `UNCONNECTED*` dangling outputs, no timing
arcs.

### Caveats carried on the 188 MHz number

1. The macro timing is a x1.5 derate of the PDK's SS_1p8V_25C lib, not a
   characterized ss_n40C_1v76 corner (MACROS.md); x2.0 would fail 5.3.
2. No standard-cell OCV derate, only the 0.10 / 0.05 ns uncertainty.
3. The capture registers now sample `dout1` ~0.6 ns after the macro's own
   rising edge (0.3 before the skew ECO). The lib has no "dout invalid after
   clk rises" arc and the GLS model holds dout, so neither STA nor GLS can
   see a hold-after-rising-edge failure inside the OpenRAM sense path. This
   is the one physical unknown on the package; E39 removes it.
4. 15 ps of margin at 5.3 is inside SI noise; 5.5 / 182 MHz is proven on
   two independent exports.
