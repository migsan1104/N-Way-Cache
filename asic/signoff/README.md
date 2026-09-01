# Signoff

Third flow of the ASIC track: synthesis (`asic/synthesis`, Genus) -> physical
design (`asic/PnR`, Innovus) -> **signoff** (here). Signoff consumes a P&R
run's deliverables and never modifies the design; every result is keyed by
the P&R run stamp it was measured on so a number and the GDS it came from
can never be mismatched.

| check | tool | consumes | status |
|---|---|---|---|
| parasitic extraction | Quantus (`quantus/`) | DEF/LEF or GDS, **QRC techfile** | techfile built and **validated for signal-width wires 2026-08-30** (`quantus/quantus.md`); design-level extraction via `quantus/extract_pnr.tcl` |
| signoff STA | Tempus (`tempus/`) | P&R netlist + SPEF + SDC, MMMC from `PnR/innovus/scripts/mmmc.tcl` | `sta.tcl` drafted, waits on stage 09 outputs |
| DRC | Magic (`drc/`); KLayout as second opinion | GDS, PDK Magic deck | script drafted; macro-only shakedown 08-28 gave a contradictory count (1.1M error tiles / "0 errors") - deck style not right yet |
| LVS | Magic extract + netgen (`lvs/`) | GDS vs P&R netlist, PDK netgen setup | script drafted; macro shakedown 08-28 FAILED: the rebadged macro name `sram_1rw1r_32_256_8_sky130` is not in the PDK spice (`sky130_sram_1kbyte_1rw1r_32x256_8`), needs a name map; the run also scattered 154 `.ext` files into `signoff/` (gitignored, delete) |
| IR drop | Voltus (`voltus/`) | P&R DB, cell power libs | run 2, optional |

Licenses (checked 2026-08-28, `lmstat -a`, 300 seats each, 0 in use):
Quantus (`QRC_*`, `Virtuoso_QRC_Extraction_XL`), Tempus (`Tempus_Timing_Signoff_*`),
Voltus, Pegasus (DRC, LVS). Installs: `/apps/cds/quantus221`, `/apps/cds/ssv231`
(Tempus + Voltus).

**Pegasus correction (2026-08-30):** `/apps/cds/pegasus231` is **Pegasus DFM**
(LPA / CMP / CAA / CPA - `bin/pegasus-lpa`, `pegasus-cpa`, `pegasus-caa`), not
Pegasus Verification; there is no `pegasus` DRC/LVS executable anywhere under
`/apps/cds` (Assura 4.1 is the only Cadence PV engine installed). Using Pegasus
for DRC/LVS would need (a) an IT install of Pegasus Verification and (b) a
hand-written sky130 rule deck, since the PDK ships decks for Magic / netgen /
KLayout only. Until both exist, DRC/LVS = Magic + netgen (+ KLayout).

Layout:

```
signoff/
  env.sh           tool sourcing + PDK paths + which P&R run to check
  quantus/         ICT -> Techgen -> qrcTechFile (the one deck we can build ourselves)
  tempus/ drc/ lvs/ voltus/
  results/<pnr-run-stamp>/<check>/     gitignored
```

Rules: reuse P&R's constraints and corners through `innovus_config.tcl`'s
variables (Tempus reads the same Tcl) rather than copying them; take PDK decks
from `libs.tech/` in place; results directory named after the P&R run stamp.
