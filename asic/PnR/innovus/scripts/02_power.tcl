# Stage 02 - power: global net connections, rings, stripes, follow-pin routing.
#
# The sky130 trap lives here. Standard cells do NOT use VDD/VSS: they use
# VPWR/VGND for supply and VPB/VNB for the well/bulk taps, and every one of the
# four needs an explicit connection. The SRAM macros use different names again
# (vccd1/vssd1). A missed connection does not error - it produces a design whose
# power is silently unconnected, discovered at verifyConnectivity after the run.

set _here [file normalize [file dirname [info script]]]
# Config first (idempotent), then restore the previous stage ONLY if no
# design is in memory.  Testing PNR_RUN_DIR alone is wrong: a stage that
# failed after sourcing the config leaves the variable defined and a
# re-source then skips the restore (floorPlan "unithd does not match any
# object in design" - first shakedown 2026-08-26).
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
if {[dbGet -e top] eq ""} { pnr_restore_stage 01_floorplan.enc }

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
set PG_RING_WIDTH   [config_env ASIC_PG_RING_WIDTH 4]
set PG_RING_SPACING [config_env ASIC_PG_RING_SPACING 2]
set PG_RING_LAYER_H [config_env ASIC_PG_RING_LAYER_H met4]
set PG_RING_LAYER_V [config_env ASIC_PG_RING_LAYER_V met5]

set PG_STRIPE_LAYER   [config_env ASIC_PG_STRIPE_LAYER met4]
set PG_STRIPE_WIDTH   [config_env ASIC_PG_STRIPE_WIDTH 2]
set PG_STRIPE_SPACING [config_env ASIC_PG_STRIPE_SPACING 2]
set PG_STRIPE_PITCH   [config_env ASIC_PG_STRIPE_PITCH 60]

# ---------------------------------------------------------------------------
# Global net connections
# ---------------------------------------------------------------------------
# Standard cells: supply + bulk. All four, or the design floats.
foreach pin $PG_CELL_POWER_PINS {
    globalNetConnect $PG_POWER_NET -type pgpin -pin $pin -inst * -override
    pnr_note "globalNetConnect $PG_POWER_NET <- cell pin $pin"
}
foreach pin $PG_CELL_GROUND_PINS {
    globalNetConnect $PG_GROUND_NET -type pgpin -pin $pin -inst * -override
    pnr_note "globalNetConnect $PG_GROUND_NET <- cell pin $pin"
}

# SRAM macros: their own pin names. Verify against the LEF actually linked -
# the 1kbyte/2kbyte sky130 variants use vccd1/vssd1, but the OpenRAM-generated
# LEF here declares lowercase vdd/gnd (grep "USE POWER" in lef/*.lef). Case and
# name both matter; a wrong name matches nothing and warns only at sroute.
if {$SRAM_MACRO} {
    foreach pin $PG_MACRO_POWER_PINS {
        globalNetConnect $PG_POWER_NET -type pgpin -pin $pin -inst * -override
        pnr_note "globalNetConnect $PG_POWER_NET <- macro pin $pin"
    }
    foreach pin $PG_MACRO_GROUND_PINS {
        globalNetConnect $PG_GROUND_NET -type pgpin -pin $pin -inst * -override
        pnr_note "globalNetConnect $PG_GROUND_NET <- macro pin $pin"
    }
}

# Tie cells and the net-level connections.
globalNetConnect $PG_POWER_NET  -type tiehi -inst * -override
globalNetConnect $PG_GROUND_NET -type tielo -inst * -override

applyGlobalNets

# ---------------------------------------------------------------------------
# Core ring
# ---------------------------------------------------------------------------
setAddRingMode -ring_target default -extend_over_row 0 \
               -avoid_short 1 -stacked_via_top_layer met5 \
               -stacked_via_bottom_layer met1

addRing -nets [list $PG_POWER_NET $PG_GROUND_NET] \
        -type core_rings -follow core \
        -layer [list top $PG_RING_LAYER_H bottom $PG_RING_LAYER_H \
                     left $PG_RING_LAYER_V right $PG_RING_LAYER_V] \
        -width $PG_RING_WIDTH \
        -spacing $PG_RING_SPACING \
        -offset $PG_RING_SPACING

