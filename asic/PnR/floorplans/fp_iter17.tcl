# ITERATION 17 (2026-09-04) - fp_iter16 (die 2900) with the macro ring fixed
# as a WALL for both routing and supply (ITER17_PLAN.md, decisions D1-D6):
#   * EDGE margin is a knob (ASIC_FP_EDGE, default 80; fp_iter16 = 40).
#   * every macro is FLIPPED (R0<->R180, R90<->R270): the LEF's 70-pin S edge
#     now faces the core, the 34-pin N edge faces the margin (pin census
#     ITER17_PLAN.md section 2; DRC.md "Floorplan lesson for iter17").
#   * blanket route blockages met1-met4 over every macro body, 3 um inset,
#     PG excepted: the router may no longer thread signals through the SRAM
#     interiors (LEF OBS is shape-level with gaps; every residual iter16b
#     DRC was a threading artefact). met5 is left free - the horizontal PDN
#     straps (02_power.tcl, ASIC_PG_STRIPE_H_*) cross the macros on it.
# Wedges, hub group and hub blockage recompute from EDGE/DIE_W exactly as in
# fp_iter16: the extra 40 um of margin comes out of the wedge depth.
set DIE_W [config_env ASIC_FP_DIE 2900.0] ; set DIE_H $DIE_W
floorPlan -site $FP_SITE -d $DIE_W $DIE_H \
    $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN
pnr_note "fp_iter17: die ${DIE_W}x${DIE_H}, margin $FP_CORE_MARGIN"

set MW 376.48 ; set MH 446.235
set GAP 40.0 ; set HALO 8.0
set EDGE [config_env ASIC_FP_EDGE 80.0]
set BLK_INSET [config_env ASIC_FP_MACRO_BLK_INSET 3.0]
set BLK_LAYERS [config_env ASIC_FP_MACRO_BLK_LAYERS {met1 met2 met3 met4}]
set row_len [expr {4*$MW + 3*$GAP}]
set x0 [expr {($DIE_W - $row_len)/2.0}]        ;# horizontal rows (top/bottom)
set y0 [expr {($DIE_H - $row_len)/2.0}]        ;# vertical rows (left/right)
set _blk_n 0
proc _place {w b x y o} {
    global HALO BLK_INSET BLK_LAYERS _blk_n
    set nm "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[$b\].g_sram.u_sram"
    placeInstance $nm $x $y $o
    addHaloToBlock $HALO $HALO $HALO $HALO $nm
    set ip [dbGet -p top.insts.name $nm]
    dbSet $ip.pStatus fixed
    # blanket route blockage over the placed body (bbox from the DB, so the
    # orientation is already accounted for), inset so edge pins stay reachable
    if {$BLK_INSET ne "" && $BLK_LAYERS ne ""} {
        lassign [lindex [dbGet $ip.box] 0] bx1 by1 bx2 by2
        set box [list [expr {$bx1 + $BLK_INSET}] [expr {$by1 + $BLK_INSET}] \
                      [expr {$bx2 - $BLK_INSET}] [expr {$by2 - $BLK_INSET}]]
        createRouteBlk -name macro_blk_w${w}b${b} -box $box -layer $BLK_LAYERS -exceptpgnet
        incr _blk_n
        pnr_note "fp_iter17: route blockage $BLK_LAYERS over way$w bank$b [join $box]"
    }
}
foreach b {0 1 2 3} {
    set xh [expr {$x0 + $b*($MW + $GAP)}]
    set yv [expr {$y0 + $b*($MW + $GAP)}]
    _place 0 $b $xh $EDGE R180                                   ;# bottom, flipped: S(70-pin) edge faces up/core
    _place 1 $b $xh [expr {$DIE_H - $EDGE - $MH}] R0             ;# top,    flipped: S edge faces down/core
    _place 2 $b $EDGE $yv R90                                    ;# left,   flipped: S edge faces right/core
    _place 3 $b [expr {$DIE_W - $EDGE - $MH}] $yv R270           ;# right,  flipped: S edge faces left/core
}
pnr_note "fp_iter17: EDGE $EDGE, macros flipped vs fp_iter16, $_blk_n macro route blockages (inset $BLK_INSET)"
# sanity: record where a dout1 pin of way0/way2 landed (fp_iter16 had it on
# the tile's inner edge; after the flip it moves to the outer edge - the
# 70-pin S edge is what faces the core now)
foreach w {0 2} {
    set t [dbGet -p top.insts.instTerms.name "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[0\].g_sram.u_sram/dout1\[0\]" -e]
    if {$t ne "" && $t ne "0x0"} { pnr_note "fp_iter17 check: way$w dout1\[0\] at [join [dbGet $t.pt]]" }
}
# way wedges (soft regions) between each macro row and the hub
set inner [expr {$EDGE + $MH + $HALO + 6}]      ;# ~540 at EDGE 80
set D 380.0                                     ;# wedge depth (iter5: was 430)
set lo $inner ; set hi [expr {$DIE_W - $inner}]
createInstGroup way0 -region $lo $lo $hi [expr {$lo + $D}]
createInstGroup way1 -region $lo [expr {$hi - $D}] $hi $hi
createInstGroup way2 -region $lo [expr {$lo + $D}] [expr {$lo + $D}] [expr {$hi - $D}]
createInstGroup way3 -region [expr {$hi - $D}] [expr {$lo + $D}] $hi [expr {$hi - $D}]
foreach w {0 1 2 3} { addInstToInstGroup way$w "GEN_WAYS\[$w\]*" }
# hub guide = the centre square the wedges leave
set h0 [expr {$lo + $D}] ; set h1 [expr {$hi - $D}]
createInstGroup hub -guide $h0 $h0 $h1 $h1
foreach pat {COMPARE_SELECT_REPLACE_* RESPONSE_UNIT_* MSHR_* ADDR_DECODE_* REPLACEMENT_* inreg_*} {
    addInstToInstGroup hub $pat
}

# G7b: hard local density cap over the hub - 40% partial placement blockage.
# (createPlaceBlockage -type partial: density is the BLOCKED fraction; 40
# leaves bins at <= 60% cell density inside the box.)
createPlaceBlockage -type partial -density 40 -box [list $h0 $h0 $h1 $h1]
pnr_note "fp_iter7: 40% partial place blockage over hub ($h0 $h0)-($h1 $h1)"
pnr_note "fp_iter17: wedges depth $D from $lo, hub ($h0,$h0)-($h1,$h1)"
