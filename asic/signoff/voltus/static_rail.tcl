# static_rail.tcl - voltus.md step 2: static power + static IR on a routed
# Innovus checkpoint, tech-only PGV (LEF-based cell views, accuracy xd).
# First run 2026-09-04 on iter16b 06_final.enc. Env: ASIC_PNR_RUN_STAMP,
# SIGNOFF_RESULTS (signoff/env.sh), optional VOLTUS_CKPT (default 06_final.enc).
set REPO   /ecel/UFAD/miguel.sanchez1/Cache
set STAMP  $env(ASIC_PNR_RUN_STAMP)
set RUN    $REPO/asic/PnR/innovus/runs/$STAMP
set PGV    $REPO/asic/signoff/voltus/pgv/techonly/techonly.cl
set OUT    $env(SIGNOFF_RESULTS)/voltus[expr {[info exists env(VOLTUS_TAG)] && $env(VOLTUS_TAG) ne "" ? "_$env(VOLTUS_TAG)" : ""}]
set VDD_V  1.76
set IR_BUDGET_FRAC 0.03      ;# voltus.md step 3: <= 3 % static drop
file mkdir $OUT $OUT/power $OUT/rail
catch {setMultiCpuUsage -localCpu 8}     ;# licence allows 8

# Load the design the documented way (LEF + MMMC + netlist + DEF), not by
# restoring the Innovus DB: Voltus 23 restoring an Innovus 21 checkpoint lost
# the floorplan and the rail connections (IMPFP-10172, "2 power/gnd nets not
# connected", VDD read as 1.6 V from the DB's libs) on the first attempt.
# innovus_config.tcl gives TOP, the LEFs, PG pin lists and SIGNOFF_LIB (corner
# from ASIC_SIGNOFF_LIB); mmmc.tcl builds setup_view / hold_view from them.
source $REPO/asic/PnR/innovus/scripts/innovus_config.tcl
set netlist [file join $PNR_OUT_DIR ${RUN_TAG}_pnr.v]
set def     [file join $PNR_OUT_DIR ${RUN_TAG}_pnr.def]
set spef    [file join $PNR_OUT_DIR ${RUN_TAG}_pnr.spef]
foreach f [list $netlist $def $spef $PGV] { if {![file exists $f]} { error "static_rail: missing $f" } }
set _lefs [list $TECH_LEF $CELL_LEF]
if {[info exists SRAM_MACRO_LEF] && [file readable $SRAM_MACRO_LEF]} { lappend _lefs $SRAM_MACRO_LEF }
# NOT init_design: that is the Innovus/Tempus initialisation and it puts
# Voltus into "timer mode", where defIn is ignored and read_def refuses
# ("read_def cannot be used in timer mode", attempts 4-5). The Voltus UG
# sequence is read_lib / read_view_definition / read_verilog /
# set_top_module / read_def. mmmc.tcl needs innovus_config.tcl's variables,
# which are already in this interpreter.
read_lib -lef $_lefs
read_view_definition $REPO/asic/PnR/innovus/scripts/mmmc.tcl
read_verilog $netlist
set_top_module $TOP -ignore_undefined_cell
read_def $def
foreach pin $PG_CELL_POWER_PINS  { globalNetConnect $PG_POWER_NET  -type pgpin -pin $pin -inst * -override }
foreach pin $PG_CELL_GROUND_PINS { globalNetConnect $PG_GROUND_NET -type pgpin -pin $pin -inst * -override }
if {$SRAM_MACRO} {
    foreach pin $PG_MACRO_POWER_PINS  { globalNetConnect $PG_POWER_NET  -type pgpin -pin $pin -inst * -override }
    foreach pin $PG_MACRO_GROUND_PINS { globalNetConnect $PG_GROUND_NET -type pgpin -pin $pin -inst * -override }
}
globalNetConnect $PG_POWER_NET  -type tiehi -inst * -override
globalNetConnect $PG_GROUND_NET -type tielo -inst * -override
pnr_apply_macro_derates
# read_spef, not spefIn: the alias silently did nothing here (power step
# reported "Parasitics Mode: No SPEF/RCDB" through attempt 4).
read_spef -rc_corner rc_slow $spef
set_analysis_view -setup {setup_view} -hold {hold_view}
puts "VOLTUS: design loaded from LEF/MMMC/netlist/DEF, PG rails connected"

# --- static power (vectorless: default toggle rates; no VCD exists) ---
set_default_switching_activity -input_activity 0.2 -period 4.0 -clock_gates_output_ratio 0.5
set_power_analysis_mode -reset
set_power_analysis_mode -method static -analysis_view setup_view -corner max \
    -write_static_currents true -create_binary_db true -binary_db_name staticPower.db
set_power_output_dir $OUT/power
report_power -outfile $OUT/power/static_power.rpt
puts "VOLTUS: static power done -> $OUT/power"

