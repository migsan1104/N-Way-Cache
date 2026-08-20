# ============================================================================
# Cadence Genus synthesis flow for the parameterized cache.
#
# This is a physically-aware (iSpatial) flow. It exists to produce numbers that
# correlate with place-and-route, not to produce the best-looking QoR:
#
#   * setup timing is analysed at ss_100C_1v60, not at typical
#   * LEF + a floorplan are loaded so interconnect is estimated instead of being
#     assumed to be zero
#   * every constraint comes from constraints/golden.sdc and nowhere else
#   * every run ends with the same fixed report set
#
# SINGLE CORNER. No MMMC is configured here. Hold is not fixed before CTS, so a
# fast corner would contribute nothing at this stage; setup at ss_100C_1v60 plus
# hold at ff_n40C_1v95 gets configured in Innovus when CTS runs. Consequently
# every number this flow reports - including power - comes from ss_100C_1v60.
#
# Nothing in this script defines a timing constraint. If you need to change the
# clock, the uncertainty, or an I/O budget, change golden.sdc.
# ============================================================================

set SCRIPT_DIR  [file normalize [file dirname [info script]]]
set CADENCE_DIR [file normalize [file dirname $SCRIPT_DIR]]
set SYNTH_DIR   [file normalize [file dirname $CADENCE_DIR]]

source [file join $SYNTH_DIR common scripts project_config.tcl]
source [file join $FILELIST_DIR rtl_files.tcl]

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
proc fail {msg} {
    puts stderr "ERROR: $msg"
    exit 1
}

proc note {msg} {
    puts "INFO: $msg"
}

# Write a report, but never let a reporting failure kill a multi-hour run.
proc safe_report {path body} {
    if {[catch {redirect $path $body} msg]} {
        puts stderr "WARNING: failed to create [file tail $path]: $msg"
        if {[catch {
            set fh [open $path w]
            puts $fh "Report command failed:"
            puts $fh $msg
            close $fh
        } write_msg]} {
            puts stderr "WARNING: unable to write placeholder $path: $write_msg"
        }
    }
}

proc require_file {path label} {
    if {![file exists $path]} {
        fail "$label does not exist: $path"
    }
    if {![file readable $path]} {
        fail "$label is not readable: $path"
    }
}

proc absolutize_rtl_files {rtl_files repo_root} {
    set files [list]
    foreach rtl $rtl_files {
        set abs [file normalize [file join $repo_root $rtl]]
        if {![file exists $abs]} {
            fail "RTL file does not exist: $rtl"
        }
        lappend files $abs
    }
    if {[llength $files] == 0} {
        fail "RTL file list is empty"
    }
    return $files
}

foreach d [list $REPORT_DIR $NETLIST_DIR $DB_DIR $LOG_DIR $WORK_DIR] {
    file mkdir $d
}

require_file $SIGNOFF_LIB "signoff timing library"
require_file $TECH_LEF    "technology LEF"
require_file $CELL_LEF    "standard cell LEF"
require_file $GOLDEN_SDC  "golden SDC"

if {$SRAM_MACRO} {
    require_file $SRAM_MACRO_LIB "SRAM macro timing library"
    require_file $SRAM_MACRO_LEF "SRAM macro LEF"
    note "SRAM macro enabled      : $SRAM_MACRO_CELL"
    note "SRAM macro liberty      : $SRAM_MACRO_LIB"
    note "SRAM macro LEF          : $SRAM_MACRO_LEF"
    note "SRAM macro late derate  : $SRAM_MACRO_DERATE"
}

set ABS_RTL_FILES [absolutize_rtl_files $RTL_FILES $REPO_ROOT]

note "signoff (setup) library : $SIGNOFF_LIB"
note "technology LEF          : $TECH_LEF"
note "standard cell LEF       : $CELL_LEF"
note "golden SDC              : $GOLDEN_SDC"
note "output directory        : $OUT_DIR"

