# Innovus PnR configuration.
#
# Sources the shared synthesis config for the things both flows must agree on -
# PDK paths, design parameters, top name, the run-tree convention - and adds
# only what place-and-route needs on top. No timing constraints live here; they
# are in ../constraints/pnr.sdc, which sources golden.sdc.
#
# Environment overrides (all optional):
#   ASIC_ASSOC              associativity                     (default 4)
#   ASIC_CACHE_BYTES        cache size in bytes               (default 16384)
#   ASIC_NETLIST            gate netlist to place and route   (default: newest
#                           Genus run for this ASSOC that produced one)
#   ASIC_MACRO_SOURCE       vendor | openram                  (default vendor)
#   ASIC_HOLD_LIB           stdcell hold-corner library
#   ASIC_SRAM_MACRO_LIB_FF  macro hold-corner library
#   ASIC_MACRO_DERATE_EARLY early derate on macros, hold corner
#   ASIC_PNR_RUN_STAMP      run directory stamp
#
# See ../README.md for the corner strategy and the sky130 traps this encodes.

set INNOVUS_SCRIPTS_DIR [file normalize [file dirname [info script]]]
set INNOVUS_DIR [file normalize [file dirname $INNOVUS_SCRIPTS_DIR]]
set PNR_DIR     [file normalize [file dirname $INNOVUS_DIR]]
set ASIC_DIR_PNR [file normalize [file dirname $PNR_DIR]]

# ---------------------------------------------------------------------------
# Shared config
# ---------------------------------------------------------------------------
# project_config.tcl validates ASIC_FLOW against {genus, dc} and exits on
# anything else, so it cannot be sourced with ASIC_FLOW=innovus. Neutralise the
# variable across the source and restore it afterwards. This is a workaround for
# a deferred refactor, not a design: see README.md, "Deferred decisions".
set _pnr_saved_flow {}
set _pnr_had_flow 0
if {[info exists ::env(ASIC_FLOW)]} {
    set _pnr_saved_flow $::env(ASIC_FLOW)
    set _pnr_had_flow 1
}
set ::env(ASIC_FLOW) genus

source [file join $ASIC_DIR_PNR synthesis common scripts project_config.tcl]

if {$_pnr_had_flow} {
    set ::env(ASIC_FLOW) $_pnr_saved_flow
} else {
    unset ::env(ASIC_FLOW)
}

# project_config.tcl defaults ASSOC to 8 (the synthesis sweep default). PnR is
# targeting the 16 KB ASSOC=4 build, so default differently here and say so.
if {![info exists ::env(ASIC_ASSOC)] || $::env(ASIC_ASSOC) eq ""} {
    set ASSOC 4
}
# project_config.tcl already derived RUN_TAG from ITS default ASSOC (8), so the
# stage-09 deliverables of the ASSOC=4 run came out named *_assoc8_* (found
# 2026-08-30). Re-derive it from the ASSOC actually in force.
set RUN_TAG ${TOP}_${CACHE_BYTES}B_assoc${ASSOC}
if {$SRAM_MACRO} { set RUN_TAG ${RUN_TAG}_sram }
if {[config_env ASIC_TAG_ONEHOT 0]} { set RUN_TAG ${RUN_TAG}_onehot }

# The Genus netlist's top module is the PARAMETER-UNIQUIFIED name, not "Cache":
# e.g. Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1 (run_genus.tcl tries a list
# of such candidates when it reads the design).  init_design and every later
# restoreDesign need that exact name (first shakedown 2026-08-26).
set TOP ${TOP}_CACHE_BYTES${CACHE_BYTES}_ASSOC${ASSOC}
if {$SRAM_MACRO} { append TOP _EN_SRAM_MACRO1 }

