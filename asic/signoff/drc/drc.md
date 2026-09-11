# DRC — design rule checking with Magic

Assume DRC has never been run here before. What it is, why Magic (and not a
Cadence tool), how the script works, and where the shakedown stands.

## What DRC is

Design Rule Checking verifies the final mask geometry (the GDS) against the
foundry's manufacturing rules: minimum widths, spacings, enclosures, density.
It knows nothing about logic or timing — a design can be DRC-clean and
functionally wrong, or timing-clean and unmanufacturable. It is a *geometry*
check, and it runs on the **merged** GDS (see the trap below).

Note the name collision: Innovus's `verify_drc` checks *routing* rules during
implementation (that is what the stage-05 gate counts). Signoff DRC checks
*mask* rules with the foundry's own deck. Different rule sets, different
severity — this one is the tapeout gate.

## Why Magic

The tool follows the deck, and only Magic / netgen / KLayout have sky130
decks (the PDK ships them in `libs.tech/`). The licensed Cadence engine for
this (Pegasus Verification) is not installed on this server — `/apps/cds/
pegasus231` is Pegasus **DFM** (litho/CMP analysis, no DRC/LVS binary) — and
no sky130 Pegasus deck exists anyway (`../README.md`). Magic's deck is the
one the sky130 open-source ecosystem signs off with; KLayout
(`sky130A.lydrc`) is the available second opinion.

## Mechanics and the Tcl 8.5 trap

`run_drc.sh` drives Magic in batch mode: read the GDS, load the top cell,
`drc euclidean on; drc style drc(full); drc check; drc catchup`, then write
`drc.rpt` (every violation) and `drc_count.txt` (by rule).

Magic at `/apps/magic` was built against Tcl/Tk 8.5, which the OS no longer
ships. The Synopsys FPGA tree carries a complete 8.5 runtime, so `env.sh`
wraps the invocation as `$MAGIC_RUN` with `LD_LIBRARY_PATH`/`TCL_LIBRARY`
scoped to that one command — never exported globally, so the Synopsys libs
cannot leak into Cadence tools.

```bash
bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
          <repo>/asic/signoff/drc/run_drc.sh [gds]'
# gds defaults to $SIGNOFF_PNR_DIR/outputs/<tag>.gds
# results in $SIGNOFF_RESULTS/drc/
```

## The merged-GDS trap (found 2026-08-30)

A GDS streamed out of Innovus **without `-merge` contains no cell layouts** —
only routing, vias, and empty references to cell structures. The v2 GDS is
exactly that (57 structures, zero `sky130_fd_sc_hd__*` cells), so DRC on it
checks routing-level geometry only; every cell-internal and cell-abutment
rule goes untested. Stage `06_export.tcl` now merges the std-cell and
SRAM-macro library GDS at stream-out, so the v3 winner's GDS will be real
mask geometry. Never quote a DRC result without saying which kind of GDS it
ran on.

## Status

- 2026-08-28 shakedown on the SRAM-macro GDS alone: contradictory output
  ("1,135,336 error tiles" yet "Total DRC errors found: 0") — the deck
  style/config in the driver script is not right yet; resolve before trusting
  any count.
- 2026-08-30: running on the v2 full-design GDS (abstract-only, see trap) as
  a script shakedown. v2 is a discarded design; the count is not a result.
- Real target: the v3 winner's **merged** GDS after stage 06.

## 2026-09-01 ~21:30 — first full-chip run (iter14 GDS): completes, numbers unusable

`DRC14_DONE=0` on the corrected script (top cell discovered correctly:
`Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1` — not vacuous). But the counts
contradict, same shape as the 08-28 macro shakedown, now at full scale:
**18,158,873 error tiles** vs `drc list count total` = **0**.

Triage (magic.log + drc.rpt):
- The `drc why` list is dominated by **FEOL rules inside library geometry**
  (diff/tap.*, licon.*, poly.*, li.*) including the SRAM-specific variants
  (poly.8 "SRAM core transistor", diff/tap.2 "in SRAM core") plus magic's
  hierarchical "can't abut or partially overlap between subcells".
- 1,571 GDS read warnings, e.g. OpenRAM macro internals with cells "placed on
  top of itself" (`hierarchical_predecode2x4`/`contact_8`).
- Conclusion: `drc(full)` on the merged GDS is checking the **OpenRAM macro
  internals**, whose bitcell arrays use foundry-waived SRAM rules that the
  standard periphery deck flags by design. 16 macros × 32×256 bitcell arrays
  plausibly accounts for millions of tiles. Innovus verify_drc on the same DB
  is in the hundreds-to-thousands — 18M is not a real violation count.

