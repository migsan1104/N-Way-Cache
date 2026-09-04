# Voltus — power integrity (IR drop / EM)

**Status: not started. Investigated 2026-08-31 (read-only); the work plan
below is executable as written.** Tool is installed and licensed at
`/apps/cds/ssv231` — the same SSV tree as Tempus, exported as `SSV_HOME` by
`../env.sh`. Commands marked *(expected form)* have NOT been run on this
install; treat the first execution of each as a shakedown, the way
`quantus.md` and `tempus.md` record theirs.

## What Voltus is

Cadence's power-integrity signoff engine. Two questions timing signoff
cannot answer:

- **IR drop** — the PG grid has resistance; cells far from stripes see less
  than the nominal supply. Timing libs assume 1.60/1.76 V *at the cell*; if
  the grid sags 5-10 %, every delay in the STA is optimistic. Static IR uses
  average currents; dynamic IR simulates switching windows.
- **Electromigration** — current density limits on wires/vias; a stripe that
  is electrically fine can still wear out.

This is the check that validates stage 02's ring/stripe choices (widths,
spacing, met5 sharing) rather than taking them on faith.

## Why THIS design needs it — two independent reasons

**1. It can invalidate the timing conclusion we are fighting for.**
Iteration 7's own `reports/route/power.rpt` at setup_view (1.76 V):

| | mW | share |
|---|---|---|
| internal | 700.6 | 64.5 % |
| switching | 385.3 | 35.5 % |
| leakage | 0.15 | 0.01 % |
| **total** | **1086.1** | — |
| (clock group) | 134.1 | 12.35 % |

1086 mW at 1.76 V is **~617 mA average** drawn across a 2.7 mm die. A typical
static-IR budget is 1-3 % of VDD (17-53 mV here); a 5 % sag costs roughly
7-10 % of path delay, which on the 4.000 ns SDC is **200-400 ps**. The whole
campaign is arguing over WNS between -0.714 and -1.272 ns. **IR drop is the
same order as the margin being fought over**, and every number quoted so far
assumes a perfect supply.

**2. It may hand back routing tracks — i.e. it is a congestion lever.**
The PDN was built in stage 02 and has never been validated. `DRC.md`
hypothesis 1 (still open) is that met5 stripes eat the horizontal supply the
design is starved of, and horizontal overflow is always our worse direction.
Voltus settles it in the only rigorous way:

- grid **over-provisioned** → thin the stripes, give met5 tracks back to
  signals: a principled attack on the actual blocker instead of another
  blockage guess;
- grid **marginal** → the PDN is not a lever, stop considering it, and stop
  treating hypothesis 1 as open.

Either answer is worth having, which is what makes this cheap.

## Measured inputs that already exist (checked 2026-08-31)

| input | state |
|---|---|
| routed database | `05_route.enc` in iterations 7, 9, 11 (+ `05_route_repaired.enc` for 7) |
| exported DEF/GDS/netlist | produced by `PnR/export_route.sh` (iteration 7 first, 2026-08-31) |
| std-cell power tables | **present** — 9,152 `internal_power`/`leakage_power` groups in `sky130_fd_sc_hd__ss_n40C_1v76.lib` |
| metal sheet resistance | in tech LEF: li1 12.8, met1/met2 0.125, met3/met4 0.047, met5 0.0285 Ω/sq |
| switching activity | Innovus `report_power` default estimate today; a real VCD/TCF from `Test_Complete` would be better |
| macro PG pins | declared — `pg_pin(vdd)` / `pg_pin(gnd)` with `voltage_name VDD/GND` |
| macro power model | **THIN — see gaps**: 11 power groups and `default_cell_leakage_power : 0.0` |

## What we need to do — the work plan

### Step 0 — prerequisites (blocking)
- A routed database worth analysing. Iteration 7's is the current best and is
  sufficient for the *static* question; it does not need to pass the DRC gate
  first, because IR drop does not care about metal shorts between signal nets.
- `source /apps/settings && source asic/PnR/innovus/env.sh && source asic/signoff/env.sh`
  with `SIGNOFF_PNR_STAMP=<run stamp>` so `SIGNOFF_PNR_DIR`/`SIGNOFF_RESULTS`
  point at that run (same pattern the Tempus flow uses).

### Step 1 — power-grid views (PGVs) — THE REAL WORK
sky130 ships no vendor PGVs, so they must be generated once from the cell
views and then reused by every later run.

