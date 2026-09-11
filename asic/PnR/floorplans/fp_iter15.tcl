# ITERATION 7 (G7b) - fp_iter5 + a PARTIAL PLACEMENT BLOCKAGE over the hub.
# G7-diag on iter5's routed DB measured the cause the density cap missed:
# 36.5% of core bins placed at 0.95-1.00 density (density_map.rpt) and hub
# track supply exhausted (26% tracks remaining inside the 940 um hub vs ~56%
# outside, ~24k gcells full - DRC.md, G7-diag). -place_global_max_density
# bounds the GLOBAL placer target only; regions/guides and opt blew past it
# locally. This file caps the hub the hard way: a 40% partial blockage over
# the hub square, so ~60% of each bin stays open for wires. Everything else
# is fp_iter5 verbatim.
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
pnr_note "fp_iter5: wedges depth $D from $lo, hub ($h0,$h0)-($h1,$h1)"

# ---------------------------------------------------------------------------
# ITERATION 15 ADDITION (2026-09-01): cluster damping over the armB/surgery
# measured violation boxes. Arms B and C proved fp_iter7's base route owes
# ~625 un-reroutable violations clustered at the ring-corner convergence
# zones and two macro seams; surgery is testing post-route density relief on
# the routed DB. This applies the same relief PRE-placement (the fp_iter8
# precedent: damping blockages over measured bins), so cells never crowd
# these tiles and no post-hoc refinePlace scramble is needed. 50% matches
# surgery's dose; boxes are surgery's (marker map + 60 um margin, die-clipped).
# Everything above is fp_iter7 verbatim.
foreach _b {
    {2102 497 2700 696}
    {192 2013 525 2212}
    {2134 2025 2429 2182}
    {2036 2174 2166 2347}
} {
    createPlaceBlockage -type partial -density 50 -box $_b
    pnr_note "fp_iter15: cluster damping 50% at $_b"
}