# ---------------------------------------------------------------------------
# Output tree
# ---------------------------------------------------------------------------
#   asic/PnR/innovus/reports/      current run
#                    checkpoints/
#                    outputs/
#                    runs/<stamp>/{reports,checkpoints,outputs,logs,work}
#
# By DEFAULT the flow writes into the top-level reports/, checkpoints/ and
# outputs/ - the layout as drawn.
#
# Setting ASIC_PNR_RUN_STAMP redirects the whole tree into runs/<stamp>/ instead.
# Use it for anything whose numbers get quoted: the default top-level
# directories are OVERWRITTEN by the next run, so two configurations cannot be
# compared unless at least one of them was stamped. (This is the one place the
# drawn layout and this repo's "never blend two runs" discipline pull in
# opposite directions; the stamp is how you get the discipline back.)
#
# NOT under asic/PPA/: that tree belongs to the Genus sweep, and a back-end run
# in it would confuse collect_ppa.py and anyone reading the results table.
#
# .gitignore excludes all four output directories - the scripts and constraints
# under asic/PnR/innovus/ ARE tracked, but the ten .enc stage checkpoints per
# run (hundreds of MB each) emphatically are not.
# Parallelism: the numbered flow never set this, so run 1's 4-5 h stages ran
# on ONE core (FLOORPLAN.md). Default stays 1; the v3 launcher sets 16.
catch {setMultiCpuUsage -localCpu [config_env ASIC_CPUS 1]}

set PNR_RUN_STAMP [config_env ASIC_PNR_RUN_STAMP {}]

if {$PNR_RUN_STAMP eq ""} {
    set PNR_RUN_DIR $INNOVUS_DIR
} else {
    set PNR_RUN_DIR [file join $INNOVUS_DIR runs $PNR_RUN_STAMP]
}
set PNR_REPORT_DIR  [file join $PNR_RUN_DIR reports]
set PNR_CKPT_DIR    [file join $PNR_RUN_DIR checkpoints]
set PNR_OUT_DIR     [file join $PNR_RUN_DIR outputs]
set PNR_LOG_DIR     [file join $PNR_RUN_DIR logs]
set PNR_WORK_DIR    [file join $PNR_RUN_DIR work]

# ---------------------------------------------------------------------------
# Input netlist
# ---------------------------------------------------------------------------
# Default: the most recent Genus run for this ASSOC that actually produced a
# mapped netlist. Pin it explicitly with ASIC_NETLIST for a reproducible run -
# and DO pin it for anything whose numbers get quoted, because "newest" changes
# under you as the campaign runs.
proc pnr_latest_netlist {runs_root} {
    set best {}
    set best_mtime 0
    foreach d [glob -nocomplain -directory $runs_root -type d *] {
        foreach v [glob -nocomplain -directory [file join $d netlist] *_mapped.v] {
            set m [file mtime $v]
            if {$m > $best_mtime} {
                set best_mtime $m
                set best $v
            }
        }
    }
    return $best
}

set PNR_GENUS_RUNS_ROOT [file join $PPA_ROOT genus assoc_$ASSOC runs]
set PNR_NETLIST [config_env ASIC_NETLIST [pnr_latest_netlist $PNR_GENUS_RUNS_ROOT]]

# ---------------------------------------------------------------------------
# Hold corner
# ---------------------------------------------------------------------------
# Fastest silicon, coldest, highest supply - the conventional opposite of the
# ss_100C_1v60 setup corner, and the one project_config.tcl already names. There
# is no temperature inversion at these voltages in sky130 (measured; see
# golden.sdc), so cold really is the fast corner.
set HOLD_LIB [config_env ASIC_HOLD_LIB \
    [file join $STDCELL_ROOT lib sky130_fd_sc_hd__ff_n40C_1v95.lib]]

# ---------------------------------------------------------------------------
# Macro libraries - the one real decision (README.md, "Macro libs")
# ---------------------------------------------------------------------------
#   vendor  - both corners exist, both carry a V/T gap patched by derate.
#   openram - setup lib matches the stdcell corner exactly (no setup derate),
#             but NO hold characterization exists yet (~26 h to produce).
set MACRO_SOURCE [config_env ASIC_MACRO_SOURCE vendor]

set OPENRAM_MACRO_DIR [file join $ASIC_DIR_PNR openram macros_out 32x256]