*(expected form)*
```tcl
set_pg_library_mode -celltype techonly \
    -extraction_tech_file <qrc tech> \
    -temperature 25 -default_power_voltage 1.76
generate_pg_library -output <dir>/techonly.cl
# then the standard-cell PGVs from LEF/GDS/SPICE:
set_pg_library_mode -celltype stdcell -spice_models ... -spice_subckts ...
generate_pg_library -output <dir>/stdcell.cl
```
Notes for this PDK: the SPICE, GDS and LEF the `stdcell` path needs all exist
under `libs.ref/sky130_fd_sc_hd/{spice,gds,lef}`. The extraction techfile can
be the one Quantus validated (`../quantus/techfiles/sky130A_nom.tch`) — the
same caveat applies (validated for signal-width wires, **not** for the wide
straps a PG analysis mostly cares about; see gaps).
**Budget: this step is hours-to-a-day of shakedown. Everything after it is quick.**

### Step 2 — static rail analysis (the cheap, decisive run)
*(expected form)*
```tcl
set_power_analysis_mode -method static -corner max \
    -analysis_view setup_view
set_power_output_dir <out>
set_rail_analysis_mode -method static -accuracy hd \
    -power_grid_library {<dir>/techonly.cl <dir>/stdcell.cl}
set_power_pads -net VDD -format xy -file <pads.txt>   ;# or -vsrc from the ring
analyze_rail -type net {VDD VSS}
report_rail -output <out> -type net {VDD VSS}
```
The `set_power_pads` step needs a decision we have never made: **where the
supply enters the die**. There is no package/bump model in this project, so
either declare the PG ring edges as the sources (defensible for a block-level
study) or place notional pads and say so in the report.

### Step 3 — read the result against a budget
- Worst instance voltage and the IR map. Budget: **≤ 3 % of 1.76 V ≈ 53 mV**
  static drop; under ~1.5 % is comfortable.
- Where the drop is: if it concentrates in the hub (where iterations 5-9 piled
  cells) that is a second, independent argument for the blockage recipe.
- EM: current density per stripe/via versus the sky130 limits.

### Step 4 — the answer that feeds the congestion fight
Compare drop against budget and decide the met5 question:
- comfortable → propose a thinner stripe plan in stage 02, re-run
  place+route, and measure whether horizontal overflow improves. That becomes
  a numbered iteration with the PDN as its single variable (the "G7c" slot
  that was defined and never run).
- marginal → close `DRC.md` hypothesis 1 as answered-negative.

### Step 5 — dynamic IR and decap ECO (only if static is marginal)
Dynamic needs real activity: a VCD/TCF from a gate-level run of
`Test_Complete` traffic, which the verification flow can produce but never has.
That is a second day of work; do not start it unless step 3 says static drop
is near budget.

### Step 6 — close the loop into STA (what makes it signoff)
The point of the exercise: analyse timing at the voltage each cell actually
sees, instead of assuming nominal.
- Voltus writes per-instance voltage;
- Tempus consumes it (voltage-aware / IR-derated STA) and re-reports WNS.
That converts "-0.714 ns assuming a perfect supply" into a defensible number,
and it is the same shape of correction as the macro derate in `mmmc.tcl`.

## The ECO story

Voltus does not only report; three kinds of fix come out of it:

1. **PG ECO** — add or widen stripes, add vias where current density is high.
   Physical, applied in Innovus, then re-route.
2. **Decap insertion ECO** — the standard automated remedy for *dynamic* IR;
   Voltus identifies where charge is needed and the filler/decap insertion is
   redone accordingly. (Note stage 06 already inserts fillers — decap-aware
   filler is a variant of that step, not a new one.)
3. **Power-aware placement/timing ECO** — Innovus can read rail results and
   avoid packing high-switching cells into a sagging region; Tempus can ECO
   against IR-derated timing. This is the loop of step 6.

For this project, ECO type 1 is the realistic one, type 3 is the valuable one,
and type 2 is out of scope until dynamic analysis exists.

## When — sequencing against the 2026-09-13 deadline

Definition of done is "clean 200 MHz STA signoff + DRC/LVS documented", so the
order stays:

**gate-passing route → Tempus STA → Magic DRC + netgen LVS → Voltus.**

One justified exception: **static IR on iteration 7's existing routed
database**, because it needs no new route, and its answer (met5 relief, yes or
no) feeds the congestion campaign that is currently the critical path. Do it
when a lull appears in the P&R queue, not by displacing an iteration.

## Known gaps — attach these to any result we quote

1. **The SRAM macro power model is nearly empty**: 11 power groups versus
   9,152 for the standard-cell library, and `default_cell_leakage_power : 0.0`.
   PG *connectivity* is fine (pins declared), but macro *current* will be badly
   estimated — and 16 macros ring the die, exactly where IR matters. Any IR
   number carries this caveat, the same way timing carries the ×1.5 macro
   derate.
2. **No CPF/UPF** in sky130 → the generated-PGV path is mandatory, and PGV
   quality is only as good as the cell SPICE/GDS.
3. **The Quantus techfile is validated for signal-width wires only** — PG
   analysis is dominated by wide straps, which are the part `quantus.md`
   explicitly marks unvalidated (50 µm plates extrapolate past the Techgen
   width tables). Either accept the caveat or extend the techfile validation
   to strap widths first.
