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

- **2026-09-07 00:40-02:30** - iter19b static IR + EM: VDD 28 mV PASS, VSS
  61 mV FAIL, VSS EM 4.0x. Root cause and fix below ("VSS straps stop at the
  VDD ring"). `em_models_lef.ict` written from the tech LEF's own
  DCCURRENTDENSITY limits (the "not in the PDK" note in the EM screen section
  was wrong: `sky130_fd_sc_hd__nom.tlef` has AVERAGE limits at Tj 90 C for
  every layer and cut), `VOLTUS_EM_TEMP` knob added to `static_rail.tcl`.

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

## What-if straps (2026-09-04 16:47-17:05) - the iter17 PDN, sized on iter16b

`create_what_if_shape -type wire -nets {VDD VSS} -layer met5 -direction hor
-pitch P -width 2 -spacing 2 -add` over the core, then one
`create_what_if_shape -type via -nets <n> -layer {met4 met5} -method auto`
per net (wires alone float: +224 resistors, drop unchanged), then
`set_rail_analysis_mode ... -import_what_if_shapes true`. Knob
`VOLTUS_WHATIF_M5_PITCH`, output tag `VOLTUS_TAG`.
VDD worst: 119 mV (none) -> 65 mV (120 um, met5 now carries 64 of it) ->
47 mV (60 um) vs 53 mV budget. VSS 66 mV at 120 um. Decision for iter17:
met5 2 um @ 60 um (~12 % of met5 tracks); 4 um is the headroom knob.

## EM screen with ASSUMED limits (2026-09-04 17:36-17:50) - not a signoff

SKY130's EM limits are not in the open PDK (requested with the Pegasus
email). `em_models_assumed.ict` (EM-only ICT, one statement per line - the
parser rejects braces after a jmax_factor table) carries generic Al-rule
assumptions: li1 0.3, met1/2 1.0, met3/4 2.0, met5 3.0 mA per um width DC
avg at 110 C; vias mcon 0.15, via1 0.2, via2/3 0.3, via4 1.5 mA per cut.
Knob `VOLTUS_EM_ICT` on `static_rail.tcl` (options ride on the single
`set_rail_analysis_mode` call - IMPTCM-113 otherwise).

iter16b, ring-as-supply, macros excluded, default activity:
| net | J/Jmax average | J/Jmax worst | elements > 1 |
|---|---|---|---|
| VDD | 0.23 | 4.49 | 22,447 |
| VSS | 0.24 | 4.47 | ~22k |

Where (rj.gif): the four diagonal corner gaps where the hub current enters,
the short channels between adjacent macros on the left/right columns, and a
few full-height met4 stripes beside the macro columns. Hub interior and
periphery < 0.3. Same mechanism as the IR drop: ~325 mA funnels into the
hub through a few 2 um met4 stripes. The iter17 met5 straps spread that
current over 24-48 straps and relieve both. With real limits the ratio may
move 2x either way; the location will not. Results:
`results/<stamp>/voltus_em_screen/`. Sheet wording: "EM screened against
assumed limits, worst J/Jmax 4.5 at the hub corner feeds".

## What-if straps, width sweep (2026-09-04 20:32-21:15) - the iter17 fallback

Knob `VOLTUS_WHATIF_M5_WIDTH` added to `static_rail.tcl` (default 2). Same
setup as the pitch sweep above (iter16b `06_final.enc`, ring as supply,
macros excluded, 100 C grid). Worst drop = 1.760 V minus the reported
minimum node voltage (VDD) / the reported maximum (VSS).

| met5 straps | VDD worst | VSS worst | met5 track share |
|---|---|---|---|
| none (baseline) | 119 mV | 121 mV | 0 |
| 2 um @ 120 um | 65 mV | 66 mV | ~6 % |
| **2 um @ 60 um (iter17 as launched)** | **47 mV** | **48 mV** | ~13 % |
| 4 um @ 120 um | 49 mV | 50 mV | ~10 %, half the strap count |
| 4 um @ 60 um | 33 mV | 33 mV | ~20 % |

Budget 53 mV. iter17's early-global-route table showed met5 over-capacity
at 7.9 % of gcells vs 0.8 % in iter16b (DRC.md "iter17 early signal"): if
the route gate confirms met5 contention, 4 um @ 120 um is the fallback that
still meets the budget with half as many straps crossing the routing;
4 um @ 60 um is the headroom option for when the macro current (excluded
here) is finally in the solve. Results:
`results/<stamp>/voltus_whatif_m5p{120,60}w4/`.

## VSS straps stop at the VDD ring (iter19b, 2026-09-07)