# ---------------------------------------------------------------------------
# Timing setup - ONE corner.
#
# These are MMMC commands, and that is not a contradiction of the single-corner
# intent. Genus enforces an initialization sequence:
#
#   uninitialized -> timing_initialized -> physical_initialized -> ...
#
# read_physical requires state 'timing_initialized', and the ONLY way to reach
# it is by declaring a library set, a delay corner and an analysis view. The
# legacy 'set_db library' path leaves the tool 'uninitialized', so LEF cannot be
# loaded and physical synthesis is impossible. Loading LEF is what makes net
# delay nonzero, so this sequence is mandatory.
#
# What matters is that exactly ONE of each object exists: one library set, one
# timing condition, one delay corner, one constraint mode, one analysis view.
# There is no fast corner and no second view. Setup and hold both point at the
# same view because set_analysis_view requires a hold view to be named, not
# because hold is being analysed meaningfully - hold is not fixed before CTS.
# ---------------------------------------------------------------------------
note "Setting up the single timing corner"
set_db init_lib_search_path [list [file dirname $SIGNOFF_LIB]]

# The setup is written to an MMMC FILE rather than issued as inline commands,
# and that is not cosmetic. syn_opt -spatial escalates to
# 'opt_spatial_effort extreme', and Genus rejects extreme effort when the corner
# setup came from inline commands:
#
#   Use of 'opt_spatial_effort extreme' without an MMMC file requires a
#   limited access feature. [PHYS-1017]
#   Limited access feature 'ispatial_single_corner' is unavailable. [LIC-5]
#
# That limited-access licence is not available at this site, so an inline setup
# kills the run after mapping. Reading the identical content from a file is
# accepted. It is still exactly ONE corner - one library set, one timing
# condition, one delay corner, one constraint mode, one analysis view.
#
# The file is written into the run directory so each run records the exact
# corner setup it used.
set MMMC_FILE [file join $OUT_DIR mmmc.tcl]
if {[catch {
    set mh [open $MMMC_FILE w]
    puts $mh "# Generated by run_genus.tcl - single corner setup."
    puts $mh "# Timing library and constraints come from project_config.tcl / golden.sdc."
    set TIMING_LIBS $SIGNOFF_LIB
    if {$SRAM_MACRO} { lappend TIMING_LIBS $SRAM_MACRO_LIB }
    puts $mh "create_library_set -name ss_libs -timing {$TIMING_LIBS}"
    puts $mh "create_timing_condition -name ss_cond -library_sets {ss_libs}"
    puts $mh "create_delay_corner -name ss_corner -timing_condition ss_cond"
    puts $mh "create_constraint_mode -name func -sdc_files {$GOLDEN_SDC}"
    puts $mh "create_analysis_view -name ss_view -constraint_mode func -delay_corner ss_corner"
    puts $mh "set_analysis_view -setup {ss_view} -hold {ss_view}"
    close $mh
} msg]} {
    fail "unable to write MMMC file $MMMC_FILE: $msg"
}
note "Wrote single-corner MMMC file: $MMMC_FILE"

if {[catch {read_mmmc $MMMC_FILE} msg]} {
    fail "read_mmmc failed on $MMMC_FILE: $msg"
}

# ---------------------------------------------------------------------------
# Physical data
# ---------------------------------------------------------------------------
note "Reading physical libraries (LEF)"
set LEF_FILES [list $TECH_LEF $CELL_LEF]
if {$SRAM_MACRO} { lappend LEF_FILES $SRAM_MACRO_LEF }
if {[catch {read_physical -lefs $LEF_FILES} msg]} {
    fail "read_physical failed: $msg"
}

# ---------------------------------------------------------------------------
# RTL
# ---------------------------------------------------------------------------
note "Reading RTL as SystemVerilog"
set HDL_DEFINES [list]
if {$SRAM_MACRO} { lappend HDL_DEFINES SRAM_MACRO_BANKS }
if {[llength $HDL_DEFINES]} {
    note "read_hdl defines: $HDL_DEFINES"
    set read_cmd [list read_hdl -sv -define $HDL_DEFINES]
} else {
    set read_cmd [list read_hdl -sv]
}
if {[catch {{*}$read_cmd $ABS_RTL_FILES} msg]} {
    fail "read_hdl failed: $msg"
}

