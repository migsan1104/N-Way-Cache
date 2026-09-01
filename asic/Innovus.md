# Innovus.md — place-and-route of the cache, taught one stage at a time

This is the companion to `asic/pnr/`. It is written to be followed at an
Innovus prompt, script line by script line, by someone who is learning
physical design *and* Tcl at the same time. Nothing here is faster than
it needs to be. Read `asic/MACROS.md` first for why there are 16 SRAM
macros in the design; everything else you need is in this file.

How to use it: **Part A** is a twenty-minute Tcl primer that only covers
what the flow scripts actually use. **Part B** is the flow, one stage per
chapter. Each chapter has the same shape: *what problem this stage
solves → the exact script lines, annotated → what to look at when it
finishes → one thing to try yourself.* The worked example throughout is
the first run on the e35abcde netlist
(`asic/PPA/pnr/assoc_4/runs/20260825_231645_e35abcde_4p0ns/`).

---

# Part A — enough Tcl to read the scripts

Innovus is driven by Tcl. Every command you type at the `innovus>`
prompt is a Tcl command; the flow file `scripts/flow.tcl` is just those
commands in a file. You need about ten ideas.

### A1. Commands are words separated by spaces

```tcl
create_floorplan -site unithd -core_size 3000 2000 30 30 30 30
```