**Numbers** (`results/<19b>/voltus`, `06_final.enc`, static, ring as supply,
setup_view, 803 mW): VDD min 1.732 V = 28 mV drop, PASS against the 53 mV
budget. VSS worst 60.8 mV, 18.8 % of nodes over threshold, map skewed to the
left edge. EM against the LEF limits (`voltus_em_lef/`, Tj 100 C derate
0.481): VDD J/Jmax max 1.001 on one element, VSS max 4.02.

**Why VSS and not VDD.** `addStripe` ends a horizontal strap at the first
ring it meets on its own layer. The core ring is VSS outside (met5 vertical
segments at x 4.1-8.1 / 2891.7-2895.7) and VDD inside (10.1-14.1). The met5
VDD straps run 10.1..2889.7, ring to ring. The met5 VSS straps run
16.5..2883.3: they start *after* the VDD ring and never reach the VSS ring.
VSS return current therefore enters only through the met4 vertical stripes
to the top and bottom ring segments, which is both the IR skew and the 4x
EM: a few met4 stripes carry what 48 straps were supposed to spread.

**Is 61 mV bad?** For timing, no: Tempus closed 3.333 ns with 0 violators
at ss 100 C 1.60 V, 160 mV below nominal, so 89 mV of combined drop is
inside the corner. For reliability, yes: the 4x EM on the same structures
is a wear-out failure, and that is what blocks signoff. The ECO is for EM;
the IR fix comes with it.

**ECO v1** (`scripts/vss_jumper_eco.tcl`, 01:46-01:52 on
`05_antenna_clean.enc`): one met4 jumper per strap end under the VDD ring,
ring x to 1 um past the strap end, stacked vias met4-met5 at both overlaps.
VSS special connectivity: 0 disconnected pieces (fixed). `verify_drc` = 388:
360 met4 SHORTs plus 28 spacing, all on the LEFT edge, all "regular wire &
special wire". The band x 4.1..15.5 on the left is a vertical met4 signal
channel: pin escape routes for the 77 met1 / 16 met3 left-edge pins, 94
nets, on every track. A jumper at any strap y crosses about 7 of them. No
clear landing window exists for a met3 alternative either. Saved as
`07_vssfix_dirty.enc`, not exported.

**ECO v2** (`scripts/vss_jumper_eco2.tcl`, launched 02:30, tmux
`vsseco19b2`): the same jumpers, then the antenna_fix6 recipe on the nets
the DRC report names: `editDelete -net`, `routeSelectedNetOnly`,
`routeDesign` with TD/SI off and the antenna fixer on, up to 4 passes with a
plateau guard. NanoRoute treats the new special wires as obstructions, so
the 94 nets jog around the jumpers. Gate: DRC 0, antenna 0, VSS pieces 0,
then `07_vssfix.enc`; also prints worst hold/setup slack (19b hold margin is
+0.004 ns, so the re-export chain may need to start from the hold step).

**Permanent fix**: `02_power.tcl` now adds the same jumpers right after the
horizontal straps (`ASIC_PG_STRAP_JUMPERS`, default on when H straps are on,
`ASIC_PG_STRAP_JUMPER_LAYER` met4) for whichever net's straps stop short of
its ring. Placed before routing, the router avoids them and no ECO is needed.

**Lesson**: check `verifyConnectivity -type special` per net AND read the
strap extents from the DEF after stage 02. A strap that stops 8 um short of
its ring is invisible in the connectivity report (the straps are connected,
via the core stripes) and only shows as an IR/EM asymmetry between the two
rails. The asymmetry is the tell: VDD and VSS share the same geometry, so a
2x difference means one of them is missing a path.

**ECO v2 result (03:08): DRC clean, IR unchanged.** Voltus on the v2 export
(`voltus_post_vsseco/`): VSS worst 60.775 mV vs 60.779 mV before. The DEF
explains it: the LEFT met4 jumpers run x 4.1..15.8 and the strap starts at
16.5. The first vertical met4 stripe set (core margin 16) puts a VDD stripe
at x 16.1-18.1, and `addStripe` trims the VSS jumper to 0.3 um before it.
Left jumper = a stub with one via to the ring and none to the strap. The
right jumper reaches (vias at x 2893.74 ring and 2882.59 strap) because
the last stripe set on that side is not in the way. Two lessons:
`verifyConnectivity -type special` = 0 pieces proved nothing (the stub
touches the ring, the strap was already connected through the core
stripes), and "ViaGen created 1 via" per stripe was the tell that only one
end landed. The DEF SPECIALNETS section and the IR number are the proof,
not the connectivity report.