set ELAB_PARAMETERS [list \
    [list CACHE_BYTES $CACHE_BYTES] \
    [list ASSOC $ASSOC] \
]

note "Elaborating $TOP with parameters: $ELAB_PARAMETERS"
if {[catch {elaborate -parameters $ELAB_PARAMETERS $TOP} msg]} {
    fail "elaboration failed with CACHE_BYTES=$CACHE_BYTES ASSOC=$ASSOC: $msg"
}

set ELAB_TOP ${TOP}_CACHE_BYTES${CACHE_BYTES}_ASSOC${ASSOC}
if {[catch {current_design $ELAB_TOP} msg]} {
    if {[catch {current_design $TOP} msg2]} {
        fail "unable to set current design to $ELAB_TOP or $TOP: $msg ; $msg2"
    }
}

# ---------------------------------------------------------------------------
# Apply the constraint mode (and therefore golden.sdc) to the elaborated design.
# ---------------------------------------------------------------------------
note "Initialising design (applies $GOLDEN_SDC)"
if {[catch {init_design} msg]} {
    fail "init_design failed: $msg"
}

# ---------------------------------------------------------------------------
# SRAM macro checks + corner-gap derate (see asic/MACROS.md).
# The run FAILS if macros were requested but the RTL fell back to flops
# (geometry mismatch) - a silent fallback would report flop-bank numbers
# under an _sram run tag.
# ---------------------------------------------------------------------------
if {$SRAM_MACRO} {
    set MACRO_INSTS [get_db insts -if ".base_cell.name == $SRAM_MACRO_CELL"]
    set MACRO_COUNT [llength $MACRO_INSTS]
    note "SRAM macro instances     : $MACRO_COUNT"
    if {$MACRO_COUNT == 0} {
        fail "ASIC_SRAM_MACRO=1 but zero $SRAM_MACRO_CELL instances elaborated (bank geometry must be 256x32 - CACHE_BYTES=16384 ASSOC=4)"
    }
    if {[catch {set_timing_derate -delay_corner ss_corner -late $SRAM_MACRO_DERATE $MACRO_INSTS} msg]} {
        fail "unable to apply SRAM macro derate: $msg"
    }
    note "Applied x$SRAM_MACRO_DERATE late derate to $MACRO_COUNT macro instances"
}

# ---------------------------------------------------------------------------
# Floorplan + interconnect estimation
#
# This is what removes the zero-net-delay problem. Without a floorplan Genus has
# no geometry to estimate wirelength from, so every net is delay-free and net
# area is zero.
# ---------------------------------------------------------------------------
note "Creating floorplan: aspect ratio $FP_ASPECT_RATIO, row density $FP_ROW_DENSITY, margin $FP_MARGIN um, site $FP_SITE"
if {[catch {
    create_floorplan -site $FP_SITE \
        -core_density_size [list $FP_ASPECT_RATIO $FP_ROW_DENSITY \
                                 $FP_MARGIN $FP_MARGIN $FP_MARGIN $FP_MARGIN]
} msg]} {
    fail "create_floorplan failed: $msg"
}

# ---------------------------------------------------------------------------
# Library restrictions
#
# sky130_fd_sc_hd ships cells that must never appear in this design:
#
#   lpflow_*  low-power-flow level shifters, isolation cells and decaps. This is
#             a single-rail design with no power domains, so an isolation or
#             level-shifting cell here would be functionally meaningless. Four of
#             them (lpflow_lsbuf_*_isowell_tap_*) are also double-height cells on
#             site unithddbl, for which the floorplan has no rows at all - if
#             synthesis picked one the netlist would not be placeable.
#             check_floorplan will still report "Sites With No Rows" for
#             unithddbl, because that site is declared in the LEF whether or not
#             anything uses it. Marking the cells dont_use is what makes the
#             warning harmless rather than what silences it.
#   probe*    DFT probe cells, not part of the functional netlist.
#
# Excluding these is what makes the mapped netlist implementable. It is not a
# QoR tweak.
# ---------------------------------------------------------------------------
set DONT_USE_PATTERNS {*lpflow* *__probe_* *__probec_*}

