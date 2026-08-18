# ============================================================================
# Synopsys Design Compiler synthesis flow for the parameterized cache.
#
# This mirrors the Genus flow: same signoff corner, same golden.sdc, same
# excluded library cells, same fixed report block, same run-stamped outputs.
#
# ONE DIFFERENCE, AND IT IS DELIBERATE.
#
# Genus runs physically-aware (LEF + floorplan + PLE), so its interconnect is
# estimated from real geometry. Design Compiler cannot do that here: DC
# Topographical needs Milkyway or NDM physical libraries, and this PDK ships
# neither for sky130_fd_sc_hd. DC therefore falls back to Liberty wire load
# models, which this script enables explicitly and records in the summary.
#
# Be aware how weak that fallback is: in sky130_fd_sc_hd the Small, Medium,
# Large and Huge wire load models are byte-for-byte identical, and the library
# declares no wire_load_selection group. So the model does not scale with design
# size and the choice between them changes nothing. DC's net delays here are
# better than zero but are NOT comparable in quality to the Genus PLE numbers.
# Quote Genus for interconnect-sensitive conclusions.
#
# SINGLE CORNER, matching the Genus flow: everything is mapped, optimized and
# reported at ss_100C_1v60. Hold is not fixed pre-CTS, so no fast corner is
# loaded; multi-corner analysis belongs in the place-and-route tool at CTS.
#
# Nothing in this script defines a timing constraint. All constraints come from
# constraints/golden.sdc.
# ============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set SYNOPSYS_DIR [file normalize [file dirname $SCRIPT_DIR]]
set SYNTH_DIR [file normalize [file dirname $SYNOPSYS_DIR]]

source [file join $SYNTH_DIR common scripts project_config.tcl]
source [file join $FILELIST_DIR rtl_files.tcl]

proc fail {msg} {
    puts stderr "ERROR: $msg"
    exit 1
}

proc note {msg} {
    puts "INFO: $msg"
}