pnr_note "core ring: ${PG_RING_WIDTH}um on $PG_RING_LAYER_H/$PG_RING_LAYER_V"

# ---------------------------------------------------------------------------
# Stripes
# ---------------------------------------------------------------------------
# Pitch is a starting value. Too sparse shows up as IR drop; too dense eats
# routing resource over the macros. Check the congestion map after 03_place.
setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met1

addStripe -nets [list $PG_POWER_NET $PG_GROUND_NET] \
          -layer $PG_STRIPE_LAYER \
          -direction vertical \
          -width $PG_STRIPE_WIDTH \
          -spacing $PG_STRIPE_SPACING \
          -set_to_set_distance $PG_STRIPE_PITCH \
          -start_from left

pnr_note "stripes: $PG_STRIPE_LAYER width $PG_STRIPE_WIDTH pitch $PG_STRIPE_PITCH"

# Horizontal straps (iter17, 2026-09-04). OFF unless ASIC_PG_STRIPE_H_LAYER is
# set, so no other run changes. The vertical met4 stripes stop at the SRAM
# macros (LEF OBS met1-met4), so the hub inside the macro ring is fed only
# through the four corner gaps: Voltus static IR on iter16b = 119/121 mV vs a
# 53 mV budget (voltus.md "First static IR result"). met5 is free over the
# macros; horizontal met5 straps ring-to-ring cross them and stack down onto
# the hub's met4 stripes. Pitch sized on iter16b's own DB with Voltus what-if
# shapes: 120 um -> 65 mV, 60 um -> 47 mV (ITER17_PLAN.md section 3).
set PG_STRIPE_H_LAYER [config_env ASIC_PG_STRIPE_H_LAYER {}]
if {$PG_STRIPE_H_LAYER ne ""} {
    set PG_STRIPE_H_WIDTH   [config_env ASIC_PG_STRIPE_H_WIDTH 2]
    set PG_STRIPE_H_SPACING [config_env ASIC_PG_STRIPE_H_SPACING 2]
    set PG_STRIPE_H_PITCH   [config_env ASIC_PG_STRIPE_H_PITCH 60]
    addStripe -nets [list $PG_POWER_NET $PG_GROUND_NET] \
              -layer $PG_STRIPE_H_LAYER \
              -direction horizontal \
              -width $PG_STRIPE_H_WIDTH \
              -spacing $PG_STRIPE_H_SPACING \
              -set_to_set_distance $PG_STRIPE_H_PITCH \
              -start_from bottom
    pnr_note "horizontal straps: $PG_STRIPE_H_LAYER width $PG_STRIPE_H_WIDTH pitch $PG_STRIPE_H_PITCH"
}