# Genus names library cells differently across versions (lib_cells vs
# base_cells) and calls the exclusion attribute either dont_use or avoid.
# Discover which pair this installation accepts rather than assuming.
set DU_OBJ ""
set DU_ATTR ""
foreach obj {lib_cells base_cells} {
    if {[catch {set probe [get_db $obj *]} m]} { continue }
    if {[llength $probe] == 0} { continue }
    set DU_OBJ $obj
    foreach attr {dont_use avoid} {
        if {![catch {set_db [lindex $probe 0] .$attr false} m2]} {
            set DU_ATTR $attr
            break
        }
    }
    break
}

if {$DU_OBJ eq "" || $DU_ATTR eq ""} {
    fail "unable to determine how to exclude library cells (obj='$DU_OBJ' attr='$DU_ATTR'). Refusing to synthesize with unplaceable cells available."
}
note "Library cell exclusion uses: get_db $DU_OBJ / .$DU_ATTR"

set dont_use_count 0
foreach pat $DONT_USE_PATTERNS {
    if {[catch {
        foreach c [get_db $DU_OBJ $pat] {
            set_db $c .$DU_ATTR true
            incr dont_use_count
        }
    } msg]} {
        puts stderr "WARNING: unable to exclude '$pat': $msg"
    }
}

if {$dont_use_count == 0} {
    fail "no lpflow/probe cells were excluded - expected 36. Refusing to synthesize with unplaceable cells available."
}
note "Excluded $dont_use_count library cells (lpflow / probe)"

note "Enabling physical layout estimation (interconnect_mode ple)"
if {[catch {set_db interconnect_mode ple} msg]} {
    fail "unable to enable PLE: $msg"
}

# ---------------------------------------------------------------------------
# Pre-synthesis checks - these decide whether the constraint set is
# trustworthy, so they run before optimization can paper over a problem.
# ---------------------------------------------------------------------------
note "Running pre-synthesis checks"

safe_report [file join $REPORT_DIR check_design.rpt]  { check_design }
safe_report [file join $REPORT_DIR check_timing.rpt]  { check_timing_intent -verbose }
safe_report [file join $REPORT_DIR clocks.rpt]        { report_clocks }
safe_report [file join $REPORT_DIR analysis_views.rpt] { report_analysis_views }
safe_report [file join $REPORT_DIR floorplan.rpt]     { check_floorplan }
safe_report [file join $REPORT_DIR ple.rpt]           { report_ple }

if {$STOP_AFTER_SETUP == 1} {
    note "ASIC_STOP_AFTER_SETUP=1 - stopping before synthesis."
    exit 0
}

# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------
note "Starting physically-aware synthesis"
if {[catch {syn_generic -physical} msg]} {
    fail "syn_generic -physical failed: $msg"
}
if {[catch {syn_map -physical} msg]} {
    fail "syn_map -physical failed: $msg"
}

# Checkpoint. syn_generic + syn_map are the expensive part of the run; without
# this, any failure in the optimization stage throws away hours of work.
set MAP_DB [file join $DB_DIR ${RUN_TAG}_post_map]
if {[catch {write_db $MAP_DB} msg]} {
    puts stderr "WARNING: post-map checkpoint failed: $msg"
} else {
    note "Post-map checkpoint written: $MAP_DB"
}

