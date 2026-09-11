# ITERATION 23 QUAD (2026-09-07) - one way per QUADRANT, hub in the middle band.
# FLOORPLAN.md section 2: on the ring (fp_iter16) every worst placed path of
# iter21 is a hub->array wire of 2.2-2.8 mm (refill_line / refill_set_id ->
# GEN_WAYS[w] array registers, -3.44 ns at 4.0). Candidate A from section 3:
# each way's 4 macros as a 2x2 block in its own corner, arranged as two
# columns whose dout1 faces an interior standard-cell channel (so no macro
# faces another macro pin-to-back), the hub in the horizontal middle band
# next to the clk pin (left edge, y=1432). Hub-to-array reach ~1 mm.
# Macro coordinates are the only real change; wedges/hub redrawn to match.
# Placement screen first (ASIC_PNR_TO=03), compare to iter21 -3.44 / -2704.
set DIE_W [config_env ASIC_FP_DIE 2900.0] ; set DIE_H $DIE_W
floorPlan -site $FP_SITE -d $DIE_W $DIE_H \
    $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN $FP_CORE_MARGIN
pnr_note "fp_iter23_quad: die ${DIE_W}x${DIE_H}, margin $FP_CORE_MARGIN"

set MW 376.48 ; set MH 446.235            ;# R0 footprint (W x H); R90/R270 swap them
set GAP 40.0 ; set EDGE 40.0 ; set HALO 8.0
set CH  [config_env ASIC_FP_WAY_CHANNEL 160.0]   ;# cell channel between the two macro columns of a block
set STRIP [config_env ASIC_FP_WAY_STRIP 260.0]   ;# soft way region extends this far past the block toward the hub
set BW [expr {2*$MH + $CH}]               ;# block width  (two R90/R270 macros + channel) ~1052
set BH [expr {2*$MW + $GAP}]              ;# block height (two rows)                     ~793
proc _place {w b x y o} {
    global HALO
    set nm "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[$b\].g_sram.u_sram"
    placeInstance $nm $x $y $o
    addHaloToBlock $HALO $HALO $HALO $HALO $nm
    dbSet [dbGet -p top.insts.name $nm].pStatus fixed
}
# A block at lower-left corner (bx,by): banks 0,1 in the left column (R270,
# dout1 -> right, into the channel), banks 2,3 in the right column (R90,
# dout1 -> left, into the channel). Rows at by and by+MW+GAP.
proc _block {w bx by} {
    global MW MH GAP CH
    set xl $bx ; set xr [expr {$bx + $MH + $CH}]
    _place $w 0 $xl $by R270
    _place $w 1 $xl [expr {$by + $MW + $GAP}] R270
    _place $w 2 $xr $by R90
    _place $w 3 $xr [expr {$by + $MW + $GAP}] R90
}
set xL $EDGE ; set xR [expr {$DIE_W - $EDGE - $BW}]
set yB $EDGE ; set yT [expr {$DIE_H - $EDGE - $BH}]
_block 0 $xL $yB     ;# way0 bottom-left
_block 3 $xR $yB     ;# way3 bottom-right
_block 2 $xL $yT     ;# way2 top-left
_block 1 $xR $yT     ;# way1 top-right
pnr_note "fp_iter23_quad: blocks ${BW}x${BH} at ($xL,$yB) ($xR,$yB) ($xL,$yT) ($xR,$yT); channel $CH"

# sanity: every macro inside the core, no two macro halos overlapping
set _boxes {}
foreach _i [dbGet -p top.insts.name *u_sram] {
    set _b [lindex [dbGet $_i.box] 0] ; if {[llength $_b] != 4} { set _b [dbGet $_i.box] }
    lassign $_b _x1 _y1 _x2 _y2
    set _cx1 $FP_CORE_MARGIN ; set _cx2 [expr {$DIE_W - $FP_CORE_MARGIN}]
    if {$_x1 < $_cx1 || $_y1 < $_cx1 || $_x2 > $_cx2 || $_y2 > $_cx2} { pnr_fail "fp_iter23_quad: [dbGet $_i.name] outside core: $_b" }
    foreach _o $_boxes {
        lassign $_o _ox1 _oy1 _ox2 _oy2
        if {$_x1 < $_ox2 + 2*$HALO && $_ox1 < $_x2 + 2*$HALO && $_y1 < $_oy2 + 2*$HALO && $_oy1 < $_y2 + 2*$HALO} { pnr_fail "fp_iter23_quad: macro halo overlap at $_b vs $_o" }
    }
    lappend _boxes [list $_x1 $_y1 $_x2 $_y2]
}
pnr_note "fp_iter23_quad check: [llength $_boxes] macros placed, no overlap, all inside core"
foreach w {0 2} {
    set t [dbGet -p top.insts.instTerms.name "GEN_WAYS\[$w\].FLAG_TAG_DATA_ARRAY_g_bank\[0\].g_sram.u_sram/dout1\[0\]" -e]
    if {$t ne "" && $t ne "0x0"} { pnr_note "fp_iter23_quad check: way$w bank0 dout1\[0\] at [join [dbGet $t.pt]] (should be on the channel side)" }
}