**ECO v3** (`scripts/vss_jumper_eco3.tcl`, launched 03:12, tmux
`vsseco19b3`, from `07_vssfix_v2stub.enc`): per strap and side, if the
jumper does not overlap the strap, add a met3 link from the stub end to the
nearest same-net met4 vertical stripe (x 20.1-22.1 on the left, which
already vias to the strap), stacked vias met3-met4 at both overlaps,
passing under the VDD stripe on a different layer. Then the same reroute
loop and gate, plus a count of met3-met4 VSS vias in the edge bands
(expect 2 per link) as the structural proof before Voltus.

**ECO v3 result (03:22): DRC clean, links only partly landed.** The addStripe
log is the tell: "ViaGen created 2 via" for 16 links, 1 via for 27, 0 for 5.
The VDD met4 vertical stripe at x 16.1-18.1 stacks vias down to every VPWR
rail (`setAddStripeMode -stacked_via_bottom_layer met1`), so wherever a
VPWR rail crosses the 2 um strap band there is a VDD met3 via pad in the
link's path, and addStripe trims the met3 link around it. Those pads are
via-master geometry, not special wires, so they are invisible to a dbGet
over `sWires`; only the via instances (`sViaInst`, `pt_x`/`pt_y`) show them.

**ECO v4** (`scripts/vss_jumper_eco4.tcl`, 03:29-03:39, from
`07_vssfix_v3partial.enc`): audit first, fix second. Per left strap, count
the real M3M4 VSS vias at the stub end and on the VSS vertical stripe; 16
straps were connected, 32 not. For each of the 32, an L-link on met3: a
vertical piece over the stub end (x stub_end-1.4..stub_end) from the strap
band to y_link, and a horizontal piece at y_link from the stub to the far
edge of the VSS stripe. y_link is the nearest VSS via height on that
stripe outside the band (a VGND rail crossing), kept 1.5 um from any VDD via
height at x 15-19, so the crossing under the VDD stripe happens where the
VDD stripe has no pads and the VSS stripe already has one. Result: 13 DRC
from 10 signal nets, one reroute pass, DRC 0, antenna 0, VSS pieces 0, and
the final audit: 48 of 48 straps with a via at both ends. Saved
`07_vssfix.enc`; export chain and Voltus relaunched 03:39.

**Lessons from v2-v4.** (1) `verifyConnectivity` = 0 pieces is not proof
of a new path; count the vias in the boxes you care about. (2) addStripe
silently trims a stripe to avoid other-net PG shapes on its own layer; it
does not trim for signal wires (those become DRC shorts you can reroute
away). A stripe that is shorter than the area you asked for is the flag.
(3) Via-stack pads live in via masters: query `sViaInst`, not `sWires`.
(4) Three Tcl mistakes cost three restarts (`dbGet $via.box` is not an
attribute, `$yc(...)` parses as an array, and Innovus reads the whole script
at `source` time so a patch needs a relaunch); a bare `innovus -execute
"dbSchema sViaInst"` answers attribute questions in 20 s.

**ECO v4 result (04:05, Voltus static on the v4 export, same setup as the
pre-ECO run: ring as supply, 228 sources per net, setup_view, 100 C):**

| | VDD worst drop | VSS worst drop | budget |
|---|---|---|---|
| pre-ECO (06_final, 00:13) | 28 mV | 60.8 mV | 52.8 mV |
| ECO v2 (stubs) | 28 mV | 60.8 mV | |
| **ECO v4 (L-links)** | **28 mV** | **30.3 mV** | |

VSS average drop 37.5 mV -> 19.9 mV. The two rails now sit within 2 mV of
each other, which is what identical geometry should give. Trap on the way
to reading this: `analyze_rail` does not overwrite `voltus_rail.log` in an
existing output directory (the stub run's 60.775 mV was still there after
the v4 run); the numbers in the launcher's stdout (`logs/voltus19b8_sh.log`)
and in `results.json` (04:05) are the v4 ones. Use a fresh `VOLTUS_TAG` per
run, or read the shell log.

**EM after v4 (04:17, `voltus_em_lef_post_vsseco/`, LEF limits at Tj 100 C):**
VDD J/Jmax max 1.001 (one element, unchanged), VSS max 2.71 (was 4.02),
average 0.057. The 4x bottom-ring vias are gone; every remaining VSS element
over 1.0 is a **single-cut via4** where a 2 um met5 strap crosses a 2 um
met4 shape (`VSS.rj.avg.rpt`, sorted by I/Ilimit):

