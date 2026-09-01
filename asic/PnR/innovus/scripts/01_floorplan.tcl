# Stage 01 - floorplan: die/core, macro placement, halos and blockages.
#
# This is the stage that actually needs judgement. Everything else in the flow
# is largely mechanical; the macro arrangement sets the wire lengths that decide
# whether timing closes. Expect to run it, look at the GUI, adjust, rerun - the
# parameters at the top exist to make that loop fast.
#
# A4 (the signoff target) instantiates 16 copies of the 32x256 macro: 4 ways x
# 4 line-words, one macro per (way, word) data bank. The natural arrangement is
# therefore a 4x4 grid, and the default below reflects that - but it is a
# starting point, not a result.

set _here [file normalize [file dirname [info script]]]
# Config first (idempotent), then restore the previous stage ONLY if no
# design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# failed after sourcing the config leaves the variable defined and a
# re-source then skips the restore (floorPlan "unithd does not match any
# object in design" - first shakedown 2026-08-26).
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
if {[dbGet -e top] eq ""} { pnr_restore_stage 00_init.enc }

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
# Core utilisation. project_config.tcl's FP_ROW_DENSITY (0.65) is what Genus
# used for its physical estimate; matching it keeps the synthesis PPA numbers
# and the PnR result comparable. Lower it if placement is congested.
set FP_UTIL   [config_env ASIC_FP_UTIL   $FP_ROW_DENSITY]
set FP_ASPECT [config_env ASIC_FP_ASPECT $FP_ASPECT_RATIO]
set FP_CORE_MARGIN [config_env ASIC_FP_CORE_MARGIN $FP_MARGIN]

# Macro grid. 16 macros -> 4 x 4 by default.
set MACRO_COLS    [config_env ASIC_MACRO_COLS 4]
set MACRO_GAP_X   [config_env ASIC_MACRO_GAP_X 40]
set MACRO_GAP_Y   [config_env ASIC_MACRO_GAP_Y 40]
# Keep-clear ring around each macro so standard cells cannot crowd the pins.
set MACRO_HALO    [config_env ASIC_MACRO_HALO 8]