4. **No package/bump model** → the supply entry point is an assumption, not
   data (step 2).
5. **Licence contention** — Voltus shares the SSV tree with Tempus; do not run
   both against a full P&R queue.

## Log

- **2026-09-04 15:00** - first execution of step 1 (`run_pgv.sh`,
  `pgv_common.tcl` / `pgv_techonly.tcl` / `pgv_stdcells.tcl`). Voltus
  23.14 (ssv231) checked out `vtsxl`; licence allows 8 CPUs. `techonly`:
  437 cells, TECH view 100%, ~40 s -> `pgv/techonly/`. `stdcells` started
  15:01 (Spectre bundled in ssv231, corner `tt`, VPWR 1.76 V, bulk
  VPB/VNB declared, 25 C) -> `pgv/stdcells/`; log `pgv/logs/stdcells.log`.
  Decisions: 1.76 V not 1.8 (campaign corner); `tt` models (PGV cap/leak
  are corner-insensitive at the level the static run needs); no
  `-lef_layermap` (auto-generated). Next: step 2 static rail on iter16b
  `06_final.enc`, supply entry = PG ring edges, declared as such.

## First static IR result: iter16b, 2026-09-04 16:10 (attempt 7 of 7)

Flow that finally ran (`static_rail.tcl` / `run_static_rail.sh <stamp>`):
`read_lib -lef` -> `read_view_definition mmmc.tcl` -> `read_verilog` ->
`set_top_module` -> `read_def` (the export DEF) -> `globalNetConnect` ->
`read_spef` -> static power (vectorless, activity 0.2) -> `set_pg_nets`
(3 % threshold) -> `set_rail_analysis_mode -method static -accuracy xd
-power_grid_library techonly.cl` -> `set_power_pads -format xy` -> one
`analyze_rail -type net <n>` per net. Six earlier attempts and their lessons
are in `../WALKTHROUGH_2026-09-04.md` section 8 (restoreDesign loses the
floorplan across Innovus 21 -> Voltus 23; `init_design` puts Voltus into
timer mode where DEF is ignored; `analyze_rail -type net` takes one net;
report names are `static_<net>.ptiavg` only after the rails are connected).

Supply model: **the PG ring is the supply** - 228 ideal sources per net at
50 um pitch on the ring centrelines (no package exists). With only one
source per side the ring itself dropped 0.22 V (VDD 275 mV worst) - that
run is kept as `results/<stamp>/voltus_attempt6_4sources/` as the
"entry-point artefact" reference.

| net | worst | average | budget (3 %) | nodes over budget | drop in met5 (ring) | drop met4..met1 |
|---|---|---|---|---|---|---|
| VDD | 119 mV (1.641 V) | 78 mV | 53 mV | 542k / 784k | 0.2 mV | 118 mV |
| VSS | 121 mV | 80 mV | 53 mV | 543k / 784k | 2.9 mV | 121 mV |

Worst hub cell: ~1.52 V effective (13.6 % lost). **FAIL against the 3 %
budget, 2.2x over; also over a 5 % budget.** Total static current 325 mA
on VDD (850 mW at 1.76 V incl. macros; power at default activities, SPEF
not applied to the switching term - see caveats).

Where (ir_linear.gif): everything outside the macro ring within 1 % of
nominal; the ENTIRE hub inside the macro ring in the worst band; gradients
only at the four diagonal corner gaps. The macro ring walls the hub off and
current reaches it through the corners. The 96 met5 + 311 met4 stripe
segments feed the periphery fine.

Consequences:
1. **DRC.md hypothesis 1 (met5 over-provisioned, thin it for tracks) is
   answered NEGATIVE.** met5 carries no drop; the PDN is under-provisioned
   into the hub, not over-provisioned at the top.
2. **iter17 PDN item:** met5 straps across the macro ring from the perimeter
   into the hub with via stacks to the hub's met4 stripes, in 02_power.tcl
   before placement. Trial it with Voltus what-if stripes on this database
   first (one re-route, not several).
3. EM: NOT analysed. The Quantus techfile has no EM rules, so the "0
   current-density violations" line is empty, not clean. Needs sky130 Jmax
   per layer in the ICT (`-process_techgen_em_rules`) or an `-em_models`
   file.

Caveats attached to the numbers: (a) macros excluded (no PGV: Spectre
rejects the ngspice models; LEF-only macro view died on an internal
assertion) - 16 SRAMs, ~157 mA, on the channel edges -> interior is
optimistic; (b) standard cells at LEF-based accuracy (xd), not
characterised; (c) vectorless activity 0.2; (d) switching power without
SPEF; (e) sources ideal (no package R/L); (f) grid at 100 C, cells at the
n40C_1v76 libs.