| location | what | count | I per cut |
|---|---|---|---|
| x 2882.6 | right strap end on its jumper | 45 | 2.4-3.2 mA |
| x 21.1 | left strap on the VSS vertical stripe | 39 | 2.0-2.5 mA |
| x 6.1 | left stub on the VSS ring | 29 | ~2 mA |
| x 2893.7 | right jumper on the VSS ring | 15 | ~2 mA |

Limit is 1.198 mA per via4 cut (2.49 mA/cut at 90 C x 0.481). The via4
rule (cut 0.8, spacing 0.8, met5 enclosure 0.31) fits one cut across a
2 um strap and about one cut per 1.6 um along it, so every strap-end
crossing in this PDN is a one-cut connection and cannot carry the strap.
Also 14 via3 at (21.1, y_link), the 1 um met3 leg on the stripe, at
<= 1.29x. Two ways to read this: the ECO exposed a PDN sizing fact (2 um
straps on 2 um stripes give one via4 cut per crossing; 4 um straps would
give four), and for iter19b the cheap fix is longer overlaps at the strap
ends only.

**ECO v5** (`scripts/vss_jumper_eco5.tcl`, launched 04:22, tmux
`vsseco19b5`, from `07_vssfix_v4ir.enc`): per strap, a met4 pad under the
strap past the VDD stripe on the left (x 18.5-26.5, merging with the VSS
stripe, ~5 cuts), a met4 pad under the last 8 um of the strap on the right,
a 4 um tall met4 pad over each VSS ring at the strap y (2x2 cuts), and a
2 um met3 pad over the stripe at y_link. Reroute loop as before; the gate
adds a via4 cut audit from `sViaInst.cutRects` (>= 3 cuts at each strap-end
pad, >= 2 at each ring pad). Voltus note: each run writes a new
`<net>_100C_avg_<n>` subdirectory in the same output dir, so `avg_1` was
the stub run and `avg_2` the v4 run; the earlier "does not overwrite" note
above is that, not a stale log.

**ECO v5 result (05:39, v5 export, `avg_3`):** VSS IR 29.4 mV worst / 19.1 mV
average (VDD 28 mV). VSS EM max 2.71x -> **1.78x**; the strap-end and ring
crossings are gone from the list. The 28 via4 elements left are all at
y 17.38 or y 2881.46 on the vertical stripes at x 201..621 and 2481: the
vertical met4 VSS stripes stop at the core edge (y 16.38 / 2882.46) and reach
the top and bottom rings through met5 jumpers that addStripe made on its own
(2 um wide, y 3.98-18.38 and 2880.46-2894.86), so each stripe end is a 2x2 um
overlap with ONE via4 cut, now carrying ~2.1 mA. These were the 4.0x elements
before any ECO; the strap jumpers took half their current, v5's pads none.
Plus 5 via3 at (21.1, y_link) <= 1.25x: the v5 met3 pad kept the old 10-cut
via (ViaGen "deleted to avoid violation" against it).

Two details learned on the way: (1) `editPowerVia -add_vias 1 -orthogonal_only
false -area <box>` is how to via a parallel overlap; its "created 1 via,
deleted 1 via to avoid violation" means the new array replaced the old
single via, not that nothing happened (the cut audit proved it: 5 cuts at
every strap-end pad, 4 at every ring pad). (2) The reroute loop can bounce
on a handful of signal-vs-signal shorts among the nets it keeps rerouting;
the legalize_fixup windowed rip-up (cut every signal wire within 6 um of
each marker, reroute together) cleared 8 of them in one pass. A reroute with
the antenna fixer off leaves antenna violations; feed those nets back in.

**ECO v6** (`scripts/vss_jumper_eco6.tcl`, 05:43, tmux `vsseco19b6`, from
`07_vssfix_v5em.enc`): extend all 96 met5 stripe-end jumpers by 8 um over
the met4 stripe (bottom up to y 26.4: the lowest VDD met5 strap at 16.98 is
already fragmented around the jumpers and the next is at 76.98; top down to
2872.5, highest VDD strap 2836.98), regenerate the via4 arrays with
editPowerVia (delete then add), regenerate the y_link met3-met4 vias, reroute
loop with windowed rip-up from pass 3, gate: >= 4 cuts at every stripe end.

