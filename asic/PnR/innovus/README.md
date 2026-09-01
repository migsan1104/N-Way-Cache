# Innovus place-and-route

RTL-to-GDSII back end for the cache. Cadence-only from 2026-08-24: Genus for
synthesis, Innovus for PnR. The Design Compiler flow (`asic/run_dc.sh`,
`asic/synthesis/synopsys/`) is retired — see "Deferred decisions" below.

**NOTHING HERE HAS BEEN RUN.** Not one line of this has been through Innovus.
The flow structure, the corner strategy and the sky130 specifics are researched
against this PDK and this design, but individual command options vary between
Innovus versions, and the first real session should be treated as a syntax
shakedown, not a result. Run it stage by stage (`source scripts/00_init.tcl`,
then `01_...`) and expect to fix option names; the staged databases exist so
that fixing one does not cost the stages before it.

Signoff target is **ASSOC=4 only** (decided 2026-08-24) - `innovus_config.tcl`
defaults to it, and only the 32x256 macro is ever instantiated.

## Layout

```
asic/PnR/
  innovus/
    scripts/
      00_init.tcl            LEF/netlist/MMMC -> init_design
      01_floorplan.tcl       die/core, 16-macro placement, halos   <- judgement
      02_power.tcl           globalNetConnect, rings, stripes, sroute
      03_place.tcl           taps + endcaps, placeDesign
      04_cts.tcl             ccopt_design, propagated clock, postCTS opt (hold becomes real)
      05_route.tcl           routeDesign -> DRC gate -> postRoute opt (quotable numbers)
      06_export.tcl          fill, verify, extract, GDS/netlist/SPEF/SDF
      innovus_config.tcl     config: paths, corners, macro source, sky130 cells
      mmmc.tcl               two MMMC corners + asymmetric macro derates
      run_innovus.tcl        driver; ASIC_PNR_FROM / ASIC_PNR_TO select stages

    constraints/
      pnr.sdc                PnR constraint mode (sources golden.sdc)

    runs/                    stamped runs (set ASIC_PNR_RUN_STAMP)
    reports/                 current run    } written directly by the flow
    checkpoints/             current run    } when no stamp is set
    outputs/                 current run    }
```

Scripts and constraints are tracked; `runs/`, `reports/`, `checkpoints/` and
`outputs/` are gitignored.

**Overwrite warning.** With no stamp set, the flow writes straight into the
top-level `reports/`, `checkpoints/` and `outputs/`, and the next run
**overwrites them**. For anything whose numbers get quoted - or any two
configurations you want to compare - set a stamp:

```
ASIC_PNR_RUN_STAMP=20260824_a4_baseline innovus -files scripts/run_innovus.tcl
```

which redirects the whole tree into `runs/<stamp>/` instead.

### Why optimisation is split from placement/CTS/route

Six structural stages, four optimisation stages. The split exists so opt
settings can be retuned without re-running the structural step underneath -
`ASIC_PNR_FROM=08` re-optimises without re-routing. Given how much this campaign
iterates, that is worth more than the alternative.

The trade-off is on the record in `03_place.tcl`: `place_opt_design` does
placement and pre-CTS optimisation as one integrated step and generally gets
better QoR than `placeDesign` + `optDesign -preCTS`. If a run is close on setup
and needs the last few ps, collapsing stages 03+04 back into `place_opt_design`
is a legitimate move.

Optimisation stages always do **setup first, then hold**. Hold fixes insert
delay buffers, which can only hurt setup; fixing setup afterwards would undo
them. Not interchangeable.

Each stage saves `checkpoints/<NN>_<name>.enc` and can be restarted on its own. To resume
mid-flow you must pin the run stamp, or the stage lands in a fresh empty run
directory and finds no database:

```
ASIC_PNR_RUN_STAMP=<stamp> ASIC_PNR_FROM=05 innovus -files scripts/run_innovus.tcl
```

Each run works inside its own `work/` dir so concurrent runs cannot corrupt
each other — the same discipline as `run_genus.sh`.

## Inputs (all produced already)

Per Genus run, under `asic/PPA/genus/assoc_<N>/runs/<stamp>/netlist/`:
  - `Cache_<size>B_assoc<N>[_sram]_mapped.v`    the gate netlist
  - `..._mapped.sdc`                            constraints as mapped

Plus the PDK views resolved by `project_config.tcl`: tech LEF, standard-cell
LEF, macro LEF, and the timing libs.

## Corners (MMMC)

| View | Process | V | T | Stdcell lib | Macro lib |
|---|---|---|---|---|---|
| setup | SS | 1.60 | 100 C | `sky130_fd_sc_hd__ss_100C_1v60` | see macro note |
| hold | FF | 1.95 | -40 C | `sky130_fd_sc_hd__ff_n40C_1v95` | see macro note |

The setup corner is unchanged from synthesis — it is the project's signoff
corner and its derivation is documented in `golden.sdc`. The hold corner is the
conventional opposite: fastest silicon, coldest, highest supply. sky130 shows no
temperature inversion at these voltages (measured, see `golden.sdc`), so cold is
genuinely the fast corner here.

### Macro libs — the one real decision

A4 binds **16 instances of the 32x256 macro**. Two options, and MMMC needs a lib
on BOTH sides:

- **Vendored** (`sram_1rw1r_32_256_8_sky130`): `SS_1p8V_25C` and `FF_1p8V_25C`
  both exist, so hold works today. But neither matches the stdcell corner's V/T,
  so both sides carry a derate: the x2.0 late derate on setup (documented in
  `asic/MACROS.md`) and an invented early derate on hold.