switch -- $MACRO_SOURCE {
    vendor {
        # SRAM_MACRO_LIB (setup) comes from project_config.tcl.
        set SRAM_MACRO_LIB_FF [config_env ASIC_SRAM_MACRO_LIB_FF \
            [file join $SRAM_MACRO_ROOT lib ${SRAM_MACRO_CELL}_FF_1p8V_25C.lib]]
    }
    openram {
        set SRAM_MACRO_LIB [config_env ASIC_SRAM_MACRO_LIB \
            [file join $OPENRAM_MACRO_DIR \
                openram_sram_1rw1r_32x256_8_SS_1p6V_100C.lib]]
        set SRAM_MACRO_LEF [config_env ASIC_SRAM_MACRO_LEF \
            [file join $OPENRAM_MACRO_DIR openram_sram_1rw1r_32x256_8.lef]]
        # Deliberately has no default: this file does not exist until an FF
        # characterization is run, and silently falling back to the vendored
        # lib would mix two different macros in one MMMC setup.
        set SRAM_MACRO_LIB_FF [config_env ASIC_SRAM_MACRO_LIB_FF {}]
    }
    default {
        puts stderr "ERROR: ASIC_MACRO_SOURCE must be 'vendor' or 'openram', got '$MACRO_SOURCE'"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Macro derates - asymmetric ON PURPOSE (README.md, "Derate asymmetry")
# ---------------------------------------------------------------------------
# SRAM_MACRO_DERATE (late, setup corner) comes from project_config.tcl and is
# 2.0 for the vendored macro. The hold corner needs an EARLY derate on the same
# instances: making cells faster than characterized is what pessimises hold.
# Applying only the late derate leaves hold silently optimistic.
#
# With ASIC_MACRO_SOURCE=openram the setup lib is AT the signoff corner, so the
# late derate should be 1.0 (set ASIC_SRAM_MACRO_DERATE=1.0) - that is the whole
# point of generating the macro. The early derate for the FF corner still
# applies until an FF-corner macro lib exists.
set SRAM_MACRO_DERATE_EARLY [config_env ASIC_MACRO_DERATE_EARLY 0.5]

# ---------------------------------------------------------------------------
# Constraints
# ---------------------------------------------------------------------------
set PNR_SDC [file join $INNOVUS_DIR constraints pnr.sdc]

# ---------------------------------------------------------------------------
# sky130 physical setup
# ---------------------------------------------------------------------------
# Power/ground pin names. NOT VDD/VSS - standard cells use VPWR/VGND plus the
# bulk pins VPB/VNB, and the SRAM macros use their own names. Every one
# needs an explicit globalNetConnect or the design routes with floating power.
# The OpenRAM-generated macro LEF (lef/sram_1rw1r_32_256_8_sky130.lef) declares
# lowercase vdd/gnd - NOT the vccd1/vssd1 of the sky130 1kbyte/2kbyte vendored
# macros. Found the hard way 2026-08-27: vccd1 matched nothing, sroute warned
# IMPSR-1254 "block pins of the VDD net were not found", 16 unpowered SRAMs.
set PG_POWER_NET  [config_env ASIC_PG_POWER_NET VDD]
set PG_GROUND_NET [config_env ASIC_PG_GROUND_NET VSS]
set PG_CELL_POWER_PINS  {VPWR VPB}
set PG_CELL_GROUND_PINS {VGND VNB}
set PG_MACRO_POWER_PINS  {vdd}
set PG_MACRO_GROUND_PINS {gnd}

# Well taps are mandatory in sky130. Endcaps close the rows.
set TAP_CELL      [config_env ASIC_TAP_CELL sky130_fd_sc_hd__tapvpwrvgnd_1]
set TAP_DISTANCE  [config_env ASIC_TAP_DISTANCE 13]
set ENDCAP_CELL   [config_env ASIC_ENDCAP_CELL sky130_fd_sc_hd__decap_3]
set FILLER_CELLS  {sky130_fd_sc_hd__fill_8 sky130_fd_sc_hd__fill_4
                   sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_1}
set DECAP_CELLS   {sky130_fd_sc_hd__decap_12 sky130_fd_sc_hd__decap_8
                   sky130_fd_sc_hd__decap_6 sky130_fd_sc_hd__decap_4
                   sky130_fd_sc_hd__decap_3}

# Carried over from run_genus.tcl: the low-power-flow cells are excluded there
# (level shifters, isolation, some double-height). Placement must honour the
# same list or it will use cells synthesis deliberately refused.
# probe_*/probec_* (DFT current-probe cells) were missing here until
# 2026-09-03: Genus/DC excluded them, but CTS useful-skew on iter16b picked
# six probec_p_8 as delay cells, and their met1 OBS overlapping the rails
# was 24 of the 35 residual verify_drc markers. Same list as synthesis now.
set PNR_DONT_USE_PATTERNS {sky130_fd_sc_hd__lpflow_* sky130_fd_sc_hd__probe_* sky130_fd_sc_hd__probec_*}

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
# Defined here rather than in 00_init.tcl so that a stage restarted on its own
# gets them without re-running init_design.
proc pnr_note {msg} { puts "INFO: $msg" }
proc pnr_fail {msg} { puts stderr "ERROR: $msg" ; exit 1 }

# Report path, grouped by stage:
#
#   reports/
#     init/        analysis_views  check_timing  setup  hold
#     floorplan/   area  utilization
#     power/       connectivity  geometry
#     post_place/  setup  hold  area  congestion  power  welltap  summary
#     post_cts/    setup  hold  clocks  skew  power  summary
#     post_route/  setup  hold  area  power  congestion  census  summary
#     signoff/     setup  hold  area  power  census  connectivity
#                  geometry  antenna  welltap  summary
#
# Same short names in every stage on purpose: comparing two stages, or the same
# stage across two runs, is then a plain diff of identically-named files.
proc pnr_ckpt {name} {
    global PNR_CKPT_DIR
    return [file join $PNR_CKPT_DIR $name]
}

proc pnr_out {name} {
    global PNR_OUT_DIR
    return [file join $PNR_OUT_DIR $name]
}

proc pnr_rpt {stage name} {
    global PNR_REPORT_DIR
    set d [file join $PNR_REPORT_DIR $stage]
    file mkdir $d
    return [file join $d $name]
}

foreach _d [list $PNR_REPORT_DIR $PNR_CKPT_DIR $PNR_OUT_DIR \
                 $PNR_LOG_DIR $PNR_WORK_DIR] {
    file mkdir $_d
}

# Self-describing runs (2026-09-02, after arms B and C silently duplicated):
# snapshot every ASIC_* launch knob into the run dir each time the config is
# sourced. Append-mode with a timestamped header, so restarts and same-dir
# arm scripts each leave their own record instead of overwriting history.
if {![catch {open [file join $PNR_RUN_DIR knobs.txt] a} _kf]} {
    puts $_kf "# [clock format [clock seconds] -format %Y-%m-%d_%H:%M:%S] pid [pid] script [info script]"
    foreach _kv [lsort [array names ::env ASIC_*]] {
        puts $_kf "$_kv=$::env($_kv)"
    }
    close $_kf
}

# Restore a previous stage's database, with the failure mode spelled out.
#
# The trap this guards: PNR_RUN_STAMP defaults to the CURRENT time, so a stage
# restarted on its own lands in a brand-new empty run directory and finds no
# database. Restarting mid-flow means pinning the stamp:
#
#   ASIC_PNR_RUN_STAMP=<the original stamp> ASIC_PNR_FROM=05 innovus -files ...
proc pnr_restore_stage {enc_name} {
    global PNR_CKPT_DIR TOP PNR_RUN_STAMP
    set enc [file join $PNR_CKPT_DIR $enc_name]
    if {![file exists $enc] && ![file exists ${enc}.dat]} {
        pnr_fail "no database at $enc\n\
                 \  Run the earlier stages first, or - if you are resuming a\n\
                 \  STAMPED run - re-run with ASIC_PNR_RUN_STAMP=<that stamp>\n\
                 \  so the flow looks in runs/<stamp>/ instead of the\n\
                 \  top-level checkpoints/."
    }
    # saveDesign X.enc writes a small X.enc loader plus the real session
    # directory X.enc.dat/; restoreDesign (Innovus 21) wants the DIRECTORY
    # (IMPSYT-7338 with the bare .enc name - first shakedown 2026-08-26).
    restoreDesign ${enc}.dat $TOP
    pnr_note "restored ${enc_name}.dat"
}