The first word is the command, everything else is an argument. Arguments
beginning with `-` are options (`-site unithd` means "the option site,
with value unithd"). There are no parentheses and no commas.

### A2. Variables: `set`, and `$` to read them

```tcl
set CORE_W 3000          ;# store
puts $CORE_W             ;# read -> prints 3000
```

`;#` starts a comment on the same line as a command; a line beginning
with `#` is a whole-line comment. Convention in these scripts: upper-case
names are settings decided at the top of the file.

### A3. `$env(NAME)` reads a shell environment variable

```tcl
set RUN $env(PNR_RUN_DIR)
```

`run_innovus.sh` exports every path as `PNR_*` before starting Innovus,
so the Tcl never hard-codes a path. `$::env(...)` (with the `::`) is the
same thing written from inside a proc, where the plain name would be
looked up in the proc's local scope. You will see both forms.

### A4. Square brackets run a command and substitute its result

```tcl
set macros [get_db insts -if {.base_cell.name == sram_1rw1r_32_256_8_sky130}]
puts "INFO: [llength $macros] macro instances"
```

`[...]` is evaluated first and its output is dropped into the outer
command. `llength` is "length of list". Inside double quotes `$` and
`[]` are still substituted; inside braces `{...}` nothing is — that is
why option values that contain `$` or `.` filters are written in braces:
they are passed verbatim for the command to interpret.

### A5. Arithmetic needs `expr`

```tcl
set y0 [expr {($CORE_H - 4*$MAC_H - 3*$HALO) / 2.0}]
```

Tcl has no infix arithmetic on its own; `expr` does it. Write the
expression in braces (faster, and `$` still works inside `expr`). `2.0`
rather than `2` forces floating point — `7/2` is `3` in Tcl, `7/2.0` is
`3.5`.

### A6. Lists

```tcl
set L [list a b c]        ;# a three-element list
lindex $L 1               ;# -> b   (zero-based)
lsort $L                  ;# sorted copy
foreach m $L { puts $m }  ;# loop
```

Almost every Innovus query returns a list. `{VDD VSS}` in an option is a
two-element list written with braces.

### A7. `proc` defines a command; `global` reaches file-level variables

```tcl
proc stage_place {} {
    global DB RPT
    place_opt_design -report_dir $RPT/place
    write_db $DB/04_place.db
}
```

Each stage of the flow is a proc so the driver at the bottom of the file
can call them by name. Variables set at the top of the file (`DB`,
`RPT`, `CORE_W` …) are *global*; a proc has to declare `global X` before
it can read `$X`. The `{}` after the name is the (empty) parameter list.

### A8. `catch` turns an error into a return code

```tcl
if {[catch {stage_$s} msg]} {
    puts "STAGE $s FAILED: $msg"
    exit 1
}
```

Without `catch`, an error inside a stage would abort the whole script
with no checkpoint written. With it, the driver can print which stage
failed and stop cleanly. `stage_$s` builds the command name from a
variable — Tcl lets you do that because commands are just words.

### A9. The Innovus object model: `get_db` / `set_db`

This is the part that is Innovus, not Tcl. The design is a database of
objects — `insts`, `nets`, `ports`, `base_cells`, `pins` — each with
attributes.

```tcl
get_db insts                                  ;# every instance (a huge list)
get_db insts -if {.base_cell.name == sram_*}  ;# filter by attribute, wildcards ok
get_db [get_db ports cpu_*] .name             ;# attribute of a list of objects -> list of names
set_db $c .dont_use true                      ;# write an attribute on an object
set_db cts_target_skew 0.20                   ;# no object: a *root* attribute = a tool setting
```

Read `get_db X -if {...}` as "give me the X's for which ...". Attributes
start with a dot, and dots chain (`.base_cell.name` = the name of the
library cell this instance is an instance of). Root attributes such as
`route_design_top_routing_layer` are how Stylus replaces the hundreds of
legacy `setXxxMode` commands: `help route_design_*` lists them and
`get_db route_design_top_routing_layer` shows the current value.

### A10. Getting help without leaving the prompt

```tcl
help create_floorplan          ;# option summary
man  create_floorplan          ;# full page
get_db -help place_*           ;# root attributes matching a pattern
```

That is all the Tcl the scripts use. Everything else is Innovus commands,
which the chapters below introduce as they are needed.

---

# Part B — the flow, one stage at a time

### B0. What physical design is, in one paragraph

Synthesis (Genus) turned the RTL into 147k standard cells and 16 macros
connected by nets, and estimated wire delays from a rough placement.
Place-and-route makes those wires real. In order: decide where the
macros go (**floorplan**), draw the power grid (**power**), give every
standard cell an exact location (**placement**), build the clock
distribution tree (**CTS**), draw every signal wire (**routing**), and
check timing again with the wires you actually drew (**sign-off**).
Each step is a commitment the next step cannot undo, which is why the
flow writes a database checkpoint after each one.

### B0.1 The files

```
asic/pnr/
  run_innovus.sh            the launcher: sets PNR_* paths, starts innovus in batch
  scripts/flow.tcl          the stages (Part B walks through it)
  scripts/mmmc.tcl          libraries + RC + SDC bundled into one "analysis view"
  constraints/pnr_4p0.sdc   golden.sdc with the period changed to 4.000 ns
  lef/sram_1rw1r_32_256_8_sky130.lef   the macro LEF with its layer names fixed
```

Run everything: `cd asic/pnr && ./run_innovus.sh`. Resume from a
checkpoint: `PNR_START_STAGE=cts PNR_RUN_STAMP=<same stamp> ./run_innovus.sh`.
Results: `asic/PPA/pnr/assoc_4/runs/<stamp>/{db,reports,outputs,logs}`.

### B0.2 Following along interactively

```bash
ssh -X <server>                       # X forwarding: you will want gui_show
source /apps/settings
cd /ecel/UFAD/miguel.sanchez1/Cache/asic/pnr
eval "$(sed -n 's/^export //p' run_innovus.sh | grep -v STAMP | sed "s|\$HERE|$PWD|g; s|\$PDK|/apps/cds/IC618/local/opdk/share/pdk/sky130A|g; s|\$GENUS_RUN|$(ls -d ../PPA/genus/assoc_4/runs/*e35abcde* | tail -1)|g" | sed 's/^/export /')"
export PNR_RUN_DIR=$PWD/scratch; mkdir -p scratch
innovus -stylus
```

Then in Innovus, `source scripts/flow.tcl` would run everything; instead
paste the lines of each chapter yourself. After every chapter:
`gui_show` to look, `gui_hide` to continue, `write_db scratch/bN.db` to
save. (`-stylus` selects the "common UI" command set used everywhere
below; without it you get the legacy camelCase commands, which do not
mix.)

---

## Chapter 1 — INIT: loading the design

**Problem.** Innovus starts empty. It needs three things to build a
timing graph: what the cells *are* (libraries), what they *look like*
(LEF), and how they are *connected* (netlist) — plus the constraints.

**Inputs, and why each exists**

| File | Contains | Who reads it |
|---|---|---|
| `.lib` (Liberty) | per-cell delay/slew/power tables vs input slew and output load | the timer |
| tech LEF (`.tlef`) | the metal stack: layer names, pitches, widths, vias, spacing rules | placer, router, RC estimator |
| cell LEF (`.lef`) | per-cell footprint: size, pin shapes on which layer, obstructions | placer, router |
| netlist (`.v`) | instances of cells, wired by nets | everyone |
| SDC | clock period, I/O delays, max slew/cap/fanout | the timer |

**The script, line by line** (`stage_init` in `flow.tcl`):

```tcl
set_db init_power_nets  {VDD}
set_db init_ground_nets {VSS}
```
The netlist has no power ports (synthesis netlists never do). These two
root attributes name the global power and ground nets that everything
will be connected to. They must be set *before* `init_design`.

```tcl
read_mmmc $::env(PNR_MMMC)
```
Reads `scripts/mmmc.tcl`. MMMC = multi-mode multi-corner: the general
machinery for "analyse the design under N combinations of library
corner, RC corner and constraint set". We use one of each, but the
objects still have to be declared:

```tcl
create_library_set    -name ss_libs  -timing {std-cell ss lib  macro SS lib}
create_timing_condition -name ss_cond -library_sets {ss_libs}
create_rc_corner      -name rc_lef   -temperature 100
create_delay_corner   -name ss_corner -timing_condition ss_cond -rc_corner rc_lef
create_constraint_mode -name func    -sdc_files {pnr_4p0.sdc}
create_analysis_view  -name ss_view  -constraint_mode func -delay_corner ss_corner
set_analysis_view     -setup {ss_view} -hold {ss_view}
```
Read bottom-up: an *analysis view* = a constraint mode + a delay corner;
a delay corner = libraries + RC corner. `set_analysis_view` says which
views to check setup and hold in. We check both in the same slow view
because the macro has no fast library (see Chapter 8).

```tcl
read_physical -lefs [list $::env(PNR_TECH_LEF) $::env(PNR_CELL_LEF) $::env(PNR_MACRO_LEF)]
```
Tech LEF first, always — it defines the layers the other LEFs refer to.
**The macro LEF is a patched copy** (`asic/pnr/lef/`): the vendored file
names its layers `m1..m4` while the tech LEF says `met1..met5`. Genus
had been silently dropping every macro pin and obstruction it could not
map (look for "A layer must be defined in the LEF technology LAYER
section" in any Genus log). Innovus refuses instead, which is the better
behaviour.

```tcl
read_netlist $::env(PNR_NETLIST) -top Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1
init_design
```
`init_design` is the moment the design exists: netlist bound to
libraries and LEF, constraints loaded, timer ready. From here
`report_timing` works (with no wires yet).

```tcl
connect_global_net VDD -type pg_pin -pin_base_name VPWR -all
connect_global_net VDD -type pg_pin -pin_base_name VPB  -all
connect_global_net VDD -type pg_pin -pin_base_name vdd  -all
connect_global_net VSS -type pg_pin -pin_base_name VGND -all
connect_global_net VSS -type pg_pin -pin_base_name VNB  -all
connect_global_net VSS -type pg_pin -pin_base_name gnd  -all
```
Power pins are connected *by name*: every std cell has `VPWR/VGND`
(supply) and `VPB/VNB` (well taps), the macro has `vdd/gnd`. Six lines,
two nets. If you forget one, the power router later reports floating
pins.

```tcl
foreach pat {*lpflow* *__probe_* *__probec_*} {
    foreach c [get_db base_cells $pat] { set_db $c .dont_use true }
}
```
The same cells Genus was forbidden to use (low-power-flow and probe
cells that are not placeable in a plain design). `opt_design` would
otherwise happily swap them in. Tcl note: nested `foreach`, the inner
one over the list returned by `get_db base_cells <pattern>`.

```tcl
set macros [get_db insts -if {.base_cell.name == $MACRO_CELL}]
set_timing_derate -delay_corner ss_corner -late $MACRO_DERATE $macros
```
The ×2.0 late derate on the 16 macro instances — identical to synthesis,
so P&R and Genus numbers stay comparable. `-late` = applies to the
launching (data) path delays; a derate > 1 makes the macro slower.

```tcl
set_db design_process_node 130
set_db route_design_bottom_routing_layer 2    ;# met1 (index form)
set_db route_design_top_routing_layer    5    ;# met4
set_db design_bottom_routing_layer met1       ;# the one that matters - see below
set_db design_top_routing_layer    met4
write_db $DB/01_init.db
```
**The `li1` trap, which cost the first two runs.** sky130's tech LEF
declares `li1` (local interconnect, meant for inside cells) as a
*routing* layer with `RESISTANCE RPERSQ 12.8` — a hundred times
`met1`'s 0.125. Innovus's pre-route RC estimator uses every routing
layer the design allows; with `li1` included, a 500 µm wire is estimated
at ~37 kΩ and every path in the design fails by nanoseconds (v2 run:
34.6k of 39k paths violating, WNS −9.3 ns, on a netlist that closes at
4.02 ns in Genus). `route_design_*_routing_layer` only limits the
*router*; `design_bottom/top_routing_layer` is what the estimator
honours, and it takes a layer *name*. Any time an entire design fails
uniformly, suspect the model, not the logic.

*How this was proven:* read the unplaced design (`01_init.db`) and
`report_timing` it. With no wires at all, the worst path is the macro
read at **WNS −0.233 ns** at 4.0 ns — the Genus number. So the logic and
the macro model are correct; every nanosecond in a placed run is wire,
and most of that was the `li1` estimate. Timing the design at three
points — unplaced (model only), post-place (estimated wires), post-route
(real wires) — localises any surprise to exactly one of the three.

Signals may use `met1`–`met4`; `met5` (3.4 µm pitch, coarse) is kept for
the power grid, as every sky130 flow does. A trap worth knowing: these
two attributes take layer *indices*, not names (the tool rejects
`met1`), and the tech LEF declares `li1` as routing layer 1 — so
`met1`=2, `met2`=3, `met3`=4, `met4`=5, `met5`=6. Check with
`get_db layers .name` before trusting a number. `write_db` is the
checkpoint.

**Look at.** `report_timing` — with the 4.0 ns SDC and no wires you
should see positive or near-zero slack; the Genus number was −524 ps at
3.5 ns. `get_db insts -if {.base_cell.name == sram_*}` should return 16.
`report_design_mismatch` should be empty (cells in the netlist that no
LEF/lib describes).

**Try.** `get_db [lindex $macros 0] .bbox` — the macro's bounding box;
it is at the origin because nothing is placed yet. `get_db ports .name`
— the 21 top-level ports.

---

## Chapter 2 — FLOORPLAN: where the big things go

**Problem.** Macros are huge (each 376 × 446 µm; the 16 of them are
2.69 mm², more than the 1.49 mm² of standard cells) and they block
routing on `met1`–`met4`. Their positions decide the shape of every
long wire in the design. The tool can place macros automatically, but
for a first floorplan doing it by hand is faster to understand and to
debug.

**First, the rule that decides everything: signals cannot cross a macro.**
The macro obstructs `met1`–`met4` over its whole area and `met5` is
reserved for power, so a wire that needs to get past a macro goes
*around* it. And the macro's pins are not on all sides equally: the read
port (`addr1`, `clk1`, `dout1`) is on its **N and E edges**, the write
port on S and W. So each macro has a side that must face the logic that
reads it.

**The first floorplan got this wrong** (the run is kept as a worked
counter-example, see "Run 1 post-mortem" at the end). It stacked two
columns of macros on each side. The outer column's read edge faced the
inner column, every 32-bit `dout1` bus detoured ~1 mm around it, the
placer inserted 14-buffer repeater chains, and the pre-CTS WNS was
−2.3 ns. No amount of optimisation fixes a floorplan.

**The v2 floorplan is a ring**: four macros on each side of a central
logic region, each rotated so its read edge faces the centre.

```
        way1 (mx)   ┌────┬────┬────┬────┐     top row, N edge faces DOWN
                    └────┴────┴────┴────┘
   way0  ┌──┐                              ┌──┐  way3
   (r0)  │  │        standard cells        │  │  (my)
   E     │  │        1667 x 1627 um        │  │  E edge
   faces │  │        ~55 % density         │  │  faces
   right │  │                              │  │  left
         └──┘                              └──┘
        way2 (r0)   ┌────┬────┬────┬────┐     bottom row, N edge faces UP
                    └────┴────┴────┴────┘
```

The arithmetic: a row or column of 4 macros with 20 µm halos is
4 × 376.5 + 3 × 20 = 1566 µm wide (rows) or 4 × 446.2 + 3 × 20 =
1845 µm tall (columns). The centre needs 1.49 mm² of std cells at ~55 %
→ ~2.7 mm². Core = 2540 × 2600 µm: the columns (416 µm each side) leave
1667 µm of width; the rows (486 µm top and bottom) leave 1627 µm of
height; 1667 × 1627 = 2.71 mm². 30 µm margin all round for the ring.

```tcl
create_floorplan -site unithd -core_size $CORE_W $CORE_H $MARGIN $MARGIN $MARGIN $MARGIN
```
`-site unithd` is the std-cell row site from the tech LEF (rows are
2.72 µm tall, cells snap to them). The four margins are
left/bottom/right/top core-to-die distances. Innovus snaps the core to
the row/track grid — the IMPFP-4026 "adjusting core to 29.92" warnings
are normal.

```tcl
set macros [lsort [get_db [get_db insts -if {.base_cell.name == $MACRO_CELL}] .name]]
```
Sorted names come out `GEN_WAYS[0]...g_bank[0]`, `...g_bank[1]`, … so
index `i` is way `i/4`, bank `i%4`; one way per side. (Tcl:
`[get_db <objects> .name]` turns objects into names; `lsort` sorts.)

```tcl
set pitch_v [expr {$MAC_H + $HALO}]
set pitch_h [expr {$MAC_W + $HALO}]
set ycol0   [expr {($CORE_H - 4*$MAC_H - 3*$HALO) / 2.0}]   ;# columns centred
set xrow0   [expr {($CORE_W - 4*$MAC_W - 3*$HALO) / 2.0}]   ;# rows centred
foreach m $macros {
    set way [expr {$i / 4}]; set k [expr {$i % 4}]
    switch $way {
        0 { set x $HALO;                             set y [expr {$ycol0 + $k*$pitch_v}]; set o r0 }
        1 { set x [expr {$xrow0 + $k*$pitch_h}];     set y [expr {$CORE_H - $HALO - $MAC_H}]; set o mx }
        2 { set x [expr {$xrow0 + $k*$pitch_h}];     set y $HALO;                            set o r0 }
        3 { set x [expr {$CORE_W - $HALO - $MAC_W}]; set y [expr {$ycol0 + $k*$pitch_v}];  set o my }
    }
    place_inst $m [expr {$x + $MARGIN}] [expr {$y + $MARGIN}] $o -fixed
    incr i
}
```
`switch` is Tcl's case statement. The orientation is the whole point:
`r0` = as drawn (E edge on the right → faces the centre for the left
column, N edge up → faces the centre for the bottom row); `my` =
mirrored about the y-axis (E edge now on the left, for the right
column); `mx` = mirrored about the x-axis (N edge now at the bottom,
for the top row). `place_inst name x y orientation -fixed`: `-fixed`
means the placer may not move it. Coordinates are **die**-relative, so
the core margin is added.

```tcl
create_place_halo -all_blocks -halo_deltas $HALO $HALO $HALO $HALO
create_route_halo -all_blocks -bottom_layer met1 -top_layer met4 -space 2
```
A *place halo* keeps standard cells 20 µm away from every macro edge so
the macro's pins (on `met3`/`met4`, on all four sides) can be reached. A
*route halo* keeps signal wires 2 µm off the edge on the blocked layers.

```tcl
edit_pin -pin [get_db [get_db ports cpu_*] .name] -side left  -layer met3 -spread_type center -spacing 2 -fixed_pin
edit_pin -pin [get_db [get_db ports mem_*] .name] -side right -layer met3 -spread_type center -spacing 2 -fixed_pin
edit_pin -pin {clk rst} -side top -layer met4 -spread_type center -spacing 10 -fixed_pin
```
Top-level pins along the die edge — but the ring covers the middle of
every edge, so the pins go in the corner gaps the ring leaves free (CPU
interface bottom-left, memory interface bottom-right, clock/reset
top-left), placed with `-spread_type range -start {x y} -end {x y}`.
For a block that will sit inside a larger chip this is a guess; it
barely affects timing because every port is registered in the wrapper.

```tcl
add_well_taps -cell sky130_fd_sc_hd__tapvpwrvgnd_1 -cell_interval 14 -in_row_offset 7
```
sky130 has no taps inside its cells; a tap cell every ≤ 15 µm in every
row ties the wells to supply (latch-up rule). This drops ~50k tiny cells
before placement even starts.

```tcl
check_floorplan > $RPT/floorplan.rpt
write_db  $DB/02_floorplan.db
write_def -floorplan $OUT/floorplan.def
```

**Look at.** `gui_show`: the two macro blocks and the channel. Turn on
*Layout → Physical → Halo*. `check_floorplan` should list no overlaps.
The DEF is text — `head -50 outputs/floorplan.def` shows the die area,
rows and macro placements in a form any tool (including KLayout) can
read.

**Try.** Move one macro: `place_inst <name> 100 100 r0 -fixed`, `gui_show`,
then `read_db db/02_floorplan.db` to undo. Or change `COL_GAP` to 100
and re-run the chapter — this floorplan is the one knob in the whole
flow that is genuinely yours.

---

## Chapter 3 — POWER: the grid the cells hang from

**Problem.** Every cell needs VDD and VSS at its rails; the macros need
them at their `met3/met4` pins. Signal routing later must weave through
whatever grid you draw, so the grid should be regular and use as little
of the low metal as possible.

**The sky130 stack**, because the plan depends on it:

| Layer | Direction | Pitch | Used for |
|---|---|---|---|
| `li1` | vertical | 0.46 | inside cells |
| `met1` | horizontal | 0.34 | std-cell rails, short signals |
| `met2` | vertical | 0.46 | signals |
| `met3` | horizontal | 0.68 | signals, macro pins |
| `met4` | vertical | 0.92 | signals, macro power pins, power stripes |
| `met5` | horizontal | 3.4 | power only (too coarse for signals) |

The macros obstruct `met1`–`met4`. Only `met5` can cross them, which
dictates the grid:

```tcl
add_rings -nets {VDD VSS} -type core_rings -follow core \
    -layer {top met5 bottom met5 left met4 right met4} -width 4 -spacing 2 -offset 4
```
Two concentric rings around the core: horizontal sides on `met5`,
vertical sides on `met4`. `-width 4 -spacing 2`: 4 µm wide wires, 2 µm
apart. Everything else connects to these.

```tcl
add_stripes -nets {VDD VSS} -layer met5 -direction horizontal \
    -width 3 -spacing 2 -set_to_set_distance 120 -start_offset 60
```
Horizontal `met5` stripe pairs every 120 µm across the *entire* core,
macros included. The macros' `met4` power pins will be dropped onto
these wherever they cross.

```tcl
add_stripes -nets {VDD VSS} -layer met4 -direction vertical \
    -width 2 -spacing 2 -set_to_set_distance 120 -start_offset 60 \
    -area {853 30 2177 2030}
```
Vertical `met4` stripes only in the std-cell channel (the `-area` box is
the channel in die coordinates) — `met4` over a macro would collide
with its obstruction.

```tcl
route_special -nets {VDD VSS} -connect {core_pin floating_stripe} \
    -core_pin_layer met1 -allow_jogging 1 -allow_layer_change 1 \
    -layer_change_range {met1 met5} -crossover_via_layer_range {met1 met5}
```
The power router. `core_pin` = draw the `met1` rail along every std-cell
row (the "follow-pin" rails) and via it up to every stripe it crosses;
`floating_stripe` = tie any stripe end that reaches nothing. Takes
seconds.

**What is deliberately not here: the macro pins.** The first run used
`-connect {block_pin core_pin floating_stripe} -block_pin all`, which
asks the router to connect every power-pin *shape* of every macro. The
vendored macro's `vdd`/`gnd` pins are each ~2,600 small rectangles (a
ring drawn as pieces), so that is 16 × 5,200 targets; after an hour at
100 % CPU and 10 GB it had printed nothing. Lesson: a LEF pin is a
*set of shapes*, and `-block_pin all` is per shape. The macro
connection lives in its own optional stage (`stage_macropg`, using
`-block_pin boundary_with_pin -block_pin_target nearest_target`, one
connection per pin per edge) so a slow power step cannot hold the
timing stages hostage — signal timing does not depend on macro power.

```tcl
check_connectivity -nets {VDD VSS} > $RPT/pg_connectivity.rpt
write_db $DB/03_power.db
```
Until `macropg` has run this report *will* list the macro power pins as
unconnected (it stops at 1,000 errors). What must not appear is a
dangling std-cell rail: search the report for `CORE_ROW` / rail
entries, not for the total.

**Look at.** `gui_show` with only `met4`/`met5` visible (*Layer* panel,
uncheck the rest): the ring, the horizontal stripes crossing the
macros, the vertical ones in the channel. Zoom on a macro edge to see
the via stacks from its `met4` pins to the `met5` stripes.

**Try.** `-set_to_set_distance 60` halves the stripe pitch: less IR drop,
less routing room. There is no free lunch; the trade is real and this is
where you would make it.

---

## Chapter 4 — PLACEMENT: every gate gets an address

**Problem.** 147k standard cells and 50k taps have to go on rows so that
(a) the wires between them are short, (b) no region is so dense the
router cannot get through, (c) timing is met. Innovus does this in three
sub-steps inside one command: *global placement* (analytic, cells may
overlap), *legalisation* (snap to rows and sites, remove overlaps),
*optimisation* (resize gates, add/remove buffers against the timing
estimate).

```tcl
set_db place_global_place_io_pins false      ;# pins are already fixed (Chapter 2)
set_db place_global_cong_effort auto         ;# congestion-aware placement
set_db add_tieoffs_cells {sky130_fd_sc_hd__conb_1}
set_db add_tieoffs_max_fanout 8
place_opt_design -report_dir $RPT/place
```
`place_opt_design` = placement + pre-CTS optimisation. It is the
longest single command in the flow (~2 h here for 147k cells) and its
log shows the three sub-steps with a timing summary after each.

```tcl
add_tieoffs
opt_design -pre_cts -report_dir $RPT/place
time_design -pre_cts -report_dir $RPT/place -report_prefix pre_cts
rpt $RPT/place/density.rpt report_density
write_db $DB/04_place.db
```
`conb_1` is the sky130 constant cell. The netlist has 761 macro pins
tied to 1/0 (`wmask0`, `csb1`) and `add_tieoffs` must run on a *placed*
design (it errors otherwise). Run 1 let one `conb_1` drive all 761 pins
— 6.8 pF, 15 ns edges — so v2 caps the fanout at 8 and follows with an
incremental `opt_design -pre_cts` to legalise and size what was added.
`time_design -pre_cts` is the **first real timing number**: placed
cells, estimated (not yet routed) wires, and an *ideal* clock (arrives
everywhere at t=0). Write it down; every later stage is compared to it.

**Look at.** `reports/place/pre_cts_*.summary` — the WNS/TNS table, plus
DRV (design-rule violations: max slew/cap/fanout from the SDC). In the
GUI, *View → Density map*: the channel should be an even colour; a red
band along a halo means the cells wanted to be closer to the macro than
the halo allows — that is the floorplan telling you to move something.
`report_utilization`: the number to compare with the 58 % estimate.

**Try.** `report_timing -max_paths 5` and compare the startpoints with
the Genus census (`asic/census.py`). If the worst path is now something
that was not in the Genus top-1000, placement created it — usually a
wire that crosses the whole channel.

---

## Chapter 5 — CTS: the clock becomes a physical thing

**Problem.** Up to now the clock reached all 35k flops and 16 macros at
time zero. In silicon it is one wire from the `clk` pin, fanned out
through a tree of buffers; the arrival at each flop differs by up to a
few hundred ps (*skew*), and the whole tree takes ~1 ns to traverse
(*latency*). Setup and hold both change once that is real.

```tcl
set_db cts_buffer_cells   {sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_16}
set_db cts_inverter_cells {sky130_fd_sc_hd__clkinv_4 sky130_fd_sc_hd__clkinv_8 sky130_fd_sc_hd__clkinv_16}
set_db cts_target_max_transition_time 0.4
set_db cts_target_skew 0.20
```
Which cells the tree may be built from (the `clkbuf` family has balanced
rise/fall) and what to aim for: ≤ 400 ps edges, ≤ 200 ps skew.

```tcl
ccopt_design -report_dir $RPT/cts
report_clock_trees  > $RPT/cts/clock_trees.rpt
report_skew_groups  > $RPT/cts/skew_groups.rpt
```
CCOpt = "clock concurrent optimisation": builds the tree and, at the
same time, deliberately skews it where that helps setup (a flop at the
end of a long path can receive its clock a little late). After it, the
clock is *propagated*: real latencies replace the ideal ones.

```tcl
opt_design -post_cts -setup -hold -report_dir $RPT/cts
time_design -post_cts       -report_dir $RPT/cts -report_prefix post_cts
time_design -post_cts -hold -report_dir $RPT/cts -report_prefix post_cts
write_db $DB/05_cts.db
```
Hold is now meaningful for the first time: a flop whose data comes from
a neighbour through one gate can violate hold if its clock arrives
earlier than the neighbour's. `opt_design -hold` adds delay cells
(`dlygate4sd*`) on such paths — without letting setup TNS degrade
(`opt_fix_hold_allow_setup_tns_degradation false`).

**Look at.** `clock_trees.rpt`: number of buffers, levels, max latency,
skew. `post_cts_*.summary` vs `pre_cts`: the setup cost of a real clock
should be ≤ 100–150 ps of WNS. The hold summary should be clean after
`opt_design`. **The macro read path from Entry 39** (`u_sram/clk1 →
out_rdata`, a half-cycle path) is decided here: `clk1` is a leaf of the
same tree, and its latency relative to the capturing flop's is the
difference between passing and failing.

**Try.** `report_timing -from [get_db pins *u_sram/clk1] -max_paths 3`.
Compare launch and capture clock latencies in the path header.

---

## Chapter 6 — ROUTING: the wires

**Problem.** Every net becomes metal on specific tracks with
DRC-clean spacing, through a grid already partly occupied by power, and
without making timing worse than the estimates said (or coupling into
neighbouring wires — *signal integrity*).

```tcl
set_db route_design_with_timing_driven true
set_db route_design_with_si_driven true
set_db route_design_detail_post_route_spread_wire true
route_design
```
NanoRoute: global routing (which regions each net passes through), track
assignment, detail routing (exact shapes and vias, rule-clean).
Timing-driven = prioritise critical nets; SI-driven = space aggressors
away from victims; spread-wire = use free tracks to widen spacing after
the fact.

```tcl
set_db extract_rc_engine post_route
extract_rc
opt_design -post_route -setup -hold -report_dir $RPT/route
write_db $DB/06_route.db
```
`extract_rc` replaces the estimates with resistance and capacitance
computed from the drawn wires — **from the tech LEF's per-layer values**,
because this server has no QRC techfile or capacitance table for sky130
(Chapter 8). `opt_design -post_route` then does the last resizing with
the real wires in place, constrained to changes the router can absorb.

**Look at.** `report_route -summary`: violations should be zero or a
handful; thousands means congestion — go back to Chapter 2 and widen
the channel. In the GUI, *congestion map* before `route_design`
(`route_global` only) is the fast way to see where wires are fighting.

---

## Chapter 7 — FINAL: numbers and files

```tcl
time_design -post_route       -report_dir $RPT/final -report_prefix post_route
time_design -post_route -hold -report_dir $RPT/final -report_prefix post_route
report_timing -max_paths 1000 -path_type full_clock -nworst 1 > $RPT/final/timing_setup_1000.rpt
report_timing -max_paths 200  -early                          > $RPT/final/timing_hold_200.rpt
report_area ; report_utilization ; report_power
check_drc -out_file $RPT/final/drc.rpt
check_connectivity -out_file $RPT/final/connectivity.rpt
report_route -summary > $RPT/final/route_summary.rpt
add_fillers -base_cells {sky130_fd_sc_hd__fill_8 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_1}
write_def     $OUT/$TOP.def
write_netlist $OUT/$TOP.pnr.v
write_sdf     $OUT/$TOP.sdf
write_stream  $OUT/$TOP.gds -merge {std-cell GDS  macro GDS}
write_db $DB/07_final.db
```

* `timing_setup_1000.rpt` is in the same format `asic/census.py` reads:
  `python3 asic/census.py <this file>` gives the same cone table as for
  Genus, so the two can be compared class by class.
* `-early` = hold report.
* `add_fillers` plugs every empty site with a filler (rails and wells
  must be continuous) — done *after* the timing reports so it cannot
  perturb them.
* `.def` is the placed-and-routed design as text; `.pnr.v` the netlist
  with the clock tree, buffers, tie cells; `.sdf` the delays for a
  gate-level simulation; `.gds` the layout, with the standard-cell and
  macro layouts merged in. **`klayout outputs/<top>.gds`** — this is the
  first artefact in the project KLayout is the right tool for.

**The comparison chain to keep**

```
Genus PLE @3.5 ns   e35abcde  WNS -524 ps  (≈ +0 at 4.02 ns)
pre-CTS   @4.0 ns   placement, estimated wires, ideal clock
post-CTS  @4.0 ns   real clock, hold fixed
post-route@4.0 ns   real wires, LEF RC
```
Each arrow costing more than ~10–15 % of the period is the stage to
investigate; that is the whole method.

---

## Chapter 8 — what this flow does not yet do (honest list)

1. **RC extraction is LEF-based.** No QRC techfile / cap table for sky130
   here. Post-route slack is directionally right, absolutely ±10 %.
   Fix: a Quantus techfile for sky130, or accept the margin.
2. **Hold at one corner.** The macro has no fast lib, so no FF analysis
   view. Real hold sign-off needs the std-cell `ff_n40C_1v95` lib plus a
   fast macro model — the OpenRAM FF characterisation already in
   `asic/openram/macros_out/32x256_FF/` is that model, once its cell
   name is rebadged (see `bind_and_run_ss.sh` for the recipe).
3. **Power is vectorless.** Default toggle rates. For a real number, dump
   a VCD from the regression at 1.0 and `read_activity_file`.
4. **Physical verification is separate.** DRC/LVS against the foundry
   deck: Pegasus is installed (`/apps/cds/pegasus231`); the open path is
   `magic` DRC and `netgen` LVS from `libs.tech/`. Neither is wired in.
5. **Macro views must stay one family.** GDS, LEF and lib all from the
   vendored `sram_1rw1r_32_256_8_sky130`. The OpenRAM-regenerated macro
   is for *timing calibration* (MACROS.md); its GDS is a different
   footprint and is DRC/LVS-unverified.

## Chapter 9 — things that bite

* Stylus (`place_opt_design`, `set_db`) vs legacy (`placeDesign`,
  `setPlaceMode`): two command sets, one tool; `innovus -stylus` selects
  the first. Documentation you find online is often the second.
* `place_inst` takes die coordinates; `create_floorplan`'s margins shift
  the core, so add them.
* A stage that fails leaves the previous `.db` intact: fix the script,
  then `PNR_START_STAGE=<stage> PNR_RUN_STAMP=<same stamp> ./run_innovus.sh`.
* Innovus echoes every line of a sourced script into the log, including
  the `puts "... FAILED"` line itself — grep for `^PNR_RESULT`, not for
  the word FAILED.
* `write_stream` without a layer map uses LEF layer names; if KLayout
  shows nothing, export a map with `write_stream -map_file` after
  checking `get_db layers .name`.

---

## Appendix — Run 1 post-mortem (2026-08-25/26), kept as the worked counter-example

Run `20260825_231645_e35abcde_4p0ns`, the v1 floorplan (two 2×4 macro
blocks left and right, 3000 × 2000 µm core). What happened, in order,
and what each taught:

1. **`route_special -block_pin all` ran for an hour and printed nothing.**
   A LEF pin is a *set of shapes*; the macro's `vdd`/`gnd` are ~2,600
   rectangles each, and `all` means every shape. The macro connection is
   now the optional `macropg` stage (Chapter 3).
2. **`report_utilization` is not a Stylus command.** Placement (2 h) had
   finished, the report line errored, and the stage died *before its
   `write_db`*. Every report now goes through `rpt`, which logs and
   continues. Write the checkpoint before the optional reports, or make
   the reports unable to fail.
3. **The pre-CTS timing it did write** (`reports/place/pre_cts.summary.gz`):
   WNS −2.295 ns at 4.0 ns, 15,280 violating paths, density 78 %,
   routing overflow 11.8 % H. Density had been 51 % after placement;
   optimisation added 50 % more cell area trying to buffer paths that
   no buffer can fix — the signature of a floorplan problem, not a
   logic problem.
4. **The worst path** was the macro read: `u_sram/clk1 → dout1` 1.53 ns
   (higher load than Genus saw), then **14 repeater buffers** to reach
   the read mux. The outer macro column's read edge faced the inner
   column; signals cannot cross a macro; every 32-bit `dout1` bus went
   ~1 mm around. Hence the ring in Chapter 2.
5. **DRV noise** that looked alarming but was not: `clk` with fanout
   34,940 (ideal net before CTS — expected), and the tie-off net at
   fanout 761 (Chapter 4). Learn to sort a DRV report into "fixed by a
   later stage", "setup mistake", and "real" before reacting.
6. **Two script bugs of my own**, worth knowing because they are typical:
   `route_design_*_routing_layer` takes an index, not a name (and `li1`
   is layer 1); and `pkill -f 'innovus.*flow.tcl'` matched the shell
   that was running it. Kill by exact process name (`pgrep -x innovus`).

## Appendix — the pre-CTS −3.8 ns, and how NOT to diagnose it (2026-08-26)

The v2 ring closed placement at **WNS −3.791 ns** (reg2reg; the default
path group was −0.312 ns / 95 paths — ordinary logic nearly closes). A
worked diagnosis, including a wrong turn worth keeping:

1. **First hypothesis: the `li1` RC trap.** Plausible (li1 is 12.8 Ω/sq
   and is a routing layer), so I set `design_*_routing_layer met1/met4`.
   The A/B test — read `04_place.db`, time as-is, then restrict layers +
   `extract_rc` + time again — came back **identical, −3.791 both ways.**
   li1 was not it. *Lesson:* re-extracting RC on an already-placed netlist
   cannot reveal a placement-time modelling error, because the buffers the
   estimate caused are already physical. The A/B test can only exonerate,
   which here it did.
2. **Second hypothesis: the 2.0 macro derate.** `reset_timing_derate` on
   the placed netlist moved WNS −3.791 → −3.532 and surfaced a *different*
   worst path. So the derate is ~0.26 ns, not the driver.
3. **What it actually is: placement locality.** Both failing families run
   from the die perimeter to the centre. (a) The macro read
   `u_sram/dout1 → out_rdata` is a *half-cycle* path (the lib launches
   dout1 on clk1's falling edge → 1.876 ns budget) and place_opt piled
   22 buffers on it. (b) The tag-compare read `rtag_raw_r → out_rdata`
   is 7.257 ns over ~29 gates. In the ring floorplan each way's FTDA read
   logic sits by its macros on the perimeter while `COMPARE_SELECT_REPLACE`
   gathers all four ways centrally, so every read crosses ~half the die;
   the delay appears as cell delay driving long-wire loads, which is why
   layer re-extraction (step 1) never moved it.

*The general lesson:* when a placed design fails and re-extraction does
not change it, the problem is where the cells ARE, not what the wires are
modelled as. The fix is a floorplan that keeps each way's read cone
together with its macros and shrinks the central gather — a v3 region
plan, not a timing-setup tweak.

## Appendix — the route stage: three bugs in one failure (2026-08-26)

`route_design` ran, then `opt_design -post_route` threw and the stage
died. Unpacking it gave three independent fixes, all now in the flow:

1. **47,721 routing DRC violations** (met1–3 ~15k each). Cause: the flow
   reserved met5 entirely for the power grid and capped *signal* routing
   at met4 — only four signal layers, on a design placement had heavily
   buffered. That is not enough routing resource; sky130 flows route
   signals met1–met5 and let signal and power share met5 (the router
   treats PG stripes as obstacles). Fix: `route_design_top_routing_layer 6`.
2. **IMPOPT-6080: "AAE-SI Optimization can only be turned on when the
   timing analysis mode is set to OCV."** Post-route optimisation with SI
   needs on-chip-variation timing mode, even for a single corner. Fix:
   `set_db timing_analysis_type ocv` in init.
3. **The stage died before its `write_db`**, discarding 30 min of
   routing. Fix: checkpoint (`06_route.db`) *immediately after*
   `route_design`+`extract_rc`, before the optimisation that can fail,
   and wrap the opt in `catch` so the routed DB survives a failure.

*The lesson:* a checkpoint belongs after every expensive, irreversible
step — not only at stage boundaries. And "reserve a layer for power" is
free only if you have layers to spare; here it cost 20 % of routing
capacity and a day.
