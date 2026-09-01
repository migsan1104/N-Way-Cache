# ITERATION 9 - fp_iter7 + CORNER DAMPING. Iteration 7 routed to 2,859 DRCs
# with the residue piled at three specific spots (DRC.md iter7 autopsy):
# the NW band ((0,2000)+(500,2000) bins) and a south pocket ((1000,500)).
# Displaced FE_OFN* opt-buffer clusters, not congestion - so this file adds
# three 25% partial blockages over those measured bins to make the piles
# spread. Everything else is fp_iter7 verbatim (hub blockage included).
# Netlist: e35abcde reference (iteration 8 proved the e36b netlist toxic).
set DIE_W 2700.0 ; set DIE_H 2700.0
floorPlan -site $FP_SITE -d $DIE_W $DIE_H \
    $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN
pnr_note "fp_iter5: die ${DIE_W}x${DIE_H}, margin $FP_CORE_MARGIN"

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
    if {$t ne "" && $t ne "0x0"} { pnr_note "fp_iter5 check: way$w dout1\[0\] at [join [dbGet $t.pt]]" }
}
# way wedges (soft regions) between each macro row and the hub
set inner [expr {$EDGE + $MH + $HALO + 6}]      ;# ~500
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

# Iteration 9: 25% damping over iteration 7's three measured residue bins.
createPlaceBlockage -type partial -density 25 -box {60 1750 1060 2400}
createPlaceBlockage -type partial -density 25 -box {900 300 1650 900}
pnr_note "fp_iter8: 25% corner damping NW (60,1750)-(1060,2400) + south (900,300)-(1650,900)"
pnr_note "fp_iter5: wedges depth $D from $lo, hub ($h0,$h0)-($h1,$h1)"