# ---------------------------------------------------------------------------
# Die and core
# ---------------------------------------------------------------------------
# Auto-size from utilisation rather than hardcoding a die: the cell area moves
# every time the RTL changes, and this campaign changes it daily. Innovus sizes
# the core to hold the placeable area at FP_UTIL, then adds the margins.
# A floorplan FILE (ASIC_FLOORPLAN=<path.tcl>, e.g. ../floorplans/fp_v3a.tcl)
# replaces everything below - die, macro placement, halos, regions - and
# stage 01 then only reports and checkpoints. That is how the v3 candidates
# run without forking the flow (FLOORPLAN.md).
set FP_FILE [config_env ASIC_FLOORPLAN {}]
if {$FP_FILE ne ""} {
    if {![file readable $FP_FILE]} { pnr_fail "ASIC_FLOORPLAN not readable: $FP_FILE" }
    pnr_note "floorplan from file: $FP_FILE"
    source $FP_FILE
} else {

floorPlan -site $FP_SITE \
          -r $FP_ASPECT $FP_UTIL \
          $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN

pnr_note "floorplan: site $FP_SITE  aspect $FP_ASPECT  util $FP_UTIL  margin $FP_CORE_MARGIN"

# ---------------------------------------------------------------------------
# Macro placement
# ---------------------------------------------------------------------------
proc pnr_place_macros {} {
    global SRAM_MACRO SRAM_MACRO_CELL MACRO_COLS MACRO_GAP_X MACRO_GAP_Y MACRO_HALO

    if {!$SRAM_MACRO} {
        pnr_note "no SRAM macros in this build - skipping macro placement"
        return
    }

    set insts {}
    foreach i [dbGet top.insts] {
        if {[string match ${SRAM_MACRO_CELL}* [dbGet $i.cell.name]]} {
            lappend insts $i
        }
    }
    set n [llength $insts]
    if {$n == 0} { pnr_fail "SRAM_MACRO set but no macro instances found" }
    pnr_note "placing $n macro instances"

    # Macro footprint, read from the design rather than hardcoded - the vendored
    # and OpenRAM macros are different sizes and this script must not care.
    set mw [dbGet [lindex $insts 0].cell.size_x]
    set mh [dbGet [lindex $insts 0].cell.size_y]
    pnr_note "macro footprint: ${mw} x ${mh} um"

    # Core box, so the grid can be centred inside it.  dbGet returns geometry
    # as a LIST of boxes ({{x0 y0 x1 y1}}) even for a single box - take the
    # first element or lindex 2/3 come back empty (first shakedown 2026-08-26).
    set core [lindex [dbGet top.fPlan.coreBox] 0]
    set cx0 [lindex $core 0] ; set cy0 [lindex $core 1]
    set cx1 [lindex $core 2] ; set cy1 [lindex $core 3]

    set rows [expr {int(ceil(double($n) / $MACRO_COLS))}]
    set grid_w [expr {$MACRO_COLS * $mw + ($MACRO_COLS - 1) * $MACRO_GAP_X}]
    set grid_h [expr {$rows * $mh + ($rows - 1) * $MACRO_GAP_Y}]

    set x0 [expr {$cx0 + (($cx1 - $cx0) - $grid_w) / 2.0}]
    set y0 [expr {$cy0 + (($cy1 - $cy0) - $grid_h) / 2.0}]

    if {$x0 < $cx0 || $y0 < $cy0} {
        pnr_note "WARNING: macro grid ${grid_w}x${grid_h} does not fit the core\
                  ([expr {$cx1-$cx0}]x[expr {$cy1-$cy0}]). Lower ASIC_FP_UTIL,\
                  change ASIC_MACRO_COLS, or shrink the gaps."
    }

    # Mirror alternate columns so adjacent macros face each other pin-to-pin.
    # Halves the average pin-to-pin distance across a column pair.
    set idx 0
    foreach inst $insts {
        set r [expr {$idx / $MACRO_COLS}]
        set c [expr {$idx % $MACRO_COLS}]
        set x [expr {$x0 + $c * ($mw + $MACRO_GAP_X)}]
        set y [expr {$y0 + $r * ($mh + $MACRO_GAP_Y)}]
        set orient [expr {($c % 2) ? "MY" : "R0"}]

        # dbGet returns a one-element list; names with [ ] get brace-quoted in
        # it ("{GEN_WAYS[1]....u_sram}") and addHaloToBlock then cannot find
        # the instance (IMPFP-7695, first shakedown 2026-08-26). lindex unwraps.
        set name [lindex [dbGet $inst.name] 0]
        placeInstance $name $x $y $orient
        addHaloToBlock $MACRO_HALO $MACRO_HALO $MACRO_HALO $MACRO_HALO $name
        incr idx
    }

    # Macros are placed by this script, not by the placer - fix ONLY them.
    # (Do not be tempted by `dbSet top.insts.pStatus fixed`: that freezes every
    # standard cell in the design before placement has run.)
    foreach inst $insts { dbSet $inst.pStatus fixed }

    pnr_note "macros placed: ${MACRO_COLS} cols x ${rows} rows, halo ${MACRO_HALO} um"
}

pnr_place_macros

}
# ---------------------------------------------------------------------------
# Reports and checkpoint
# ---------------------------------------------------------------------------
# Inspect these (and the GUI) before moving on. A floorplan that is wrong here
# is cheap to fix and expensive to discover after CTS.
report_area                > [pnr_rpt floorplan area.rpt]
checkFPlan -reportUtil     > [pnr_rpt floorplan utilization.rpt]

saveDesign [pnr_ckpt 01_floorplan.enc]
pnr_note "stage 01 (floorplan) complete - INSPECT before continuing"
