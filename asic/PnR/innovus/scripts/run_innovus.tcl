# Driver: run the staged flow end to end, or a slice of it.
#
#   innovus -files scripts/run_innovus.tcl
#
# Environment:
#   ASIC_PNR_FROM   first stage to run   (default 00)
#   ASIC_PNR_TO     last stage to run    (default 06)
#
# Each stage saves its own database, and every stage script can restore the
# previous one on its own, so a failure never costs the stages before it:
#
#   ASIC_PNR_FROM=05 ASIC_PNR_TO=06 innovus -files scripts/run_innovus.tcl
#
# re-routes/re-optimises and re-exports without re-placing. The optimisation stages are
# split out from the structural ones (place/CTS/route) precisely so that opt
# settings can be retuned cheaply - that is the whole point of 10 stages
# instead of 7. That is the same reason run_genus.tcl keeps a
# reopenable db - a lost hour of placement is a lost hour.
#
# For the interactive loop the stages are meant to be sourced by hand:
#   source scripts/00_init.tcl
#   source scripts/01_floorplan.tcl
#   ... look at the GUI, adjust 01's tunables, source it again ...

set _here [file normalize [file dirname [info script]]]

# Renumbered 2026-08-30 after combining 03+04, 05+06, 07+08: seven live
# stages, 00-06. Run-1/v2 artifacts on disk keep the OLD numbering
# (04_prects_opt.enc, 07_route.enc, 09_final.enc ...); scripts/retired/
# holds the old split stages under their old numbers.
set STAGES {
    00 00_init.tcl
    01 01_floorplan.tcl
    02 02_power.tcl
    03 03_place.tcl
    04 04_cts.tcl
    05 05_route.tcl
    06 06_export.tcl
}

# innovus_config.tcl defines config_env, but the driver needs it before the
# first stage runs.
proc _drv_env {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}

set FROM [_drv_env ASIC_PNR_FROM 00]
set TO   [_drv_env ASIC_PNR_TO   06]

# Restarting mid-flow: load the config only (the stage script restores the
# database itself). Sourcing 00_init.tcl here would re-run init_design and throw
# away the very stages being resumed from.
if {$FROM ne "00"} {
    source [file join $_here innovus_config.tcl]
    pnr_note "resuming at stage $FROM in run $PNR_RUN_STAMP"
}

set ran {}
foreach {num script} $STAGES {
    if {[string compare $num $FROM] < 0} { continue }
    if {[string compare $num $TO]   > 0} { break }

    puts "\n================ STAGE $num : $script ================"
    if {[catch {source [file join $_here $script]} msg]} {
        puts stderr "ERROR: stage $num ($script) failed: $msg"
        puts stderr "       Databases up to the previous stage are intact in db/."
        exit 1
    }
    lappend ran $num
}

puts "\n================ stages run: $ran ================"
exit 0
