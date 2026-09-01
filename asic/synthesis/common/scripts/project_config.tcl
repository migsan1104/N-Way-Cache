# Shared cache synthesis configuration.
# This file intentionally contains no tool-specific synthesis commands and no
# timing constraints. All constraints live in constraints/golden.sdc.
#
# Design parameters and the clock target are overridable from the environment so
# a sweep can be run without editing this file:
#
#   ASIC_ASSOC              associativity              (default 8)
#   ASIC_CACHE_BYTES        cache size in bytes        (default 16384)
#   ASIC_CLOCK_PERIOD_NS    reported clock target      (default 3.500)
#   ASIC_RUN_STAMP          run directory stamp        (default: generated)
#   ASIC_STOP_AFTER_SETUP   1 = stop before synthesis   (default 0)
#
# ASIC_CLOCK_PERIOD_NS is used only for run bookkeeping and the summary report.
# The clock the tools actually optimize against is the one in golden.sdc; if you
# change the period, change it there.
#
# ASIC_FLOW selects which per-tool output tree the run writes into and is set by
# the launcher scripts (run_genus.sh -> genus, run_dc.sh -> dc).

set CONFIG_DIR [file normalize [file dirname [info script]]]
set COMMON_DIR [file normalize [file dirname $CONFIG_DIR]]
set SYNTH_DIR [file normalize [file dirname $COMMON_DIR]]
set ASIC_DIR [file normalize [file dirname $SYNTH_DIR]]
set REPO_ROOT [file normalize [file dirname $ASIC_DIR]]

proc config_env {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default
}

set TOP Cache

set CACHE_BYTES [config_env ASIC_CACHE_BYTES 16384]
set ASSOC [config_env ASIC_ASSOC 8]

if {![string is integer -strict $ASSOC] || $ASSOC < 1} {
    puts stderr "ERROR: ASIC_ASSOC must be a positive integer, got '$ASSOC'"
    exit 1
}
if {![string is integer -strict $CACHE_BYTES] || $CACHE_BYTES < 1} {
    puts stderr "ERROR: ASIC_CACHE_BYTES must be a positive integer, got '$CACHE_BYTES'"
    exit 1
}

set CLOCK_PORT clk
set RESET_PORT rst

# Bookkeeping only - the authoritative period is in golden.sdc.
set CLOCK_PERIOD_NS [config_env ASIC_CLOCK_PERIOD_NS 3.500]

set SRC_DIR [file join $REPO_ROOT src]
set CONSTRAINT_DIR [file join $COMMON_DIR constraints]
set FILELIST_DIR [file join $COMMON_DIR filelists]

# The one constraints file both tools read.
set GOLDEN_SDC [file join $CONSTRAINT_DIR golden.sdc]

# ---------------------------------------------------------------------------
# PDK
# ---------------------------------------------------------------------------
set PDK_ROOT [config_env ASIC_PDK_ROOT \
    /apps/cds/IC618/local/opdk/share/pdk/sky130A]
set STDCELL_ROOT [file join $PDK_ROOT libs.ref sky130_fd_sc_hd]

# Setup-timing signoff corner: slow process, 1.60 V, 100 C.
#
# sky130_fd_sc_hd is a 1.8 V nominal library, so 1.60 V is nominal minus about
# 10% for supply droop - the real worst-case operating point for this block. The
# PDK also ships ss corners down to 1.28 V, but those are deep-undervolt
# characterizations, not a signoff point for a design that runs at 1.8 V.
#
# The temperature was picked by measurement with voltage held fixed, so that
# temperature and voltage are not confounded. Interpolating inv_1 cell_fall at
# 0.10 ns input slew and 0.05 pF load:
#
#     ss_n40C_1v60   0.2973 ns
#     ss_100C_1v60   0.3782 ns   <- slower by 1.272x
#
# The same comparison at a fixed 1.40 V agrees (0.5050 ns hot vs 0.4145 ns
# cold), so there is no temperature inversion at these voltages: hot is slower,
# the conventional way round. For reference this corner is 1.76x tt_025C_1v80.
#
# ONE corner only at synthesis. Hold is not fixed pre-CTS, so a fast corner adds
# nothing at this stage; multi-corner analysis (setup here, hold at
# ff_n40C_1v95) is configured in Innovus at CTS.
set SIGNOFF_LIB [config_env ASIC_SIGNOFF_LIB \
    [file join $STDCELL_ROOT lib sky130_fd_sc_hd__ss_100C_1v60.lib]]