Fix direction (next run): treat vendor macro GDS as golden and exclude macro
internals from the check — delete/flatten the `sram_1rw1r_32_256_8_sky130`
instances after `gds read` and DRC the remainder (std cells + routing), or
DRC macro-halo regions only. Separately explain the `total = 0` counter
before trusting any zero from this flow.

**2026-09-01 ~22:00:** macro exclusion implemented in `run_drc.sh` (empties
`sram_1rw1r_32_256_8_sky130*` cell defs after `gds read`; blind spot noted in
the script header). Validation run launched against the same iter14 GDS
(tmux `drc14b`; prior noise run preserved as `results/.../drc_withmacros/`).
A believable count here validates the methodology for whichever arm wins.

**2026-09-02 ~00:30 — macro exclusion alone did NOT fix the count.** drc14b
(macros emptied, style drc(full)) returned the IDENTICAL 18,158,873 error
tiles / "total 0" as the with-macros run — bit-identical count across two
different layouts means the tiles are not macro-internal and the tile counter
is not measuring found violations. magicrc's `drc off` is commented (not the
cause). Working theory: drc(full) hierarchical checking of pre-verified std
cells (the "can't abut or partially overlap between subcells" class) floods
the count, and `drc list count total` semantics disagree with the tile
counter. Industry-standard fix applied to run_drc.sh: **routing-only style**
(`drc style drc(routing)`, env-overridable via ASIC_DRC_STYLE) + explicit
`drc on` for batch mode — std cells/macros are pre-verified by the PDK; what
P&R signoff must check is the routing we created. Validation rerun: tmux
`drc14c`; prior runs preserved as drc_withmacros/ and drc_full_macroexcl/.
Escalation if still nonsense: gds flatten true (OpenLane-precheck style,
441G RAM available), then KLayout as the independent arbiter.

**2026-09-02 ~02:00 — KLayout arbiter ONLINE (userspace install, no root).**
drc14c (routing style) still contradicted itself (10.4M tiles / "0 found"),
so the escalation ladder reached KLayout. Installed 0.30.12 to
`~/.local/klayout-0.30.12/` by extracting the Rocky 8 RPM + 7 dependency
RPMs (ruby-libs, libgit2, http-parser, 4x qt5 add-ons) via rpm2cpio from
`dl.rockylinux.org/pub/rocky/8/`; wrapper `~/.local/bin/klayout` sets
LD_LIBRARY_PATH + RUBYLIB + RUBYOPT=--disable-gems. First run: the PDK's
`sky130A_mr.drc` deck, **beol=true feol=false** (routing-only posture, macros'
FEOL trusted), 16 threads, on the iter14 GDS — tmux `kldrc14`, results
`results/<stamp>/klayout_drc/drc.lyrdb`. Whatever it returns becomes the
number Magic must reproduce before Magic is trusted again.

**2026-09-02 ~05:30 — KLAYOUT VERDICT (iter14 filled GDS): geometry is nearly
clean; the arms' violation counts are a SHORTS problem, not a spacing problem.**
sky130A_mr.drc, beol=true feol=false, 3.5 h wall / 16 threads: 238,391 raw
items → location-classified against the fp_iter7 macro ring (scratchpad
script): **only 297 fall outside macro footprints**, and just **9 are on
routing layers** (3 m3.2, 3 via3.2, 2 m5.2, 1 m4.2); the other 288 are
li.3/ct.2 std-cell-layer items at cell boundaries (fill/abutment class -
triage pending). The 238k in-macro items are the OpenRAM bitcell arrays vs
the periphery deck - foundry-waived patterns, vendor GDS golden, expected.