# Spatial optimization, with an honest fallback. If -spatial cannot run, the
# design is still physically mapped and PLE is still active, so net delays stay
# real - we simply lose the placement-driven refinement pass. Which one ran is
# recorded in the summary rather than left implicit.
set OPT_MODE "syn_opt -spatial"
if {[catch {set_db opt_spatial_effort standard} msg]} {
    puts stderr "WARNING: unable to set opt_spatial_effort: $msg"
}
if {[catch {syn_opt -spatial} msg]} {
    puts stderr "WARNING: syn_opt -spatial failed ($msg); falling back to non-spatial syn_opt"
    set OPT_MODE "syn_opt (non-spatial fallback; -spatial failed)"
    if {[catch {syn_opt} msg2]} {
        fail "syn_opt failed as well: $msg2"
    }
}
note "Optimization stage used: $OPT_MODE"

# ---------------------------------------------------------------------------
# Fixed report block. Every run ends with exactly this set.
# ---------------------------------------------------------------------------
note "Generating reports"

# Fields chosen so that net rows carry visible delay and load columns - the
# whole point of the physical flow is that these are not zero.
set TIMING_FIELDS {timing_point flags arc edge cell fanout load transition delay arrival wire_length}

safe_report [file join $REPORT_DIR check_timing.rpt]   { check_timing_intent -verbose }
safe_report [file join $REPORT_DIR check_design.rpt]   { check_design }
safe_report [file join $REPORT_DIR clocks.rpt]         { report_clocks }
safe_report [file join $REPORT_DIR timing.rpt] \
    "report_timing -max_paths 20 -path_type full -fields {$TIMING_FIELDS}"
safe_report [file join $REPORT_DIR qor.rpt]            { report_qor }
safe_report [file join $REPORT_DIR area.rpt]           { report_area }
safe_report [file join $REPORT_DIR area_hierarchy.rpt] { report_area -hierarchy }
safe_report [file join $REPORT_DIR gates.rpt]          { report_gates }
safe_report [file join $REPORT_DIR messages.rpt]       { report_messages }
safe_report [file join $REPORT_DIR ple_post_synth.rpt] { report_ple }
safe_report [file join $REPORT_DIR power.rpt]          { report_power }

