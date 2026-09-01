# Stage 00 - init: configuration, MMMC, physical/logical data, design init.
#
#   innovus -files scripts/00_init.tcl        (or source it from the GUI)
#
# Every later stage assumes this one ran. Stages restore the previous stage's
# database rather than re-running it, so a failed route does not cost a
# placement (see run_innovus.tcl).

set _here [file normalize [file dirname [info script]]]

source [file join $_here innovus_config.tcl]

# Run directories and the pnr_* helpers come from innovus_config.tcl.

if {$PNR_NETLIST eq "" || ![file readable $PNR_NETLIST]} {
    pnr_fail "netlist not readable: '$PNR_NETLIST'\n\
             \  Set ASIC_NETLIST to a Genus mapped netlist, e.g.\n\
             \  PPA/genus/assoc_$ASSOC/runs/<stamp>/netlist/${RUN_TAG}_mapped.v"
}

pnr_note "top            : $TOP"
pnr_note "CACHE_BYTES    : $CACHE_BYTES   ASSOC: $ASSOC"
pnr_note "netlist        : $PNR_NETLIST"
pnr_note "macro source   : $MACRO_SOURCE  (SRAM_MACRO=$SRAM_MACRO)"
pnr_note "setup lib      : $SIGNOFF_LIB"
pnr_note "hold  lib      : $HOLD_LIB"
pnr_note "run dir        : $PNR_RUN_DIR"

# ---------------------------------------------------------------------------
# Physical libraries
# ---------------------------------------------------------------------------
# Tech LEF first, then cell LEF, then macro LEF. The PDK ships min/nom/max tech
# LEFs; only one can be loaded for a design, so RC variation across corners is
# handled by the rc_corner scaling factors in mmmc.tcl, not by swapping this.
set _lefs [list $TECH_LEF $CELL_LEF]
if {$SRAM_MACRO} { lappend _lefs $SRAM_MACRO_LEF }

foreach f $_lefs {
    if {![file readable $f]} { pnr_fail "LEF not readable: $f" }
}

set init_lef_file $_lefs
set init_verilog  $PNR_NETLIST
set init_top_cell $TOP
set init_design_netlisttype "Verilog"
set init_design_settop 1

# Power/ground nets. The pin-level connections happen in 02_power.tcl; these
# two names are what the netlist's PG nets are called at the top level.
set init_pwr_net $PG_POWER_NET
set init_gnd_net $PG_GROUND_NET

# ---------------------------------------------------------------------------
# MMMC - handed to init_design, which sources the file itself so the design
# comes up multi-corner.  Do NOT source mmmc.tcl directly here as well: its
# final set_analysis_view is only legal inside/after init_design
# (TCLCMD-1230, first shakedown 2026-08-26).  The pnr_apply_macro_derates
# proc it defines is still available afterwards - init_design sources the
# file into this same interpreter.
# ---------------------------------------------------------------------------
set init_mmmc_file [file join $_here mmmc.tcl]

init_design

# ---------------------------------------------------------------------------
# Post-init setup
# ---------------------------------------------------------------------------
# Tell the tool the real process. Unset, Innovus assumes its 90nm default
# ("Both design process and tech node are not set" in the load log) and tunes
# extraction filtering and optimization heuristics for that. The LEF still
# governs all actual design rules; this only calibrates heuristics. sky130 has
# no Cadence -node calibration entry, so only -process is set.
setDesignMode -process 130
# Exclude li1 (12.8 ohm/sq) from routing AND from all wire-RC estimation, from
# the very start - the discarded flow measured -4..-9 ns/path of li1 pessimism.
# INT layer numbers: li1=1, met1=2 ... met5=6.
setDesignMode -bottomRoutingLayer 2 -topRoutingLayer 6
# Carry synthesis's cell exclusions into placement. run_genus.tcl excludes the
# lpflow_* family (level shifters, isolation cells, some double-height); if
# placement is allowed to use them, PnR inserts cells synthesis deliberately
# refused and the netlists stop corresponding.
# get_lib_cells returns a COLLECTION (one opaque handle such as 0x1), not a
# Tcl list - a plain foreach iterates once over the handle and TCLCMD-917s.
# foreach_in_collection is the SDC-style iterator (first shakedown 2026-08-26).
foreach pat $PNR_DONT_USE_PATTERNS {
    set _n 0
    foreach_in_collection c [get_lib_cells -quiet $pat] {
        set_dont_use [get_object_name $c] true
        incr _n
    }
    pnr_note "dont_use applied: $pat ($_n lib cells)"
}

# Macro derates - asymmetric across setup/hold (see mmmc.tcl). Must run after
# init_design because it resolves actual instances.
pnr_apply_macro_derates

# A sanity report before anything is placed: if the corner setup is wrong, it is
# cheaper to find out here than after an hour of placement.
report_analysis_views > [pnr_rpt init analysis_views.rpt]
check_timing -verbose  > [pnr_rpt init check_timing.rpt]
report_timing -late  -max_paths 10 > [pnr_rpt init setup.rpt]
report_timing -early -max_paths 10 > [pnr_rpt init hold.rpt]

saveDesign [pnr_ckpt 00_init.enc]
pnr_note "stage 00 (init) complete"
