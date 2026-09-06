# legalize_pgfix2.tcl - 2026-09-06 iter19b: delete the dangling VSS M3M4 via at
# (921.1,2860.135) by object (editPowerVia -delete_vias left it, as on 16b;
# fix3 there used dbDeleteObj). Saves 05_legal_pgfix2.enc.
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_LEGALIZE_SRC 05_legal_pgfix.enc]
pnr_restore_stage $_src
set fh [open [pnr_rpt legalize pgfix2.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "LEGALQ $msg" }
set _box [config_env ASIC_LEGALIZE_VIA_BOX {920.6 2859.6 921.6 2860.7}]
# editSelect -area -type Special selected nothing here (2026-09-06); dbQuery
# with the four-type list sees the via as objType sViaInst.
set _d 0
lassign $_box bx1 by1 bx2 by2
foreach o [dbQuery -area $_box -objType {sWire sVia wire via}] {
    catch {
        set ot [dbGet $o.objType]
        lq "found objType=$ot net=[dbGet -e $o.net.name] via=[dbGet -e $o.via.name] pt=[dbGet -e $o.pt] box=[dbGet -e $o.box]"
        if {[string match *Via* $ot]} {
            lassign [lindex [dbGet $o.pt] 0] px py
            if {$px >= $bx1 && $px <= $bx2 && $py >= $by1 && $py <= $by2} { lq "DELETE $ot [dbGet -e $o.via.name] at $px $py"; dbDeleteObj $o; incr _d }
        }
    }
}
lq "vias deleted: $_d"
clearDrc
verify_drc -limit 100000 -report [pnr_rpt legalize drc_after_pgfix2.rpt]
set n [llength [dbGet -e top.markers]]
lq "after pgfix2: verify_drc = $n"
saveDesign [pnr_ckpt 05_legal_pgfix2.enc]
lq "LEGAL FINAL verify_drc = $n (pgfix2)"
close $fh
exit 0