# Genus 21.17 has no report_exceptions command, so the exception set is reported
# by scanning the constraint source itself. That is the authoritative answer:
# if golden.sdc declares no exceptions, the design has none.
set exc_path [file join $REPORT_DIR exceptions.rpt]
if {[catch {
    set fh [open $exc_path w]
    puts $fh "Timing exceptions"
    puts $fh "================="
    puts $fh ""
    puts $fh "Genus [get_db program_version] provides no report_exceptions command."
    puts $fh "Exceptions are therefore reported by scanning the single constraint"
    puts $fh "source, $GOLDEN_SDC, for exception commands."
    puts $fh ""
    set found 0
    set sdc_fh [open $GOLDEN_SDC r]
    set lineno 0
    while {[gets $sdc_fh line] >= 0} {
        incr lineno
        set trimmed [string trim $line]
        if {[string index $trimmed 0] eq "#"} { continue }
        foreach pat {set_false_path set_multicycle_path set_max_delay set_min_delay set_disable_timing set_clock_groups} {
            if {[string match "*${pat}*" $trimmed]} {
                puts $fh "  $GOLDEN_SDC:$lineno: $trimmed"
                incr found
            }
        }
    }
    close $sdc_fh
    if {$found == 0} {
        puts $fh "NONE - no active timing exceptions are declared."
    } else {
        puts $fh ""
        puts $fh "$found exception statement(s) found."
    }
    close $fh
} msg]} {
    puts stderr "WARNING: exceptions report failed: $msg"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
set NETLIST_OUT [file join $NETLIST_DIR ${RUN_TAG}_mapped.v]
set SDC_OUT     [file join $NETLIST_DIR ${RUN_TAG}_mapped.sdc]
set DB_OUT      [file join $DB_DIR ${RUN_TAG}_genus]

note "Writing mapped netlist: $NETLIST_OUT"
if {[catch {write_hdl > $NETLIST_OUT} msg]} {
    fail "write_hdl failed: $msg"
}

note "Writing mapped SDC: $SDC_OUT"
if {[catch {write_sdc > $SDC_OUT} msg]} {
    fail "write_sdc failed: $msg"
}

note "Writing Genus database: $DB_OUT"
if {[catch {write_db $DB_OUT} msg]} {
    puts stderr "WARNING: write_db failed: $msg"
    if {[catch {write_design -basename $DB_OUT} msg2]} {
        fail "database/checkpoint write failed: $msg ; $msg2"
    }
}

# ---------------------------------------------------------------------------
# One-page summary
# ---------------------------------------------------------------------------
proc scrape {path pattern} {
    if {![file exists $path]} { return "n/a" }
    set fh [open $path r]
    set txt [read $fh]
    close $fh
    if {[regexp $pattern $txt -> v]} { return [string trim $v] }
    return "n/a"
}

# report_qor prints timing in picoseconds; convert so the summary is in ns.
proc ps_to_ns {v} {
    if {![string is double -strict $v]} { return $v }
    return [format %.3f [expr {$v / 1000.0}]]
}

set qor_path  [file join $REPORT_DIR qor.rpt]
set area_path [file join $REPORT_DIR area.rpt]
set pwr_path  [file join $REPORT_DIR power.rpt]

set wns       [ps_to_ns [scrape $qor_path {clk\s+(-?[\d.]+)\s+-?[\d.]+\s+\d+}]]
set tns       [ps_to_ns [scrape $qor_path {clk\s+-?[\d.]+\s+(-?[\d.]+)\s+\d+}]]
set violating [scrape $qor_path {clk\s+-?[\d.]+\s+-?[\d.]+\s+(\d+)}]
set cell_area [scrape $qor_path {Cell Area\s+([\d.]+)}]
set net_area  [scrape $qor_path {Net Area\s+([\d.]+)}]
set seq_count [scrape $qor_path {Sequential Instance Count\s+(\d+)}]
set leaf_count [scrape $qor_path {Leaf Instance Count\s+(\d+)}]
set total_pwr [scrape $pwr_path {Subtotal\s+\S+\s+\S+\s+\S+\s+(\S+)}]

set summary_path [file join $REPORT_DIR summary.rpt]
set fh [open $summary_path w]
foreach line [list \
    "======================================================================" \
    " Genus synthesis summary" \
    "======================================================================" \
    "Design                 : [current_design]" \
    "CACHE_BYTES / ASSOC    : $CACHE_BYTES / $ASSOC" \
    "Run stamp              : $RUN_STAMP" \
    "Genus version          : [get_db program_version]" \
    "" \
    "Timing library (single): $SIGNOFF_LIB" \
    "Technology LEF         : $TECH_LEF" \
    "Standard cell LEF      : $CELL_LEF" \
    "Constraints            : $GOLDEN_SDC" \
    "Interconnect mode      : [get_db interconnect_mode]" \
    "Optimization stage     : $OPT_MODE" \
    "Floorplan              : aspect $FP_ASPECT_RATIO, density $FP_ROW_DENSITY, margin $FP_MARGIN um, site $FP_SITE" \
    "" \
    "Clock constraint       : $CLOCK_PERIOD_NS ns (synthesis-stage guardband)" \
    "Setup uncertainty      : 0.250 ns (from golden.sdc)" \
    "Real target            : 4.000 ns / 250 MHz, judged post-route" \
    "" \
    "WNS                    : $wns ns" \
    "TNS                    : $tns ns" \
    "Violating paths        : $violating" \
    "Cell area              : $cell_area um^2" \
    "Net area               : $net_area um^2" \
    "Leaf cell count        : $leaf_count" \
    "Sequential cell count  : $seq_count" \
    "Total power            : $total_pwr W (at ss_100C_1v60, the only corner loaded)" \
    "" \
    "Netlist                : $NETLIST_OUT" \
    "Mapped SDC             : $SDC_OUT" \
    "Database               : $DB_OUT" \
    "Reports                : $REPORT_DIR" \
    "======================================================================" \
] {
    puts $line
    puts $fh $line
}
close $fh

note "Genus synthesis completed successfully."
exit 0