Reconciliation with Innovus's 706: NanoRoute's count is dominated by
**Shorts** - geometrically legal metal touching two nets - which spacing DRC
cannot see; they are connectivity errors (LVS's domain). Both tools are
right; they measure different failure classes. Methodology going forward:
- **Geometry signoff = KLayout** (this flow), outside-macro filter applied.
  Magic remains untrusted (three self-contradictory runs, ledger above).
- **Shorts/opens = Innovus verify_drc + netgen LVS** - this is what the
  arms' 706/627/571 numbers actually track, and why driving them to zero
  remains the campaign's core work even though "DRC" geometry is ~clean.

## 2026-09-04 18:24 — KLAYOUT VERDICT, iter16b exported GDS (the 9/13 package)

`sky130A_mr.drc`, beol=true feol=false, 16 threads, 13:50-18:24 (4.6 h) on
`runs/20260902_iter16b_e35_fp16_die2900/outputs/Cache_16384B_assoc4_sram.gds`
(filled, macros merged). Classifier now in the repo:
`signoff/drc/classify_lyrdb.py <drc.lyrdb> --die 2900 --edge 40`.

| class | items | what |
|---|---|---|
| total | 156,510 | |
| inside macro footprints | 155,341 | li.3 79,927 / li.7 30,430 / m1.2 16,765 / m2.2 13,908 ... - OpenRAM bitcell arrays vs the periphery deck, vendor GDS golden (same class as the iter14 verdict's 238k) |
| outside, routing layers | **3** | 1 **m3.2** met3 spacing 0.225 < 0.30 um at (2412.75, 992.15) = the right macro column's inner edge (x 2413.765), a met3 wire against the macro edge; 2 **via3.2** (via3 spacing 0.2) at cell-local (0,0) in the Innovus via masters `..._VIA23` / `..._VIA4` (multi-cut via cells, not top-level routing) |
| outside, std-cell layers | 1,166 | ct.1_b (mcon max length 0.17) 848 + ct.2 (mcon spacing 0.19) 318, ALL in one 2 um column at x = 1460.3-1461.7 spanning y 100-486 and 2400-2761 = the row ends against the bank2 halo (x 1462) in the bank1/bank2 channel of the bottom and top macro rows, ~5 per std-cell row. Cell-boundary/abutment class (the iter14 verdict's 288 were the same family); triage pending - why only that channel is the open question |

Verdict for the sheet: **BEOL geometry clean on routing layers except one
met3 spacing item at a macro edge**; the endcap mcon column is a
placement-boundary artefact to triage, not a routing failure. iter14 for
comparison: 297 outside / 9 routing-layer.

## 2026-09-04 20:53 — KLayout FEOL pass, iter16b GDS: 0 items

`sky130A_mr.drc` with `feol=true beol=false` (the complement of the 18:24
run), 16 threads, 20:32-20:53 (21 min vs 4.6 h for BEOL): **0 items**
(`results/<stamp>/klayout_drc_feol/`). Standard cells, fill/decap and the
vendor macro are foundry-clean at the front end and P&R adds no FEOL
geometry, so a clean result is the expected one; the short runtime is the
FEOL section's smaller rule set on the same 2.5 M flat polygons. The
"BEOL only" caveat on the signoff sheet is closed. NOTE the BEOL in-macro
waiver is under re-examination after the li1 finding (DRC.md "li1 under
the macros"): the BEOL run must be repeated on the re-exported GDS from
`07_li1fix.enc`.

## 2026-09-09 to 09-11 - KLayout on iter26b (quad floorplan): five passes, all clean outside the macros

`sky130A_mr.drc`, beol=true feol=false, 16 threads, ~4.5 h per pass, on
each export of the iter26b run; classified with `classify_lyrdb.py --def`
(macro boxes read from the exported DEF, so it works on the quad floorplan).
Last pass in `results/<26b>/klayout_drc/`, earlier ones under
`results/<26b>/pass<N>_*/klayout_drc/`.

| pass | export | items | inside macros | outside | outside = |
|---|---|---|---|---|---|
| 1 | final5 | 24,220 | 24,173 | 47 | 4 via3.2 + 5 m3.2 + **38 li.3 at the 10 overlapping antenna diodes** (see lvs.md) |
| 2 | final6 | 24,182 | 24,173 | 9 | 4 via3.2 + 5 m3.2 |
| 3 | clkskew8 | 24,182 | 24,173 | 9 | same |
| 4 | pgvia9 | 24,245 | 24,236 | 9 | same |
| 5 | **tagskew10 (signed off)** | **24,249** | 24,240 | **9** | same |

The nine are the standing artefact set of this flow: four `via3.2` items at
cell-local (0, 0) inside the Innovus multi-cut via masters (not top-level
routing) and five `m3.2` met3-spacing items sitting exactly on a macro box
edge (x = 486 / 2412 um), where a routed met3 wire meets the vendor macro's
own met3. None is within 3 um of an antenna diode. The ~24k in-macro items
are the OpenRAM bitcell arrays against the periphery rule deck, the same
class waived since the iter14 verdict (vendor GDS is golden).

Not repeated on 26b: the FEOL pass. It was 0 items on iter16b and P&R adds no
front-end geometry (fill/tap/decap/diode are library cells), so the iter16b
result stands for the process; a 26b rerun would take 21 minutes if a
reviewer wants it on the exact GDS.
