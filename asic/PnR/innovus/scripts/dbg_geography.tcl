# Debug utility: congestion reports + module placement geography.
# Session-safe: analyzes whatever design is in memory, saves nothing.
# Usage (any time after placement):  source scripts/dbg_geography.tcl

reportCongestion -overflow > [pnr_rpt place congestion.rpt]
reportCongestion -hotspot  > [pnr_rpt place congestion_hotspot.rpt]
checkPlace                 > [pnr_rpt place checkplace.rpt]

set _geo [pnr_rpt place placement_geography.txt]
catch {close $fp}
set fp [open $_geo w]
set _die [join [lindex [dbGet top.fPlan.box] 0]]
puts $fp "Module placement geography (um). Die ([lindex $_die 0],[lindex $_die 1])-([lindex $_die 2],[lindex $_die 3])"
puts $fp ""

proc grp {tag pat} {
    global fp
    set ps [dbGet -p top.insts.name $pat -e]
    if {$ps eq "" || $ps eq "0x0"} { puts $fp [format "%-34s NO MATCH (%s)" $tag $pat]; return }
    set n 0; set sx 0.0; set sy 0.0
    set minx 1e12; set miny 1e12; set maxx -1e12; set maxy -1e12
    foreach b [dbGet $ps.box] {
        set b [join $b]
        set x0 [lindex $b 0]; set y0 [lindex $b 1]
        set x1 [lindex $b 2]; set y1 [lindex $b 3]
        set sx [expr {$sx + ($x0+$x1)/2.0}]
        set sy [expr {$sy + ($y0+$y1)/2.0}]
        incr n
        if {$x0<$minx} {set minx $x0}
        if {$y0<$miny} {set miny $y0}
        if {$x1>$maxx} {set maxx $x1}
        if {$y1>$maxy} {set maxy $y1}
    }
    puts $fp [format "%-34s n=%6d  centroid=(%6.0f,%6.0f)  bbox=(%5.0f,%5.0f)-(%5.0f,%5.0f)  span=%4.0fx%4.0f" \
        $tag $n [expr {$sx/$n}] [expr {$sy/$n}] $minx $miny $maxx $maxy \
        [expr {$maxx-$minx}] [expr {$maxy-$miny}]]
}

foreach w {0 1 2 3} {
    grp "way$w all (GEN_WAYS\[$w\])"   "GEN_WAYS\\\[$w\\\].*"
    grp "way$w tag-read regs"          "GEN_WAYS\\\[$w\\\].FLAG_TAG_DATA_ARRAY_g_read_registered.*"
}
grp "rindex_rep_r (way0 survivor)"  "GEN_WAYS\\\[0\\\].rindex_rep_r_reg*"
grp "ADDR_DECODE (S0)"              "ADDR_DECODE_*"
grp "COMPARE_SELECT_REPLACE (S1)"   "COMPARE_SELECT_REPLACE_*"
grp "REPLACEMENT (PLRU)"            "REPLACEMENT_*"
grp "MSHR_FILE (all)"               "MSHR_FILE_*"
grp "RESPONSE_UNIT (all)"           "RESPONSE_UNIT_*"
grp "MSHR_REQ_ARBITER"              "MSHR_REQ_ARBITER_*"
grp "input regs (inreg_*)"          "inreg_*"

puts $fp ""
puts $fp "SRAM macros (fixed):"
foreach p [dbGet -p2 top.insts.cell.name sram_1rw1r* -e] {
    set nm [dbGet $p.name]
    set b  [join [dbGet $p.box]]
    puts $fp [format "  %-58s (%5.0f,%5.0f)-(%5.0f,%5.0f)" $nm \
        [lindex $b 0] [lindex $b 1] [lindex $b 2] [lindex $b 3]]
}
close $fp
puts "geography written to $_geo"
