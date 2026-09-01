# v3-B - true ring, one way per side (FLOORPLAN.md). Sourced by
# 01_floorplan.tcl via ASIC_FLOORPLAN.
#
# 4 macros in a row along each die edge, dout1 (top) edges rotated inward:
# bottom R0, top R180, left R270 (top->right), right R90 (top->left).
# Innovus placeInstance takes the ROTATED bbox lower-left corner; R90/R270
# bboxes are MH wide x MW tall. Die grown to 2700 so the way wedges + hub
# hold ~1.5 mm2 of cells below ~60% density (2574 left a 1.6 mm inner square
# = too tight, FLOORPLAN.md "Fit"). Say so when comparing area with v2.
#   way0 = bottom, way1 = top, way2 = left, way3 = right
set DIE_W 2700.0 ; set DIE_H 2700.0
floorPlan -site $FP_SITE -d $DIE_W $DIE_H \
    $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN
pnr_note "fp_v3b: die ${DIE_W}x${DIE_H}, margin $FP_CORE_MARGIN"

set MW 376.48 ; set MH 446.235
set GAP 40.0 ; set EDGE 40.0 ; set HALO 8.0
set row_len [expr {4*$MW + 3*$GAP}]
set x0 [expr {($DIE_W - $row_len)/2.0}]        ;# horizontal rows (top/bottom)
set y0 [expr {($DIE_H - $row_len)/2.0}]        ;# vertical rows (left/right)
proc _place {w b x y o} {
    global HALO
    set nm "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[$b\].g_sram.u_sram"
    placeInstance $nm $x $y $o
    addHaloToBlock $HALO $HALO $HALO $HALO $nm
    dbSet [dbGet -p top.insts.name $nm].pStatus fixed
}
foreach b {0 1 2 3} {
    set xh [expr {$x0 + $b*($MW + $GAP)}]
    set yv [expr {$y0 + $b*($MW + $GAP)}]
    _place 0 $b $xh $EDGE R0                                     ;# bottom, dout1 up
    _place 1 $b $xh [expr {$DIE_H - $EDGE - $MH}] R180           ;# top, dout1 down
    _place 2 $b $EDGE $yv R270                                   ;# left, dout1 right
    _place 3 $b [expr {$DIE_W - $EDGE - $MH}] $yv R90            ;# right, dout1 left
}
# sanity: a dout1 pin of way0/way2 must sit on the tile's inner edge
foreach w {0 2} {
    set t [dbGet -p top.insts.instTerms.name "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[0\].g_sram.u_sram/dout1\[0\]" -e]
    if {$t ne "" && $t ne "0x0"} { pnr_note "fp_v3b check: way$w dout1\[0\] at [join [dbGet $t.pt]]" }
}
# way wedges (soft regions) between each macro row and the hub
set inner [expr {$EDGE + $MH + $HALO + 6}]      ;# ~500
set D 430.0                                     ;# wedge depth
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
pnr_note "fp_v3b: wedges depth $D from $lo, hub ($h0,$h0)-($h1,$h1)"
