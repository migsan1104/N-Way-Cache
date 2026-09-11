# Signoff

**Signed-off package (2026-09-11):** P&R run
`20260908_iter26b_quad2_ch260_e35fo32_ctsA_p4000_1v76`, checkpoint
`05_tagskew10.enc`, export in its `outputs/`. 188.7 MHz (5.3 ns) in Tempus
SI at ss_n40C_1v76 with the macro derate, route DRC 0, antenna 0, KLayout
clean outside the macros, LVS clean, IR/EM clean, gate-level simulation at
5.3 ns passes the full regression. Sheet: `GDS11_Image/Iter26b_SO.png`;
per-check notes in each subdirectory's `.md`; the 182 MHz fallback
(pgvia9 export, pass 4) has its own complete result set under
`results/<run>/pass4_pgvia9/`.

Third flow of the ASIC track: synthesis (`asic/synthesis`, Genus) -> physical
design (`asic/PnR`, Innovus) -> **signoff** (here). Signoff consumes a P&R
run's deliverables and never modifies the design; every result is keyed by
the P&R run stamp it was measured on so a number and the GDS it came from
can never be mismatched.

| check | tool | consumes | status |
|---|---|---|---|
| parasitic extraction | Quantus (`quantus/`) | DEF/LEF or GDS, **QRC techfile** | techfile built and **validated for signal-width wires 2026-08-30** (`quantus/quantus.md`); design-level extraction via `quantus/extract_pnr.tcl` |
| signoff STA | Tempus (`tempus/`) | P&R netlist + SPEF + SDC, MMMC from `PnR/innovus/scripts/mmmc.tcl` | **iter26b signed off 2026-09-11: 5.3 ns / 188.7 MHz, SI, ss_n40C_1v76, 0 violators, hold +0.075** (`tempus/tempus.md`) |
| DRC | KLayout `sky130A_mr.drc` (`drc/`); Magic retired | merged GDS | **iter26b: 9 items outside the macros, all known artefacts** (`drc/drc.md`); Magic's counts never reconciled and are not used |
| LVS | Magic extract (macros black-boxed) + netgen (`lvs/`) | GDS vs `*_pnr_lvs.v` | **iter26b: 197,438 = 197,438 devices, +64 macro wmask1 tie-off nets only** (`lvs/lvs.md`); caught the overlapping antenna diodes on pass 1 |
| IR drop / EM | Voltus (`voltus/`) | exported DEF + SPEF, PGV | **iter26b: VDD 22 mV / VSS 22.6 mV worst, EM 0 elements over limit** after two PG via ECOs (`voltus/voltus.md`) |
| DRC/LVS, 2nd engine | Pegasus (`pegasus/`) | GDS + P&R netlist, hand-ported sky130 deck | side project — binary not installed (IT request), teaching-grade DRC deck staged; `pegasus/Pegasus.md` is the ledger |

Licenses (checked 2026-08-28, `lmstat -a`, 300 seats each, 0 in use):
Quantus (`QRC_*`, `Virtuoso_QRC_Extraction_XL`), Tempus (`Tempus_Timing_Signoff_*`),
Voltus, Pegasus (DRC, LVS). Installs: `/apps/cds/quantus221`, `/apps/cds/ssv231`
(Tempus + Voltus).

**Pegasus (2026-09-01):** `/apps/cds/pegasus231` is **Pegasus DFM**, not
Pegasus Verification — no `pegasus` DRC/LVS executable exists under `/apps/cds`,
though the licenses do. Standing it up is a side project tracked in
`pegasus/Pegasus.md` (investigation, staged OSU DRC deck, drafted runner and
IT request). Until it lands, DRC/LVS = Magic + netgen (+ KLayout).

Follow-along narrative of a full signoff day, with the lessons:
`WALKTHROUGH_2026-09-04.md` (export, fill, connectivity classification, the
Tempus SDC bug, Fmax claims, utilisation, Voltus PGVs).

Layout:

```
signoff/
  env.sh           tool sourcing + PDK paths + which P&R run to check
  quantus/         ICT -> Techgen -> qrcTechFile (the one deck we can build ourselves)
  tempus/ drc/ lvs/ voltus/
  pegasus/         side project: Pegasus DRC/LVS (Pegasus.md = ledger, decks/, runner)
  results/<pnr-run-stamp>/<check>/     gitignored
```

Rules: reuse P&R's constraints and corners through `innovus_config.tcl`'s
variables (Tempus reads the same Tcl) rather than copying them; take PDK decks
from `libs.tech/` in place; results directory named after the P&R run stamp.