proc safe_report {path body} {
    if {[catch {redirect -file $path $body} msg]} {
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

proc require_nonempty_file {path label} {
    if {![file exists $path]} { fail "$label was not written: $path" }
    if {[file size $path] == 0} { fail "$label is empty: $path" }
}

proc absolutize_rtl_files {rtl_files repo_root} {
    set files [list]
    foreach rtl $rtl_files {
        set abs [file normalize [file join $repo_root $rtl]]
        if {![file exists $abs]} { fail "RTL file does not exist: $rtl" }
        lappend files $abs
    }
    if {[llength $files] == 0} { fail "RTL file list is empty" }
    return $files
}

foreach d [list $REPORT_DIR $NETLIST_DIR $DB_DIR $LOG_DIR $WORK_DIR] {
    file mkdir $d
}

# ---------------------------------------------------------------------------
# Libraries
#
# DC cannot read Liberty, so the signoff corner is pre-compiled to .db by
# libraries/sky130_fd_sc_hd/build_db.tcl. One library only: ss_100C_1v60, the
# same corner the Genus flow uses. Every reported number, power included, comes
# from it.
# ---------------------------------------------------------------------------
if {![info exists ::env(DC_TARGET_LIB)] || $::env(DC_TARGET_LIB) eq ""} {
    fail "DC_TARGET_LIB is not set"
}
set DC_TARGET_LIB [file normalize $::env(DC_TARGET_LIB)]
if {![file exists $DC_TARGET_LIB]} { fail "DC_TARGET_LIB does not exist: $DC_TARGET_LIB" }
if {![string match "*.db" $DC_TARGET_LIB]} {
    fail "DC_TARGET_LIB must be a Synopsys .db file, not a Liberty .lib. Build one with libraries/sky130_fd_sc_hd/build_db.tcl."
}

if {![file exists $GOLDEN_SDC]} { fail "golden SDC does not exist: $GOLDEN_SDC" }

set ABS_RTL_FILES [absolutize_rtl_files $RTL_FILES $REPO_ROOT]

set LINK_LIBS [list "*" $DC_TARGET_LIB]
set SEARCH_DIRS [list . $REPO_ROOT [file dirname $DC_TARGET_LIB]]

set_app_var search_path [concat $SEARCH_DIRS $search_path]
set_app_var target_library [list $DC_TARGET_LIB]
set_app_var link_library $LINK_LIBS

note "target_library      = $target_library"
note "link_library        = $link_library"
note "golden SDC          = $GOLDEN_SDC"
note "output directory    = $OUT_DIR"

if {[catch {set lib_cells [get_lib_cells -quiet */*]} msg]} {
    fail "unable to query target library cells: $msg"
}
if {[sizeof_collection $lib_cells] == 0} {
    fail "target library contains no visible library cells: $DC_TARGET_LIB"
}

# ---------------------------------------------------------------------------
# Library restrictions - identical intent to the Genus flow.
# lpflow_* are level shifters / isolation cells for multi-rail designs (four are
# double-height cells that a single-height floorplan cannot place); probe* are
# DFT cells. Neither belongs in this netlist.
# ---------------------------------------------------------------------------
set dont_use_count 0
foreach pat {*lpflow* *probe_* *probec_*} {
    if {[catch {
        set c [get_lib_cells -quiet */$pat]
        if {[sizeof_collection $c] > 0} {
            set_dont_use $c
            incr dont_use_count [sizeof_collection $c]
        }
    } msg]} {
        puts stderr "WARNING: unable to exclude '$pat': $msg"
    }
}
if {$dont_use_count == 0} {
    fail "no lpflow/probe cells were excluded - expected 36. Refusing to synthesize with unplaceable cells available."
}
note "Excluded $dont_use_count library cells (lpflow / probe)"

# ---------------------------------------------------------------------------
# RTL
# ---------------------------------------------------------------------------
set DC_WORK_LIB [file join $WORK_DIR WORK]
file mkdir $DC_WORK_LIB
define_design_lib WORK -path $DC_WORK_LIB

note "Analyzing SystemVerilog RTL"
if {[catch {analyze -format sverilog -library WORK $ABS_RTL_FILES} msg]} {
    fail "analyze failed: $msg"
}

note "Elaborating $TOP"
set ELAB_PARAMETERS "CACHE_BYTES=$CACHE_BYTES,ASSOC=$ASSOC"
if {[catch {elaborate $TOP -library WORK -parameters $ELAB_PARAMETERS} msg]} {
    fail "elaborate failed with CACHE_BYTES=$CACHE_BYTES ASSOC=$ASSOC: $msg"
}

set CURRENT_DESIGN_NAME [get_object_name [current_design]]
note "Elaborated design = $CURRENT_DESIGN_NAME"

note "Linking design"
if {[catch {link} msg]} { fail "link failed: $msg" }

if {[catch {set unresolved_designs [get_designs -quiet * -filter "is_unresolved == true"]} msg]} {
    puts stderr "WARNING: unable to query unresolved designs after link: $msg"
} elseif {[sizeof_collection $unresolved_designs] > 0} {
    safe_report [file join $REPORT_DIR unresolved_references.rpt] { report_reference -hierarchy }
    fail "unresolved references remain after link"
}

# ---------------------------------------------------------------------------
# Interconnect estimation - the documented fallback.
#
# This MUST come after link. set_wire_load_mode and set_wire_load_model both act
# on the current design, and before elaborate/link there is no current design -
# they fail with "Current design is not defined" and the fallback is silently
# never applied, leaving the run with no interconnect model at all.
# ---------------------------------------------------------------------------
note "DC Topographical is unavailable (no Milkyway/NDM in this PDK); falling back to Liberty wire load models"
if {[catch {set_wire_load_mode top} msg]} {
    fail "set_wire_load_mode failed: $msg"
}
if {[catch {set_wire_load_model -name Small} msg]} {
    fail "set_wire_load_model failed: $msg"
}

# ---------------------------------------------------------------------------
# Constraints - the same file Genus reads, read directly. No regeneration.
# ---------------------------------------------------------------------------
# NOTE: `source`, not `read_sdc`.
#
# DC's read_sdc runs the file in a restricted SDC-only interpreter that does not
# expose remove_from_collection, so the set_input_delay and set_driving_cell
# lines in golden.sdc fail there - and they fail QUIETLY, leaving the design
# with no input delays and no boundary drive while the run continues and reports
# timing as if everything were constrained. Sourcing the same file in the full
# dc_shell interpreter applies every line. Genus reads the identical file
# through its constraint mode without this problem.
note "Sourcing golden SDC: $GOLDEN_SDC"
if {[catch {source -echo -verbose $GOLDEN_SDC} msg]} {
    fail "failed to apply $GOLDEN_SDC: $msg"
}

if {[sizeof_collection [get_clocks -quiet $CLOCK_PORT]] == 0} {
    fail "clock '$CLOCK_PORT' is missing after reading the golden SDC"
}


# ---------------------------------------------------------------------------
# Pre-compile checks
# ---------------------------------------------------------------------------
note "Running pre-compile checks"
safe_report [file join $REPORT_DIR check_design.rpt] { check_design }
safe_report [file join $REPORT_DIR check_timing.rpt] { check_timing }
safe_report [file join $REPORT_DIR clocks.rpt]       { report_clock }
safe_report [file join $REPORT_DIR clock_skew.rpt]   { report_clock -skew }

# Prove the constraint set actually landed rather than assuming it. A silently
# dropped set_input_delay is the easiest way to make a timing report look good
# and mean nothing - which is exactly what read_sdc did to this flow before it
# was switched to source. Scan DC's own check_timing output for the phrases it
# uses when a port has no external delay, and refuse to continue if any appear.
set ct_path [file join $REPORT_DIR check_timing.rpt]
if {[file exists $ct_path]} {
    set fh [open $ct_path r]
    set ct [read $fh]
    close $fh
    # Only real Warning/Error lines count. DC prints an informational
    # "Checking unconstrained_endpoints..." header for every category whether or
    # not it finds anything, so matching on the topic word alone false-positives
    # on a perfectly clean report.
    set offenders [list]
    foreach line [split $ct "\n"] {
        if {![regexp {^(Warning|Error):} $line]} { continue }
        foreach pat {"no input delay" "no output delay" "unconstrained endpoint"
                     "not constrained for maximum delay" "no driving cell"
                     "partial input delay" "has no clock"} {
            if {[string match -nocase "*$pat*" $line]} {
                lappend offenders [string trim $line]
                break
            }
        }
    }
    if {[llength $offenders] > 0} {
        puts stderr "ERROR: check_timing reports unconstrained timing after applying $GOLDEN_SDC:"
        foreach o [lrange $offenders 0 9] { puts stderr "  $o" }
        fail "constraint set did not fully take effect - refusing to report timing that is not trustworthy"
    }
    note "check_timing: no unconstrained ports or endpoints reported"
} else {
    puts stderr "WARNING: check_timing report was not produced; cannot verify constraints landed"
}

if {$STOP_AFTER_SETUP == 1} {
    note "ASIC_STOP_AFTER_SETUP=1 - stopping before compile."
    exit 0
}

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
note "Starting compile_ultra"
if {[catch {compile_ultra} msg]} { fail "compile_ultra failed: $msg" }

# ---------------------------------------------------------------------------
# Post-compile sanity
# ---------------------------------------------------------------------------
if {[catch {set gtech_cells [get_cells -quiet -hierarchical -filter "ref_name =~ GTECH*"]} msg]} {
    puts stderr "WARNING: unable to query remaining GTECH cells: $msg"
} elseif {[sizeof_collection $gtech_cells] > 0} {
    safe_report [file join $REPORT_DIR remaining_gtech_cells.rpt] {
        report_cell [get_cells -hierarchical -filter "ref_name =~ GTECH*"]
    }
    fail "GTECH cells remain after compile"
}

if {[catch {set unmapped_cells [get_cells -quiet -hierarchical -filter "is_unmapped == true"]} msg]} {
    puts stderr "WARNING: unable to query unmapped cells: $msg"
} elseif {[sizeof_collection $unmapped_cells] > 0} {
    safe_report [file join $REPORT_DIR unmapped_cells.rpt] {
        report_cell [get_cells -hierarchical -filter "is_unmapped == true"]
    }
    fail "unmapped cells remain after compile"
}

# ---------------------------------------------------------------------------
# Fixed report block - same set as the Genus flow.
# ---------------------------------------------------------------------------
note "Generating reports"

safe_report [file join $REPORT_DIR check_timing.rpt]   { check_timing }
safe_report [file join $REPORT_DIR check_design.rpt]   { check_design }
safe_report [file join $REPORT_DIR clocks.rpt]         { report_clock }
safe_report [file join $REPORT_DIR timing.rpt] {
    report_timing -delay_type max -max_paths 20 -path_type full \
        -input_pins -nets -capacitance -transition_time -nosplit
}
safe_report [file join $REPORT_DIR timing_hold.rpt] {
    report_timing -delay_type min -max_paths 20 -path_type full -nosplit
}
safe_report [file join $REPORT_DIR qor.rpt]            { report_qor }
safe_report [file join $REPORT_DIR area.rpt]           { report_area }
safe_report [file join $REPORT_DIR area_hierarchy.rpt] { report_area -hierarchy }
safe_report [file join $REPORT_DIR cell_area.rpt]      { report_area }
safe_report [file join $REPORT_DIR cell_usage.rpt]     { report_reference -hierarchy }
safe_report [file join $REPORT_DIR constraints.rpt]    { report_constraint -all_violators }
safe_report [file join $REPORT_DIR wire_load.rpt]      { report_wire_load }

# DC has no report_exceptions either; report from the single constraint source,
# exactly as the Genus flow does.
set exc_path [file join $REPORT_DIR exceptions.rpt]
if {[catch {
    set fh [open $exc_path w]
    puts $fh "Timing exceptions"
    puts $fh "================="
    puts $fh ""
    puts $fh "Reported by scanning the single constraint source, $GOLDEN_SDC."
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
safe_report [file join $REPORT_DIR timing_requirements.rpt] { report_timing_requirements }

# Power. Reported at the signoff corner, because that is the only library
# loaded. A typical-corner power number is a separate question and belongs to a
# run that links tt_025C_1v80; do not read this figure as typical-silicon power.
safe_report [file join $REPORT_DIR power.rpt] { report_power }
set POWER_CORNER "ss_100C_1v60"

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
change_names -rules verilog -hierarchy

set NETLIST_OUT [file join $NETLIST_DIR ${RUN_TAG}_mapped.v]
set SDC_OUT     [file join $NETLIST_DIR ${RUN_TAG}_mapped.sdc]
set DDC_OUT     [file join $DB_DIR ${RUN_TAG}.ddc]

note "Writing mapped Verilog: $NETLIST_OUT"
if {[catch {write_file -format verilog -hierarchy -output $NETLIST_OUT} msg]} {
    fail "write mapped Verilog failed: $msg"
}
note "Writing mapped SDC: $SDC_OUT"
if {[catch {write_sdc $SDC_OUT} msg]} { fail "write_sdc failed: $msg" }
note "Writing DDC database: $DDC_OUT"
if {[catch {write_file -format ddc -hierarchy -output $DDC_OUT} msg]} {
    fail "write DDC failed: $msg"
}

require_nonempty_file $NETLIST_OUT "mapped Verilog netlist"
require_nonempty_file $SDC_OUT "mapped SDC"
require_nonempty_file $DDC_OUT "DDC database"

# ---------------------------------------------------------------------------
# One-page summary - same fields as the Genus summary.
# ---------------------------------------------------------------------------
proc scrape {path pattern} {
    if {![file exists $path]} { return "n/a" }
    set fh [open $path r]
    set txt [read $fh]
    close $fh
    if {[regexp $pattern $txt -> v]} { return [string trim $v] }
    return "n/a"
}

set qor_path  [file join $REPORT_DIR qor.rpt]
set area_path [file join $REPORT_DIR area.rpt]
set pwr_path  [file join $REPORT_DIR power.rpt]

set wns        [scrape $qor_path {Critical Path Slack:\s*(-?[\d.]+)}]
set tns        [scrape $qor_path {Total Negative Slack:\s*(-?[\d.]+)}]
set violating  [scrape $qor_path {No\. of Violating Paths:\s*(\d+)}]
set cell_area  [scrape $area_path {Total cell area:\s*([\d.]+)}]
set net_area   [scrape $area_path {Total interconnect area:\s*([\d.eE+-]+)}]
set seq_count  [scrape $qor_path {Sequential Cell Count:\s*(\d+)}]
set leaf_count [scrape $qor_path {Leaf Cell Count:\s*(\d+)}]
set total_pwr  [scrape $pwr_path {Total Dynamic Power\s*=\s*([\d.]+\s*\w+)}]
set leak_pwr   [scrape $pwr_path {Cell Leakage Power\s*=\s*([\d.]+\s*\w+)}]

set summary_path [file join $REPORT_DIR summary.rpt]
set fh [open $summary_path w]
foreach line [list \
    "======================================================================" \
    " Design Compiler synthesis summary" \
    "======================================================================" \
    "Design                 : $CURRENT_DESIGN_NAME" \
    "CACHE_BYTES / ASSOC    : $CACHE_BYTES / $ASSOC" \
    "Run stamp              : $RUN_STAMP" \
    "" \
    "Timing library (single): $DC_TARGET_LIB" \
    "Constraints            : $GOLDEN_SDC" \
    "Interconnect           : Liberty wire load models (FALLBACK)" \
    "                         DC Topographical unavailable - no Milkyway/NDM" \
    "                         in this PDK. Note that sky130_fd_sc_hd's Small/" \
    "                         Medium/Large/Huge models are identical, so the" \
    "                         estimate does not scale with design size." \
    "" \
    "Clock constraint       : $CLOCK_PERIOD_NS ns (synthesis-stage guardband)" \
    "Setup uncertainty      : 0.250 ns (from golden.sdc)" \
    "Real target            : 4.000 ns / 250 MHz, judged post-route" \
    "" \
    "WNS                    : $wns ns" \
    "TNS                    : $tns ns" \
    "Violating paths        : $violating" \
    "Cell area              : $cell_area um^2" \
    "Net (interconnect) area: $net_area" \
    "Leaf cell count        : $leaf_count" \
    "Sequential cell count  : $seq_count" \
    "Dynamic power ($POWER_CORNER) : $total_pwr" \
    "Leakage power ($POWER_CORNER) : $leak_pwr" \
    "" \
    "Netlist                : $NETLIST_OUT" \
    "Mapped SDC             : $SDC_OUT" \
    "Database               : $DDC_OUT" \
    "Reports                : $REPORT_DIR" \
    "======================================================================" \
] {
    puts $line
    puts $fh $line
}
close $fh

note "Design Compiler synthesis completed successfully."
exit 0