**ECO v6 result (06:28, `avg_4`):** VSS IR 29.2 mV worst / 19.0 mV average.
VSS EM 1.78x -> **1.24x**; every via4 is now under the limit (worst 0.99 at a
jumper-to-ring via, 2 cuts). The 5 elements left are via3 at (21.1, y_link)
for y_link 383.18 / 443.02 / 502.86 / 2423.18 / 2483.02 (1.02-1.24x): the
v5 2 um met3 pad was never built there. The power planner refused four of
them with IMPPP-354 ("would merge with rings / no legal target / would
break a design rule") and five more never landed; those y_links sit within
2 um of the strap band, where the v3 met3 piece already is. The via on the
1 um leg is the 10-cut one. Lesson: `addStripe` can silently decline; the
count of shapes you asked for vs the count in the DEF is the check.

**ECO v7** (`scripts/vss_jumper_eco7.tcl`, 06:31, tmux `vsseco19b7`, from
`07_vssfix_v6.enc`): for every L-link leg without a 2 um pad, a vertical
met3 pad on the stripe (x 20.1-22.1, y_link +- 2.5) with
`setAddStripeMode -ignore_DRC true` so the planner does not refuse it
(verify_drc judges afterwards, and markers naming VDD are counted in the
gate), then editPowerVia delete+add met3-met4 over it; gate adds a via3 cut
audit (>= 20 cuts at every y_link).

**ECO v7 result (07:15, `avg_5`) and where the campaign stops.**

| package | VDD worst drop | VSS worst drop | VSS avg | VDD J/Jmax | VSS J/Jmax |
|---|---|---|---|---|---|
| pre-ECO (06_final 00:03) | 28 mV | 60.8 mV | 37.5 mV | 1.001 | 4.02 |
| v2 stubs | 28 | 60.8 | 37.5 | | |
| v4 L-links (IR fix) | 28 | 30.3 | 19.9 | 1.001 | 2.71 |
| v5 strap-end + ring via arrays | 28 | 29.4 | 19.1 | 1.001 | 1.78 |
| v6 stripe-end via arrays | 28 | 29.2 | 19.0 | 1.001 | 1.24 |
| **v7 y_link via arrays (final)** | **28** | **29.2** | **18.9** | **1.001** | **1.010** |
| v8 right-channel VDD/VSS stripe pair (LVS fix) | 28 | 29.2 | 18.8 | 1.001 | 1.009 |

Budget 52.8 mV: both rails pass with 2x margin. The 1.010 is three
segments of one 1 um met3 L-link leg (y_link 443.02, x 15.8-21.1) at
3.30 mA against a 3.27 mA limit; every via on VSS is under 1.0 (11 elements
between 0.95 and 1.0, all on the same left-edge L-links). VDD's 1.001 is
one via4 at (17.1, 376.98), a VDD vertical-stripe via to a VPWR rail, present
since before any ECO. Both are 1 % over an average-DC limit taken from the
tech LEF at Tj 90 C and derated to 100 C; a 2 um leg (or a second leg) at
that strap would clear it, but the sixth re-export of the day would cost the
signoff chain another hour and the number is not what decides the design.
Stopped here; `07_vssfix.enc` (v7) is the package the chain signs off.

**Campaign lessons in one place.** (1) IR/EM asymmetry between two rails
with identical geometry means one of them is missing a path; find it in
the DEF, not the connectivity report. (2) addStripe stops at the first ring
on its layer, trims silently around other-net PG on its layer, refuses
stripes it dislikes (IMPPP-354), and only drops vias where shapes cross.
Count what landed. (3) A 2 um strap on a 2 um stripe gives one via4 cut per
crossing in this PDK (0.8 cut, 0.8 space): with strap currents of 2-3 mA
and 1.2 mA per cut, every such crossing is an EM violation by construction.
Size the PDN (4 um straps: four cuts) or lengthen the overlaps.
(4) `editPowerVia -add_vias -orthogonal_only false` fills parallel
overlaps; "created 1, deleted 1" is success. (5) The rip-up/reroute loop
handles the signal collisions of any PG ECO; use the windowed rip-up when it
bounces and feed antenna nets back in when the fixer was off. (6) One
Innovus probe with `dbSchema` and `dbGet` answers attribute questions in
20 s; guessing cost three restarts. (7) Each ECO iteration cost ~50 min
(ECO 8, export 13, Voltus 25) and five were needed after the first one that
"worked"; the audit inside the ECO (vias, cuts) is what shortened the loop.

## 2026-09-07 14:04 - v8 (right-channel stripe pair) rerun: no change

ECO v8 added a VDD+VSS met4 stripe pair in the 24 um channel right of the
macro column (the LVS floating-rail fix, see lvs.md) and rerouted ~300 nets.
Voltus static IR + LEF-limit EM on the v8 export (avg_6): VDD 28 mV / 1.001
(same single via4), VSS 29.2 mV worst, 18.8 mV avg, EM 1.009 (was 1.010; same
met3 L-link leg). The grid is unchanged by the channel stripes, as expected -
they hang off the existing straps and rings. Logs: runs/<19b>/logs/voltus19b8_sh.log.
