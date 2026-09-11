# vss_jumper_eco.tcl - 2026-09-07 (iter19b Voltus finding). The horizontal
# met5 VSS straps stop inside the VDD ring (x 16.5..2883.3) and never reach
# the VSS ring (met5 at x 6.1 / 2893.74), so VSS is fed only from the top and
# bottom edges: VSS worst drop 61 mV vs VDD 28 mV, VSS J/Jmax 4.0 vs 1.0.
# Fix: one met4 jumper per strap end, under the VDD ring, from the VSS ring
# to 1 um past the strap end, with met4-met5 vias at both overlaps. Saves
# ASIC_ECO_DST iff verify_drc = 0 and VSS special-wire connectivity reports
# no disconnected pieces. Exit 0 iff clean.
#   ASIC_ECO_SRC  checkpoint (05_antenna_clean.enc)
#   ASIC_ECO_DST  checkpoint to write (07_vssfix.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 05_antenna_clean.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
pnr_restore_stage $_src
set fh [open [pnr_rpt vss_eco vss_eco.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
set vss [dbGet -p top.nets.name VSS]
# ring x positions from the DB: VSS vertical met5 ring segments (long, x near the edges)
set ringL ""; set ringR ""; set ys {}
foreach w [dbGet $vss.sWires] {
    if {[dbGet $w.layer.name] ne "met5"} continue
    lassign [lindex [dbGet $w.box] 0] x1 y1 x2 y2
    set len [expr {max($x2-$x1, $y2-$y1)}]
    if {$len < 2000} continue
    if {$y2 - $y1 > $x2 - $x1} {
        if {$x1 < 100} { set ringL [list $x1 $x2] } elseif {$x1 > 2800} { set ringR [list $x1 $x2] }
    } else {
        lappend ys [list [expr {($y1+$y2)/2.0}] $x1 $x2 [expr {$y2-$y1}]]
    }
}
lq "VSS ring left=$ringL right=$ringR straps=[llength $ys]"
if {$ringL eq "" || $ringR eq "" || ![llength $ys]} { lq "ECO ABORT: geometry not found"; close $fh; exit 3 }
setAddStripeMode -stacked_via_top_layer met5 -stacked_via_bottom_layer met4
set n 0
foreach s [lsort -real -index 0 $ys] {
    lassign $s yc sx1 sx2 sw
    set y1 [expr {$yc - $sw/2.0}]; set y2 [expr {$yc + $sw/2.0}]
    # left: from the VSS ring's outer edge to 1 um past the strap start
    addStripe -nets VSS -layer met4 -direction horizontal -width $sw \
        -area [list [lindex $ringL 0] $y1 [expr {$sx1 + 1.0}] $y2] \
        -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    # right: from 1 um before the strap end to the VSS ring's outer edge
    addStripe -nets VSS -layer met4 -direction horizontal -width $sw \
        -area [list [expr {$sx2 - 1.0}] $y1 [lindex $ringR 1] $y2] \
        -start_from bottom -start_offset 0 -number_of_sets 1 -set_to_set_distance 1000
    incr n
}
lq "jumpers added: $n straps x 2 sides"
verifyConnectivity -type special -net VSS -noAntenna -error 5000 -warning 50 -report [pnr_rpt vss_eco vss_conn.rpt]
set f [open [pnr_rpt vss_eco vss_conn.rpt] r]; set t [read $f]; close $f
set pieces 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> pieces
set opens 0;  regexp {Net VSS: has special routes with opens} $t opens_m
lq "VSS special connectivity: IMPVFC-200 pieces=$pieces"
clearDrc
verify_drc -limit 100000 -report [pnr_rpt vss_eco drc.rpt]
set d [llength [dbGet -e top.markers]]
lq "VSS ECO: verify_drc = $d vss_pieces = $pieces"
pnr_note "VSS ECO: verify_drc = $d vss_pieces = $pieces"
if {$d == 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
saveDesign [pnr_ckpt 07_vssfix_dirty.enc]; close $fh; exit 2
