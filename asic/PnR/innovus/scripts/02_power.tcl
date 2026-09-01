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

# ---------------------------------------------------------------------------
# Follow pins
# ---------------------------------------------------------------------------
# Connects the standard-cell rows' VPWR/VGND rails to the ring and stripes.
sroute -nets [list $PG_POWER_NET $PG_GROUND_NET] \
       -connect { corePin padPin blockPin } \
       -allowJogging 1 -allowLayerChange 1

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
