# Quantus: building a QRC techfile for sky130A

Started 2026-08-28. Quantus is installed and licensed on this server, but the
sky130 PDK ships no QRC techfile (`.tch`), which is why every extraction so far
is Innovus's LEF-based estimate and why Genus's `opt_spatial` fails with
PHYS-1015. This directory builds that techfile.

## Files

- `sky130A.ict` - the process description (conductors, dielectrics, vias).
  Sources are listed in its header; every number is traceable to a file on
  this server except the dielectric constants, which come from the SkyWater
  stack documentation and are what validation calibrates.
- `run_techgen.sh [nom|min|max]` - runs `Techgen -ict sky130A.ict -output
  techfiles/sky130A_<corner>.tch`; log in `techgen_<corner>.log`.
- `techfiles/` - output (gitignored until validated; then track the nom file).

## Status

| step | state |
|---|---|
| 1. ICT drafted (nom) | done |
| 2. Techgen compiles it | done 2026-08-28 (11.2 h CPU, `techfiles/sky130A_nom.tch`). **122 of 381 field-solver jobs logged `error in 2d field solver` / "intervals intersect"** (`work_nom/jobs/*.log`); the affected models are the wide-width ones (see step 3) |
| 3. Validation vs tech LEF | **done 2026-08-30 - PASS for signal-width wires**, table below |
| 4. min / max corners | not started |
| 5. `create_rc_corner -qx_tech_file` in `PnR/innovus/scripts/mmmc.tcl`, Tempus reads it | wired (opt-in via `ASIC_QRC_TECH`); design-level run in progress (`extract_pnr.tcl`) |
| 6. Genus physical-aware `opt_spatial` retry | after 5 |

### Validation result (nom, 2026-08-30, `validate/out_nom/compare.txt`)

Isolated 1000 um wires and 50 x 50 um plates per layer, nothing else on the die;
`C_lef` = LEF `CPERSQDIST`*area + `EDGECAPACITANCE`*perimeter.

| layer | min-width wire C (qrc/lef) | 1.0 um wire | 2.0 um wire | 50 um plate | wire R (qrc/Rsq*L/W) |
|---|---|---|---|---|---|
| met1 | 0.88 | 1.02 | 1.05 | 1.97 | 1.00 |
| met2 | 0.86 | 1.01 | 1.06 | 2.11 | 1.00 |
| met3 | 0.87 | 0.95 | 1.02 | 2.05 | 1.00 |
| met4 | 0.86 | 0.93 | 1.01 | 2.03 | 1.00 |
| met5 | 0.87 (1.6 um min) | - | 0.88 | 1.96 | 1.00 |

- Resistance is exact on every layer and width: the conductor table is right.
- Capacitance inside Techgen's modelled width range (its width tables stop at
  ~1.4-2.4 um, `work_nom/jobs/*.log` "Width limits") is within +-15 % of the LEF
  model on every layer, and the min-width met1 wire (0.0747 fF/um) is within 1 %
  of the PDK's own OpenRCX rule (`$PDK/libs.tech/openlane/rules.openrcx.sky130A.nom.spef_extractor`,
  met1 OVER substrate 0.0753 fF/um) - an independent reference.
- The 50 um plates come out 2x. Their R is exact, so the geometry is single;
  the cap is an EXTRAPOLATION beyond the width tables, from the model family
  whose solver jobs failed. Treat any net wider than ~2 um (PG stripes, the
  macro power straps) as unvalidated; signal routing in this design is all
  min-width.
- Quote as: "Quantus with an in-house sky130A techfile, validated against the
  foundry tech LEF and OpenRCX rules for signal-width wires (R exact, C within
  15 %)". Never as a foundry-qualified extraction.

Three flow bugs found and fixed by this validation run: `create_rc_corner
-qrc_tech` is not an Innovus 21 option (silently ignored -> IMPEXT-3491, and
the reason stage 09's `extractRC` failed on 08-29); the correct one is
`-qx_tech_file`. `compare.py` did not resolve the SPEF `*NAME_MAP`. The plate
test structure drew a 50 um pin on top of the 50 um route (2x C, R/2).

## Validation (what makes it quotable)

A hand-written stack can be 2x off silently. Three checks, cheapest first:

1. **Parallel-plate sanity.** For each metal, the tech LEF gives
   `CAPACITANCE CPERSQDIST` (area cap to substrate, aF/um^2) and
   `EDGECAPACITANCE`. A single wide plate over substrate extracted by Quantus
   must land within ~15 % of the LEF area cap (met1 25.8, met2 16.9, met3
   12.4, met4 8.4, met5 6.3 aF/um^2). If a layer is off, its ILD thickness
   or k is wrong - adjust the dielectric below it. Test structure: a small
   DEF with one 50 x 50 um plate per layer.
2. **Unit-length wire.** A 1 mm minimum-width wire per layer: compare
   Quantus R (must equal Rsq x L/W exactly - that checks the conductor
   table) and total C against Innovus's LEF-based `extractRC` on the same DEF.
3. **Design-level.** Extract run 1's routed DEF with Quantus and with Innovus
   LEF-based extraction; compare total cap per net on the 1000 census nets
   (`asic/census.py` grouping). Agreement within ~20 % with a consistent
   sign is the bar; report the ratio alongside any Quantus-based slack.

Independent second opinion if wanted: OpenRCX (rule files ship in
`$PDK/libs.tech/openlane/rules.openrcx.sky130A.*`, needs OpenROAD) or Magic
`ext2spice -c` on the GDS.

## How Innovus / Tempus will use it

```tcl
create_rc_corner -name rc_nom -qx_tech_file $env(SKY130_QRC_TECH_DIR)/sky130A_nom.tch -T 25
setExtractRCMode -engine postRoute -effortLevel signoff    ;# invokes Quantus
extractRC
```

replacing the `-preRoute_res/-preRoute_cap` scaling in `mmmc.tcl`. Quote the
result as "Quantus with an in-house sky130A techfile validated against the
foundry tech LEF" - never as a foundry-qualified extraction.
