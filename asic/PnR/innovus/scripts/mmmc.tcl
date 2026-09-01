# MMMC setup: one setup view (SS) and one hold view (FF).
#
# Sourced after innovus_config.tcl, which defines every path used here.
#
# The Genus flow writes its own single-corner mmmc.tcl per run (setup only, both
# -setup and -hold pointed at the same view, because hold is not fixed pre-CTS).
# This file is the real thing: two corners, and the macro derates applied
# asymmetrically across them.
#
# Corner rationale, RC-corner limitation and macro-lib options: ../README.md.

if {![info exists SIGNOFF_LIB]} {
    error "mmmc.tcl: source innovus_config.tcl first"
}

# ---------------------------------------------------------------------------
# Library sets
# ---------------------------------------------------------------------------
set _ss_libs [list $SIGNOFF_LIB]
set _ff_libs [list $HOLD_LIB]

if {$SRAM_MACRO} {
    if {![file readable $SRAM_MACRO_LIB]} {
        error "mmmc.tcl: setup macro lib not readable: $SRAM_MACRO_LIB"
    }
    lappend _ss_libs $SRAM_MACRO_LIB

    # No silent fallback. A missing FF macro lib means hold analysis would run
    # with the macros untimed, which reads as "hold is clean" - the exact
    # failure this whole two-corner setup exists to prevent. With
    # ASIC_MACRO_SOURCE=openram this is expected until an FF characterization
    # has been run (~26 h; see README.md).
    if {$SRAM_MACRO_LIB_FF eq "" || ![file readable $SRAM_MACRO_LIB_FF]} {
        error "mmmc.tcl: no readable FF-corner macro library.\n\
              \  ASIC_MACRO_SOURCE = $MACRO_SOURCE\n\
              \  ASIC_SRAM_MACRO_LIB_FF = '$SRAM_MACRO_LIB_FF'\n\
              \  Hold analysis without a macro lib is silently optimistic.\n\
              \  Either run an FF characterization for this macro, or use\n\
              \  ASIC_MACRO_SOURCE=vendor (its FF_1p8V_25C lib ships with the PDK)."
    }
    lappend _ff_libs $SRAM_MACRO_LIB_FF
}

create_library_set -name ss_libs -timing $_ss_libs
create_library_set -name ff_libs -timing $_ff_libs

# ---------------------------------------------------------------------------
# RC corners
# ---------------------------------------------------------------------------
# This PDK ships no QRC tech file and no captable - only OpenRCX and Calibre
# rule decks, neither of which Innovus reads - so -qx_tech_file / -cap_table are
# not options here. RC corners are therefore temperature plus RC scaling
# factors over LEF-based extraction. That is the ceiling of what the PDK
# supports, not a shortcut: quote post-route numbers with that caveat attached.
#
# The scaling factors are deliberately mild placeholders (+/-10%) rather than
# invented precision. Replace them if a real extraction deck ever appears.
# 2026-08-28: an in-house Quantus techfile is being built and validated in
# asic/signoff/quantus/. Until it passes validation it is opt-in: set
# ASIC_QRC_TECH to the .tch path and both corners extract through Quantus
# (same file; the +/-10% scaling stays as the corner spread). Unset = the
# LEF-based default below, unchanged.
set _qrc [config_env ASIC_QRC_TECH {}]
if {$_qrc ne "" && ![file readable $_qrc]} { error "mmmc.tcl: ASIC_QRC_TECH not readable: $_qrc" }
set _qrc_opt [expr {$_qrc ne "" ? [list -qx_tech_file $_qrc] : {}}]
if {$_qrc ne ""} { puts "INFO: RC corners use Quantus techfile $_qrc (UNVALIDATED unless signoff/quantus/quantus.md says otherwise)" }

create_rc_corner -name rc_slow -T 100 {*}$_qrc_opt \
    -preRoute_res 1.10 -preRoute_cap 1.10 \
    -postRoute_res 1.10 -postRoute_cap 1.10

create_rc_corner -name rc_fast -T -40 {*}$_qrc_opt \
    -preRoute_res 0.90 -preRoute_cap 0.90 \
    -postRoute_res 0.90 -postRoute_cap 0.90

# ---------------------------------------------------------------------------
# Delay corners
# ---------------------------------------------------------------------------
create_delay_corner -name ss_corner -library_set ss_libs -rc_corner rc_slow
create_delay_corner -name ff_corner -library_set ff_libs -rc_corner rc_fast

# ---------------------------------------------------------------------------
# Macro derates - asymmetric on purpose
# ---------------------------------------------------------------------------
# Setup: LATE derate, slowing the macros to cover the corner gap between the
#        macro lib's V/T and the stdcell signoff corner (x2.0 for the vendored
#        macro; see asic/MACROS.md for how that number was derived).
# Hold:  EARLY derate, SPEEDING the macros up. A late derate does nothing for
#        hold. Omitting this is the classic silently-optimistic-hold bug.
#
# Applied per delay corner, and only when macros are actually instantiated.
# The instance collection is resolved after the netlist is read, so this proc
# is called from run_innovus.tcl post-init rather than at MMMC creation time.
proc pnr_apply_macro_derates {} {
    global SRAM_MACRO SRAM_MACRO_CELL SRAM_MACRO_DERATE SRAM_MACRO_DERATE_EARLY

    if {!$SRAM_MACRO} { return }

    # get_cells returns a collection; sizeof_collection counts it (llength of
    # the handle is always 1 - first shakedown 2026-08-26 reported "1 instances").
    set insts [get_cells -hierarchical -filter "ref_name =~ ${SRAM_MACRO_CELL}*"]
    if {[sizeof_collection $insts] == 0} {
        error "pnr_apply_macro_derates: SRAM_MACRO is set but no macro instances\
               matched ref_name ${SRAM_MACRO_CELL}* - check the netlist."
    }

    set_timing_derate -delay_corner ss_corner -late  $SRAM_MACRO_DERATE       $insts
    set_timing_derate -delay_corner ff_corner -early $SRAM_MACRO_DERATE_EARLY $insts

    puts "INFO: macro derate  setup(late) x$SRAM_MACRO_DERATE ,\
          hold(early) x$SRAM_MACRO_DERATE_EARLY  on [sizeof_collection $insts] instances"
}

# ---------------------------------------------------------------------------
# Constraint mode and views
# ---------------------------------------------------------------------------
# One functional mode for both corners. pnr.sdc sources golden.sdc and adds the
# back-end margins golden.sdc deliberately defers (hold uncertainty; propagated
# clock is switched on after CTS by the flow, not here).
create_constraint_mode -name func -sdc_files [list $PNR_SDC]

create_analysis_view -name setup_view -constraint_mode func -delay_corner ss_corner
create_analysis_view -name hold_view  -constraint_mode func -delay_corner ff_corner

set_analysis_view -setup {setup_view} -hold {hold_view}
