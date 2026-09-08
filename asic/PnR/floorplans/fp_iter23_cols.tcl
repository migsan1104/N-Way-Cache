# ITERATION 23 COLS (2026-09-07) - two macro COLUMNS, hub in the centre channel.
# FLOORPLAN.md section 3 candidate B: ways 0+2 as a 2-wide x 4-tall block on the
# left, ways 1+3 on the right, each block's two macro columns facing an interior
# cell channel (dout1 into the channel), the shared logic in the vertical channel
# between the blocks. Longest hub-to-array reach ~1.2 mm (ring: ~2.6 mm).
# Macro coordinates are the real change; way regions and hub redrawn to match.
# Placement screen first (ASIC_PNR_TO=03), compare to iter21 -3.44 / -2704.
set DIE_W [config_env ASIC_FP_DIE 2900.0] ; set DIE_H $DIE_W
floorPlan -site $FP_SITE -d $DIE_W $DIE_H \
    $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN
pnr_note "fp_iter23_cols: die ${DIE_W}x${DIE_H}, margin $FP_CORE_MARGIN"

set MW 376.48 ; set MH 446.235            ;# R0 footprint; R90/R270 swap them
set GAP 40.0 ; set EDGE 40.0 ; set HALO 8.0
set CH  [config_env ASIC_FP_WAY_CHANNEL 160.0]   ;# cell channel between the two macro columns
set STRIP [config_env ASIC_FP_WAY_STRIP 130.0]   ;# soft way region past the block toward the hub
set BW [expr {2*$MH + $CH}]               ;# block width ~1052
set WH [expr {2*$MW + $GAP}]              ;# one way = two rows ~793
set BH [expr {2*$WH + $GAP}]              ;# two ways stacked ~1626
proc _place {w b x y o} {
    global HALO
    set nm "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[$b\].g_sram.u_sram"
    placeInstance $nm $x $y $o
    addHaloToBlock $HALO $HALO $HALO $HALO $nm
    dbSet [dbGet -p top.insts.name $nm].pStatus fixed
}
# one way = 2x2: banks 0,1 left column (R270, dout1 -> right), banks 2,3 right
# column (R90, dout1 -> left); rows at by and by+MW+GAP.
proc _way2x2 {w bx by} {
    global MW MH GAP CH
    set xl $bx ; set xr [expr {$bx + $MH + $CH}]
    _place $w 0 $xl $by R270
    _place $w 1 $xl [expr {$by + $MW + $GAP}] R270
    _place $w 2 $xr $by R90
    _place $w 3 $xr [expr {$by + $MW + $GAP}] R90
}
set xL $EDGE ; set xR [expr {$DIE_W - $EDGE - $BW}]
set yB [expr {($DIE_H - $BH)/2.0}] ; set yT [expr {$yB + $WH + $GAP}]
_way2x2 0 $xL $yB    ;# way0 left, lower
_way2x2 2 $xL $yT    ;# way2 left, upper
_way2x2 3 $xR $yB    ;# way3 right, lower
_way2x2 1 $xR $yT    ;# way1 right, upper
pnr_note "fp_iter23_cols: blocks ${BW}x${BH} at x=$xL and x=$xR, y from $yB; channel $CH"

# sanity: inside core, no halo overlap
set _boxes {}
foreach _i [dbGet -p top.insts.name *u_sram] {
    set _b [lindex [dbGet $_i.box] 0] ; if {[llength $_b] != 4} { set _b [dbGet $_i.box] }
    lassign $_b _x1 _y1 _x2 _y2
    set _cx1 $FP_CORE_MARGIN ; set _cx2 [expr {$DIE_W - $FP_CORE_MARGIN}]
    if {$_x1 < $_cx1 || $_y1 < $_cx1 || $_x2 > $_cx2 || $_y2 > $_cx2} { pnr_fail "fp_iter23_cols: [dbGet $_i.name] outside core: $_b" }
    foreach _o $_boxes {
        lassign $_o _ox1 _oy1 _ox2 _oy2
        if {$_x1 < $_ox2 + 2*$HALO && $_ox1 < $_x2 + 2*$HALO && $_y1 < $_oy2 + 2*$HALO && $_oy1 < $_y2 + 2*$HALO} { pnr_fail "fp_iter23_cols: macro halo overlap at $_b vs $_o" }
    }
    lappend _boxes [list $_x1 $_y1 $_x2 $_y2]
}
pnr_note "fp_iter23_cols check: [llength $_boxes] macros placed, no overlap, all inside core"
foreach w {0 2} {
    set t [dbGet -p top.insts.instTerms.name "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[0\].g_sram.u_sram/dout1\[0\]" -e]
    if {$t ne "" && $t ne "0x0"} { pnr_note "fp_iter23_cols check: way$w bank0 dout1\[0\] at [join [dbGet $t.pt]] (should be on the channel side)" }
}

# way regions (soft): each way's half-block bbox + STRIP toward the centre
# + the free band beyond its end of the block (below for the lower ways,
# above for the upper ways). First cut (2026-09-07 23:30) used the half-block
# alone: 0.23 mm2 for 0.18 mm2 of cells = 78% density against the 55% cap,
# 18,251 instances could not be legalized. The ring/quad give ~0.53 mm2.
set x1L [expr {$xL + $BW + $STRIP}] ; set x0R [expr {$xR - $STRIP}]
set yLo $FP_CORE_MARGIN ; set yHi [expr {$DIE_H - $FP_CORE_MARGIN}]
createInstGroup way0 -region $xL $yLo $x1L [expr {$yB + $WH}]
createInstGroup way2 -region $xL $yT $x1L $yHi
createInstGroup way3 -region $x0R $yLo [expr {$xR + $BW}] [expr {$yB + $WH}]
createInstGroup way1 -region $x0R $yT [expr {$xR + $BW}] $yHi
foreach w {0 1 2 3} { addInstToInstGroup way$w "GEN_WAYS\[$w\]*" }
# hub guide = the centre channel, full core height
set h0x $x1L ; set h1x $x0R
set h0y $FP_CORE_MARGIN ; set h1y [expr {$DIE_H - $FP_CORE_MARGIN}]
createInstGroup hub -guide $h0x $h0y $h1x $h1y
foreach pat {COMPARE_SELECT_REPLACE_* RESPONSE_UNIT_* MSHR_* ADDR_DECODE_* REPLACEMENT_* inreg_*} {
    addInstToInstGroup hub $pat
}
# no partial blockage here: the ring's 40% hub cap (G7b) was a congestion fix
# for a 1140x1140 hub; this hub is a 456 um channel and already needs every site.
pnr_note "fp_iter23_cols: way regions strip $STRIP + end bands; hub guide ($h0x,$h0y)-($h1x,$h1y) [expr {$h1x-$h0x}] um wide, no blockage"
