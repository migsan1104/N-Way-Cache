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
