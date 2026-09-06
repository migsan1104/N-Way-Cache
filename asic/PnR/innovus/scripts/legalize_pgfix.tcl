# legalize_pgfix.tcl - 2026-09-06 (iter19b, 5 PG markers left after fixup).
#  * NSMETAL VSS via at (922,2860): iter16b fix8-10 sequence - delete the
#    under-enclosed M3M4 via, re-add the met4 VSS stripe stub from y 2861
#    up to the ring (legalize_fixup deleted the old stub), re-drop vias.
#  * MINWIDTH met5 VDD (via4 enclosure pads protruding below the 2 um strap
#    at four macro pin crossings): delete those via stacks; each is one of
#    dozens of strap-to-pin connections per macro.
# Prints every PG object in each marker box before touching it. Reads the
# markers from ASIC_LEGALIZE_DRC_RPT (drc_after_fixup.rpt), saves
# 05_legal_pgfix.enc, verifies special connectivity of VDD/VSS.
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_LEGALIZE_SRC 05_legal_fixup.enc]
pnr_restore_stage $_src
set fh [open [pnr_rpt legalize pgfix.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
proc show {tag box} {
    foreach o [dbQuery -area $box -objType {sWire sVia wire via}] {
        catch { lq "$tag obj=[dbGet $o.objType] layer=[dbGet -e $o.layer.name] net=[dbGet -e $o.net.name] box=[dbGet -e $o.box] via=[dbGet -e $o.via.name] pt=[dbGet -e $o.pt] shape=[dbGet -e $o.shape]" }
    }
}
set _rpt [config_env ASIC_LEGALIZE_DRC_RPT [pnr_rpt legalize drc_after_fixup.rpt]]
set items {}; set cur ""
set f [open $_rpt r]
while {[gets $f l] >= 0} {
    if {[regexp {^([A-Z]+):(.*)$} $l -> t rest]} { set cur [list $t $rest]; continue }
    if {[regexp {^Bounds\s*:\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)} $l -> x1 y1 x2 y2] && $cur ne ""} {
        lappend items [list [lindex $cur 0] [lindex $cur 1] $x1 $y1 $x2 $y2]; set cur ""
    }
}
close $f
lq "src=$_src items=[llength $items] markers_in_db=[llength [dbGet -e top.markers]]"
foreach it $items {
    lassign $it t rest x1 y1 x2 y2
    set big [list [expr {$x1-3}] [expr {$y1-3}] [expr {$x2+3}] [expr {$y2+3}]]
    lq "--- $t at ($x1,$y1)-($x2,$y2): [string trim $rest]"
    show "  before" $big
    if {$t eq "NSMETAL"} {
        editPowerVia -delete_vias true -area [list [expr {$x1-1}] [expr {$y1-0.6}] [expr {$x2+1}] [expr {$y2+0.9}]] -top_layer met4 -bottom_layer met3
        setEdit -nets VSS -type Special -shape STRIPE -layer_vertical met4 -width_vertical 2.0 -status FIXED
        set xc [expr {($x1+$x2)/2.0}]
        editAddRoute $xc [expr {$y2+0.9}]
        editCommitRoute $xc 2883.0
        editPowerVia -add_vias true -area [list [expr {$xc-2.1}] [expr {$y2+0.4}] [expr {$xc+2.1}] 2896.0] -top_layer met5 -bottom_layer met1 -nets VSS
    } elseif {$t eq "MINWIDTH" && [string match *met5* $rest]} {
        editPowerVia -delete_vias true -area [list $x1 $y1 $x2 $y2] -top_layer met5 -bottom_layer met4
    }
    show "  after " $big
}
foreach n {VDD VSS} { catch { verifyConnectivity -type special -net $n -noAntenna -noWeakConnect -report [pnr_rpt legalize ${n}_conn_pgfix.rpt] } _m; lq "$n special connectivity: $_m" }
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_pgfix.rpt]
set n [llength [dbGet -e top.markers]]
lq "after pgfix: verify_drc = $n"
saveDesign [pnr_ckpt 05_legal_pgfix.enc]
lq "LEGAL FINAL verify_drc = $n (pgfix)"
close $fh
exit 0