# way regions (soft): block bbox + STRIP toward the hub on both inner sides.
# The block interior (channel) and the strips are where the way's cells land.
set x0L $xL ; set x1L [expr {$xL + $BW + $STRIP}]
set x0R [expr {$xR - $STRIP}] ; set x1R [expr {$xR + $BW}]
set y0B $yB ; set y1B [expr {$yB + $BH + $STRIP}]
set y0T [expr {$yT - $STRIP}] ; set y1T [expr {$yT + $BH}]
createInstGroup way0 -region $x0L $y0B $x1L $y1B
createInstGroup way3 -region $x0R $y0B $x1R $y1B
createInstGroup way2 -region $x0L $y0T $x1L $y1T
createInstGroup way1 -region $x0R $y0T $x1R $y1T
foreach w {0 1 2 3} { addInstToInstGroup way$w "GEN_WAYS\[$w\]*" }
# hub guide = middle band between the way regions, trimmed at the sides
set HUB_X_INSET [config_env ASIC_FP_HUB_X_INSET 600.0]
set h0x $HUB_X_INSET ; set h1x [expr {$DIE_W - $HUB_X_INSET}]
set h0y $y1B ; set h1y $y0T
createInstGroup hub -guide $h0x $h0y $h1x $h1y
foreach pat {COMPARE_SELECT_REPLACE_* RESPONSE_UNIT* MSHR_* ADDR_DECODE_* REPLACEMENT_* inreg_*} {
    addInstToInstGroup hub $pat
}
# same 40% partial blockage over the hub as fp_iter7/16 (G7b), one variable
createPlaceBlockage -type partial -density 40 -box [list $h0x $h0y $h1x $h1y]
pnr_note "fp_iter23_quad: way regions strip $STRIP; hub guide ($h0x,$h0y)-($h1x,$h1y) with 40% partial blockage"
# v2 (2026-09-08 11:30, after iter23q routed to 5,932 DRC with 4,244 of them
# in x 500-650 / y 700-900 = the top of way 0's interior channel, the only
# exit of a 160 um slot closed by the die edge; way 3's mirror channel had 0):
#   ASIC_FP_WAY_CHANNEL=260   widens every channel mouth (block 1152 wide)
#   ASIC_FP_PIN_BAND=1        all I/O pins on the LEFT edge inside the hub
#                             band, so the 117+95 default left/bottom pins
#                             stop escaping through way 0's corner.
if {[config_env ASIC_FP_PIN_BAND 0]} {
    set _pins [dbGet top.terms.name]
    set _py0 [expr {$h0y + 20.0}] ; set _py1 [expr {$h1y - 20.0}]
    set _px  $FP_CORE_MARGIN
    if {[catch {editPin -pin $_pins -side LEFT -layer 4 -spreadType range -spreadDirection clockwise \
                    -start [list $_px $_py0] -end [list $_px $_py1] -fixOverlap 1} _m]} {
        pnr_note "fp_iter23_quad v2: editPin FAILED ($_m) - pins left at their default places"
    } else {
        set _in 0
        foreach _t [dbGet top.terms] {
            lassign [lindex [dbGet $_t.pt] 0] _x1 _y1
            if {$_x1 < 60 && $_y1 >= $_py0 - 1 && $_y1 <= $_py1 + 1} { incr _in }
        }
        pnr_note "fp_iter23_quad v2: [llength $_pins] pins spread on the left edge y $_py0..$_py1 on met3; $_in verified inside the band"
    }
}

