# v3-A - quadrant tiles (FLOORPLAN.md). Sourced by 01_floorplan.tcl via
# ASIC_FLOORPLAN. Expects innovus_config.tcl procs + design loaded (post 00).
#
# Each way = its 4 macros in a 2x2 block in one quadrant, dout1 (top) edges
# facing a 120 um horizontal channel that opens toward the die centre; the
# way's logic in a soft region between its tile and the hub; hub = centre
# guide. Same die as v2 so areas are comparable.
#   way0 = lower-left, way1 = upper-left, way2 = lower-right, way3 = upper-right
set DIE_W 2574.6 ; set DIE_H 2570.4
floorPlan -site $FP_SITE -d $DIE_W $DIE_H \
    $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN
pnr_note "fp_v3a: die ${DIE_W}x${DIE_H}, margin $FP_CORE_MARGIN"

set MW 376.48 ; set MH 446.235
set GAPX 40.0 ; set CHAN 120.0 ; set EDGE 60.0 ; set HALO 8.0
# per-quadrant: sx/sy = +1 growing from the low corner, -1 from the high corner
#   way  {x-anchor  y-anchor  sx  sy}
array set QUAD {
    0 {low  low   1  1}
    1 {low  high  1 -1}
    2 {high low  -1  1}
    3 {high high -1 -1}
}
proc _v3a_xy {anchor s size extent} {
    # lower-left coordinate for a box of $size placed $extent from the anchored edge
    global DIE_W DIE_H
    if {$anchor eq "low"} { return $extent }
    return [expr {($size eq "W" ? $::DIE_W : $::DIE_H) - $extent}]
}
foreach w {0 1 2 3} {
    lassign $QUAD($w) ax ay sx sy
    # column x positions (2 macros side by side, inner column nearer the centre)
    set x0 [expr {$ax eq "low" ? $EDGE : $DIE_W - $EDGE - 2*$MW - $GAPX}]
    # rows: lower row R0 (top edge up), upper row R180 (top edge down) ->
    # both dout1 edges face the CHAN-wide horizontal channel between them.
    set ylow  [expr {$ay eq "low" ? $EDGE : $DIE_H - $EDGE - 2*$MH - $CHAN}]
    set yhigh [expr {$ylow + $MH + $CHAN}]
    set b 0
    foreach {yy oo} [list $ylow R0 $yhigh R180] {
        foreach cc {0 1} {
            set x [expr {$x0 + $cc*($MW + $GAPX)}]
            set nm "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[$b\].g_sram.u_sram"
            placeInstance $nm $x $yy $oo
            addHaloToBlock $HALO $HALO $HALO $HALO $nm
            dbSet [dbGet -p top.insts.name $nm].pStatus fixed
            incr b
        }
    }
    # way logic: soft region in the vertical strip between tile and centre
    set tile_w [expr {2*$MW + $GAPX + $EDGE}]  ;# x extent of tile from its edge
    if {$ax eq "low"} { set rx0 [expr {$EDGE + 2*$MW + $GAPX + 30}]; set rx1 [expr {$DIE_W/2 - 20}] } \
    else              { set rx0 [expr {$DIE_W/2 + 20}]; set rx1 [expr {$DIE_W - ($EDGE + 2*$MW + $GAPX + 30)}] }
    if {$ay eq "low"} { set ry0 40.0; set ry1 [expr {$DIE_H/2 - 20}] } \
    else              { set ry0 [expr {$DIE_H/2 + 20}]; set ry1 [expr {$DIE_H - 40}] }
    createInstGroup way$w -region $rx0 $ry0 $rx1 $ry1
    addInstToInstGroup way$w "GEN_WAYS\[$w\]*"
    pnr_note "fp_v3a: way$w tile at ($x0,$ylow) region ($rx0,$ry0)-($rx1,$ry1)"
}
# hub: soft guide at the centre for the shared logic
set hx0 [expr {$DIE_W/2 - 420}] ; set hx1 [expr {$DIE_W/2 + 420}]
set hy0 [expr {$DIE_H/2 - 420}] ; set hy1 [expr {$DIE_H/2 + 420}]
createInstGroup hub -guide $hx0 $hy0 $hx1 $hy1
foreach pat {COMPARE_SELECT_REPLACE_* RESPONSE_UNIT_* MSHR_* ADDR_DECODE_* REPLACEMENT_* inreg_*} {
    addInstToInstGroup hub $pat
}
pnr_note "fp_v3a: hub guide ($hx0,$hy0)-($hx1,$hy1)"