# --- supply entry: the PG ring, declared as the source (no package model) ---
# Ring centrelines from the exported DEF: VDD met4 y=11.98 / 2886.86 (x 10.1..
# 2889.74), met5 x=12.1 / 2887.74 (y 9.98..2888.86); VSS ring 6 um outside.
# Attempt 6 used ONE source per side: 81 mA per source through a 4 um ring
# put 0.22 V across met5 before any stripe - an entry-point artefact, not the
# grid. VOLTUS_VSRC_PITCH (um, default 50) spreads sources along all four
# sides (~230 per net), i.e. "the ring is the supply", which is the honest
# block-level statement when no package exists.
set PITCH [expr {[info exists env(VOLTUS_VSRC_PITCH)] ? double($env(VOLTUS_VSRC_PITCH)) : 50.0}]
proc _ring_pp {file net xw xe ys yn pitch} {
    set f [open $file w]; set n 0
    puts $f "* vsrc name X(um) Y(um) layer  (ring-as-supply, pitch $pitch um)"
    for {set y 30.0} {$y <= 2870.0} {set y [expr {$y + $pitch}]} {
        puts $f "${net}_W[incr n] $xw $y met5"; puts $f "${net}_E[incr n] $xe $y met5"
    }
    for {set x 30.0} {$x <= 2870.0} {set x [expr {$x + $pitch}]} {
        puts $f "${net}_S[incr n] $x $ys met4"; puts $f "${net}_N[incr n] $x $yn met4"
    }
    close $f; return $n
}
puts "VOLTUS: [_ring_pp $OUT/rail/vdd.pp VDD 12.1 2887.74 11.98 2886.86 $PITCH] VDD sources, [_ring_pp $OUT/rail/vss.pp VSS 6.1 2893.74 5.98 2892.86 $PITCH] VSS sources (pitch $PITCH um)"

# techonly always; the LEF-only macro views (pgv_macros.tcl) if they exist,
# so the 16 SRAMs' current (~1/3 of the total) takes part in the solve.
set PGVS [list $PGV]
foreach _m [glob -nocomplain [file dirname [file dirname $PGV]]/macros/*.cl] { lappend PGVS $_m }
puts "VOLTUS: power-grid libraries: $PGVS"
set_pg_nets -net VDD -voltage $VDD_V -threshold [expr {$VDD_V * (1.0 - $IR_BUDGET_FRAC)}]
set_pg_nets -net VSS -voltage 0.0    -threshold [expr {$VDD_V * $IR_BUDGET_FRAC}]
# VOLTUS_WHATIF_M5_PITCH (um): trial horizontal met5 VDD/VSS straps across
# the whole core (over the macro ring) at that pitch, width 2 / spacing 2,
# as Voltus what-if shapes - the iter17 PDN candidate, sized here on the
# routed iter16b database before anything is re-routed (2026-09-04).
set _wi 0
if {[info exists env(VOLTUS_WHATIF_M5_PITCH)] && $env(VOLTUS_WHATIF_M5_PITCH) ne ""} {
    set _wp [expr {double($env(VOLTUS_WHATIF_M5_PITCH))}]
    # VOLTUS_WHATIF_M5_WIDTH (um, default 2): the headroom knob - iter17
    # fallback sizing (2026-09-04 20:40): 4 um at 120 and at 60 um pitch.
    set _ww [expr {[info exists env(VOLTUS_WHATIF_M5_WIDTH)] && $env(VOLTUS_WHATIF_M5_WIDTH) ne "" ? double($env(VOLTUS_WHATIF_M5_WIDTH)) : 2.0}]
    create_what_if_shape -type wire -nets {VDD VSS} -layer met5 -direction hor \
        -area {16 16 2884 2884} -pitch $_wp -width $_ww -spacing 2 -add
    # Wires alone float (first trial: +224 resistors, drop unchanged). Vias on
    # every met4/met5 crossing in the area tie the straps to the ring and to
    # the existing met4 stripes.
    foreach _n {VDD VSS} {   ;# VOLTUS_ERA-3058: vias are one net per call
        create_what_if_shape -type via -nets $_n -layer {met4 met5} -method auto \
            -area {16 16 2884 2884} -add
    }
    set _wi 1
    puts "VOLTUS: what-if met5 horizontal VDD/VSS straps, pitch $_wp um, width $_ww um, over the full core"
}
set _em {}
if {[info exists env(VOLTUS_EM_ICT)] && [file readable $env(VOLTUS_EM_ICT)]} {
    # EM limits (EM-only ICT). With em_models_assumed.ict this is a SCREEN
    # against assumed limits (see that file's header), not signoff. The
    # options must ride on the one set_rail_analysis_mode call (IMPTCM-113).
    set _em [list -process_techgen_em_rules true -ict_em_models $env(VOLTUS_EM_ICT) -em_temperature [expr {[info exists env(VOLTUS_EM_TEMP)] && $env(VOLTUS_EM_TEMP) ne "" ? $env(VOLTUS_EM_TEMP) : 110}]]
    puts "VOLTUS: EM analysis ON with limits from $env(VOLTUS_EM_ICT) (assumed limits => screen only)"
}
set_rail_analysis_mode -method static -accuracy xd -analysis_view setup_view \
    -power_grid_library $PGVS -temperature 100 -verbosity true \
    -import_what_if_shapes [expr {$_wi ? "true" : "false"}] {*}$_em
set_power_data -reset
set_power_data -format current [glob $OUT/power/static_*.ptiavg]
set_power_pads -net VDD -format xy -file $OUT/rail/vdd.pp
set_power_pads -net VSS -format xy -file $OUT/rail/vss.pp
# -type net takes ONE net (a list gives "wrong # args: check_rail_files").
foreach _n {VDD VSS} {
    analyze_rail -output $OUT/rail/$_n -type net $_n
    puts "VOLTUS: rail analysis of $_n done -> $OUT/rail/$_n"
}
puts "VOLTUS: static rail done -> $OUT/rail"
exit