# Strap-to-ring jumpers (iter19b Voltus finding, 2026-09-07). addStripe stops a
# horizontal strap at the FIRST ring it meets on its own layer, so the net whose
# ring is the outer one (VSS: ring x 4.1-8.1, VDD ring x 10.1-14.1 inside it)
# gets straps that end at the VDD ring (x 16.5..2883.3) and never touch the VSS
# ring. VSS was then fed only from the top/bottom edges: 61 mV drop vs VDD's
# 28 mV, VSS EM 4.0x the LEF limit (voltus.md "VSS straps stop at the VDD
# ring"). One met4 jumper per strap end, under the inner ring, closes the gap;
# placed here, before routing, NanoRoute simply routes around it (the same
# jumpers as a post-route ECO on 19b collided with 94 pin-escape nets).
set PG_STRAP_JUMPERS [config_env ASIC_PG_STRAP_JUMPERS 1]
if {$PG_STRIPE_H_LAYER ne "" && $PG_STRAP_JUMPERS} {
    set jl [config_env ASIC_PG_STRAP_JUMPER_LAYER met4]
    setAddStripeMode -stacked_via_top_layer $PG_STRIPE_H_LAYER -stacked_via_bottom_layer $jl
    set die [dbGet top.fPlan.box]; lassign [lindex $die 0] dx1 dy1 dx2 dy2
    foreach pgnet [list $PG_POWER_NET $PG_GROUND_NET] {
        set nobj [dbGet -p top.nets.name $pgnet]
        set ringL ""; set ringR ""; set straps {}
        foreach w [dbGet $nobj.sWires] {
            set lay [dbGet $w.layer.name]
            lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
            if {$lay eq $PG_RING_LAYER_V && ($y2 - $y1) > ($dy2 - $dy1) * 0.5} {
                if {$x1 < ($dx1 + $dx2) / 2.0} { set ringL [list $x1 $x2] } else { set ringR [list $x1 $x2] }
            } elseif {$lay eq $PG_STRIPE_H_LAYER && ($x2 - $x1) > ($dx2 - $dx1) * 0.5} {
                lappend straps [list $x1 $y1 $x2 $y2]
            }
        }
        if {$ringL eq "" || $ringR eq ""} { pnr_note "strap jumpers: $pgnet vertical ring not found - skipped"; continue }
        set nj 0
        foreach sb $straps {
            lassign $sb sx1 sy1 sx2 sy2
            set w [expr {$sy2 - $sy1}]
            if {$sx1 > [lindex $ringL 1] + 0.01} {
                addStripe -nets $pgnet -layer $jl -direction horizontal -width $w \
                    -area [list [lindex $ringL 0] $sy1 [expr {$sx1 + 1.0}] $sy2] \
                    -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
                incr nj
            }
            if {$sx2 < [lindex $ringR 0] - 0.01} {
                addStripe -nets $pgnet -layer $jl -direction horizontal -width $w \
                    -area [list [expr {$sx2 - 1.0}] $sy1 [lindex $ringR 1] $sy2] \
                    -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
                incr nj
            }
        }
        pnr_note "strap jumpers: $pgnet [llength $straps] straps, $nj $jl jumpers to the $PG_RING_LAYER_V ring"
    }
    setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met1
}

# ---------------------------------------------------------------------------
# Follow pins
# ---------------------------------------------------------------------------
# Connects the standard-cell rows' VPWR/VGND rails to the ring and stripes.
# li1 is NOT allowed for PG routing (2026-09-04 21:20 finding, DRC.md "li1
# under the macros"): the SRAM LEF obstructs met1-met4 only, so sroute with an
# unbounded layer change dropped to li1 and bridged the met1 rails ACROSS the
# macro bodies on li1 (iter16b: 368 of 370 li1 special wires inside macro
# footprints, up to 371 um long, on top of the macro's own li1 = VSS/VDD
# shorts into the SRAM periphery that verify_drc cannot see). The LEF now also
# carries an li1 OBS; this range is the belt to that suspender.
set PG_SROUTE_LAYER_RANGE [config_env ASIC_PG_SROUTE_LAYER_RANGE {met1 met4}]
sroute -nets [list $PG_POWER_NET $PG_GROUND_NET] \
       -connect { corePin padPin blockPin } \
       -allowJogging 1 -allowLayerChange 1 \
       -layerChangeRange $PG_SROUTE_LAYER_RANGE
set _li1 [llength [dbGet -p2 top.nets.sWires.layer.name li1 -e]]
if {$_li1 > 0} { pnr_fail "stage 02: $_li1 li1 special wires exist after sroute - PG on li1 is forbidden (see comment above)" }
pnr_note "sroute layer range $PG_SROUTE_LAYER_RANGE; li1 special wires: $_li1"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
# Run these now. verifyConnectivity on PG at this stage catches a wrong pin name
# immediately; the same mistake found after routing costs the whole run.
verifyConnectivity -type special -noAntenna \
    > [pnr_rpt power connectivity.rpt]
verifyGeometry > [pnr_rpt power geometry.rpt]

saveDesign [pnr_ckpt 02_power.enc]
pnr_note "stage 02 (power) complete - check 02_pg_connectivity.rpt for opens"