- **OpenRAM** (`asic/openram/macros_out/32x256/`): characterized AT the setup
  corner (SS/1.60V/100C), which is the entire reason it was generated - it
  retires the setup derate. **There is no FF characterization**, so hold has no
  lib until one is run (~26 h, config-only change, separate `output_path`).

Whichever is chosen, it is a variable in `innovus_config.tcl`, not a hardcode.

### Derate asymmetry — easy to get wrong

Genus applies `set_timing_derate -late 2.0` to the macro instances. Under MMMC
that is a *setup-corner* statement. The hold corner needs an EARLY derate
(< 1.0) on the same instances, and it is a different number. Applying only the
late derate makes hold silently optimistic — the failure mode that does not show
up as an error, only as a chip that does not work.

### RC corners — a PDK limitation, not a choice

This PDK ships **no QRC tech file and no captable** (only OpenRCX and Calibre
rules, neither of which Innovus reads), so `create_rc_corner -qx_tech_file` is
unavailable. RC corners are therefore defined by temperature plus RC scaling
factors (`-T`, `-preRoute_res/cap`, `-postRoute_res/cap`), with LEF-based
extraction. This is the honest ceiling of what the PDK allows; treat extracted
numbers accordingly and say so when quoting post-route results.

## Constraints

`golden.sdc` stays the synthesis constraint file and is deliberately pre-CTS:
setup uncertainty 0.250, **no hold uncertainty**, ideal clock. Its own comments
defer both to CTS. `constraints/pnr.sdc` is the PnR mode: it sources
`golden.sdc` and adds what the back end needs (hold uncertainty; propagated
clock after CTS). The synthesis file is not edited — both flows keep reading one
authoritative source.

## Flow stages

Renumbered 2026-08-30 after combining opt stages into their structural stages
(old 03+04 -> 03, 05+06 -> 04, 07+08 -> 05, 09 -> 06). Run-1/v2 artifacts on
disk keep the OLD numbers; `scripts/retired/` holds the old split scripts.

| # | Stage | Does | Key point |
|---|---|---|---|
| 00 | init | LEFs, netlist, MMMC, `init_design` | dont_use + macro derates applied here |
| 01 | floorplan | die/core, **16-macro placement**, halos | the stage that needs judgement |
| 02 | power | globalNetConnect, rings, stripes, sroute | sky130 PG names — the classic trap |
| 03 | place | taps + endcaps FIRST, then `place_opt_design` | integrated placement + preCTS opt (03+04 combined 2026-08-30; **setup only** — clock is still ideal); ends with the preCTS comparison reports |
| 04 | cts | `ccopt_design`, propagated clock, uncertainty swap, then `optDesign -postCTS`/`-hold` | first honest hold number; tree checkpointed (`04_cts_raw.enc`) before opt |
| 05 | route | `routeDesign` -> checkpoint -> **`verify_drc` gate** (`ASIC_DRC_GATE`, default 2000) -> `optDesign -postRoute`/`-hold` | above the gate opt is skipped - v2 measured opt-on-DRCs at x5.5 violations, -12.8 -> -22 ns |
| 06 | export | fill, verify, extract, write deliverables | LEF-based extraction (see RC corners) |

## sky130 traps to pre-wire (each one costs hours if discovered live)

- **PG pin names are not VDD/VSS.** Standard cells use `VPWR`/`VGND` plus the
  bulk pins `VPB`/`VNB`; the SRAM macros use `vccd1`/`vssd1`. All four need
  explicit `globalNetConnect`. Confirm the bound macro's LEF pin names — the
  1kbyte/2kbyte variants use `vccd1`/`vssd1`; verify the one actually linked.
- **Well taps are mandatory** (`sky130_fd_sc_hd__tapvpwrvgnd_*`) at the
  max-distance rule, plus endcaps. Missing taps surface as DRC carnage at the
  end of a long run.
- **`lpflow_*` cells must stay excluded.** `run_genus.tcl` already excludes them
  (level shifters, isolation, some double-height); the same `dont_use` list must
  be carried into Innovus or place will use cells synthesis refused.
- **The `TT_1p8V_100C` macro lib is broken** (7.8 ns garbage, per
  `asic/MACROS.md`). Never link it, in any corner.

## Deferred decisions

1. **Shared-path refactor.** `project_config.tcl`, `golden.sdc` and the
   filelists live under `asic/synthesis/common/`, but they are not
   synthesis-specific — Innovus reads them too. They belong at `asic/common/`.
   NOT done yet: five Genus runs are in flight and those files are read lazily
   by running jobs (the live-edit trap that cost the macro16 reports on
   2026-08-20). Do the move when nothing is running.
   Until then `innovus_config.tcl` sources the file in place.
2. **`ASIC_FLOW` does not accept `innovus`.** `project_config.tcl` validates it
   against `{genus, dc}` and exits otherwise. Same live-edit reason: not touched
   yet. `innovus_config.tcl` therefore sources the config with the default flow
   and overrides the output tree itself. Fold `innovus` into the switch during
   the refactor above.
3. **Design Compiler retirement.** Cadence-only means `run_dc.sh`,
   `synthesis/synopsys/`, the `dc` branch of `collect_ppa.py`, and the DC
   references in `CLAUDE.md` and `asic/README.md` are dead. Nothing has been
   deleted — that is a call to make deliberately, not a side effect of adding a
   folder.

Floorplan history and the v3 plan: see [FLOORPLAN.md](../FLOORPLAN.md).