# Physical data for wire-load estimation. Without these the synthesizer has no
# geometry and reports zero net delay and zero net area.
set TECH_LEF [config_env ASIC_TECH_LEF \
    [file join $STDCELL_ROOT techlef sky130_fd_sc_hd__nom.tlef]]
set CELL_LEF [config_env ASIC_CELL_LEF \
    [file join $STDCELL_ROOT lef sky130_fd_sc_hd.lef]]

# ---------------------------------------------------------------------------
# Optional SRAM hard macro for the data banks (ASIC_SRAM_MACRO=1).
# Corner decision recorded in asic/MACROS.md (2026-08-20): the macro's only
# slow lib is SS_1p8V_25C; signoff cells stay at ss_100C_1v60 and the V/T gap
# is enveloped by a x2.0 late derate on the macro instances (data-derived
# from the macro's TT sensitivity family). The TT_1p8V_100C lib is BROKEN
# (7.8 ns garbage) - never link it.
set SRAM_MACRO [config_env ASIC_SRAM_MACRO 0]
set SRAM_MACRO_ROOT [config_env ASIC_SRAM_MACRO_ROOT \
    /apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_sram_macros]
set SRAM_MACRO_CELL sram_1rw1r_32_256_8_sky130
set SRAM_MACRO_LIB [config_env ASIC_SRAM_MACRO_LIB \
    [file join $SRAM_MACRO_ROOT lib ${SRAM_MACRO_CELL}_SS_1p8V_25C.lib]]
set SRAM_MACRO_LEF [config_env ASIC_SRAM_MACRO_LEF \
    [file join $SRAM_MACRO_ROOT lef ${SRAM_MACRO_CELL}.lef]]
set SRAM_MACRO_DERATE [config_env ASIC_SRAM_MACRO_DERATE 2.0]

# ---------------------------------------------------------------------------
# Floorplan (drives physical-layout estimation, not a real floorplan)
# ---------------------------------------------------------------------------
set FP_SITE [config_env ASIC_FP_SITE unithd]
set FP_ASPECT_RATIO [config_env ASIC_FP_ASPECT_RATIO 1.0]
set FP_ROW_DENSITY [config_env ASIC_FP_ROW_DENSITY 0.65]
set FP_MARGIN [config_env ASIC_FP_MARGIN 10]

# ---------------------------------------------------------------------------
# Output tree
# ---------------------------------------------------------------------------
# Per-tool, per-associativity results tree. Mirrors openflex/PPA/assoc_<N>/ so
# both the FPGA and ASIC flows are read the same way.
set PPA_ROOT [file join $ASIC_DIR PPA]

set ASIC_FLOW [config_env ASIC_FLOW genus]
switch -- $ASIC_FLOW {
    genus - dc {}
    default {
        puts stderr "ERROR: ASIC_FLOW must be 'genus' or 'dc', got '$ASIC_FLOW'"
        exit 1
    }
}

set RUN_DIR [file join $PPA_ROOT $ASIC_FLOW assoc_$ASSOC]

# Every run writes into its own stamped directory so results can never be a
# blend of two runs, and so an older run stays available for comparison.
# runs/latest is a symlink maintained by the launcher script.
set RUN_STAMP [config_env ASIC_RUN_STAMP [clock format [clock seconds] -format %Y%m%d_%H%M%S]]
set RUNS_ROOT [file join $RUN_DIR runs]
set OUT_DIR [file join $RUNS_ROOT $RUN_STAMP]

set REPORT_DIR [file join $OUT_DIR reports]
set NETLIST_DIR [file join $OUT_DIR netlist]
set DB_DIR [file join $OUT_DIR db]
set LOG_DIR [file join $OUT_DIR logs]
set WORK_DIR [file join $OUT_DIR work]

# Basename shared by every artifact a run produces, so netlists from different
# configurations can never be confused with one another.
set RUN_TAG ${TOP}_${CACHE_BYTES}B_assoc${ASSOC}
if {$SRAM_MACRO} { set RUN_TAG ${RUN_TAG}_sram }
if {[config_env ASIC_TAG_ONEHOT 0]} { set RUN_TAG ${RUN_TAG}_onehot }

set STOP_AFTER_SETUP [config_env ASIC_STOP_AFTER_SETUP 0]
