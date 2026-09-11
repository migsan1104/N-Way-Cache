# li1 PG ECO (2026-09-04): remove every li1 special wire and every li1<->met1
# special via that sroute created, then re-verify PG connectivity and save a
# NEW checkpoint. Why: the SRAM LEF has no li1 OBS, so sroute bridged the
# met1 rails across the macro bodies on li1 (iter16b: 368/370 li1 sWires
# inside macro footprints, 202 longer than 100 um) on top of the macros' own
# li1 - shorts that verify_drc cannot see and that the KLayout in-macro
# waiver hid (DRC.md "li1 under the macros"). The met1 rails keep their
# met1..met4 stacked vias to the stripes/ring, so nothing else changes.
#
#   ASIC_ECO_SRC  checkpoint to load   (default 06_final.enc)
#   ASIC_ECO_DST  checkpoint to write  (default 07_li1fix.enc)
#   ASIC_PNR_RUN_STAMP must name the run (innovus_config.tcl)
set _here [file normalize [file dirname [info script]]]
if {![info exists PNR_RUN_DIR]} { source [file join $_here innovus_config.tcl] }
set src [config_env ASIC_ECO_SRC 06_final.enc]
set dst [config_env ASIC_ECO_DST 07_li1fix.enc]
if {[dbGet -e top] eq ""} { pnr_restore_stage $src }

set w0 [llength [dbGet -p2 top.nets.sWires.layer.name li1 -e]]
set v0 [llength [dbGet -p2 top.nets.sVias.via.name L1M1* -e]]
pnr_note "li1 ECO: before - li1 sWires $w0, L1M1 sVias $v0"
foreach w [dbGet -p2 top.nets.sWires.layer.name li1 -e] { dbDeleteObj $w }
foreach v [dbGet -p2 top.nets.sVias.via.name L1M1* -e]  { dbDeleteObj $v }
set w1 [llength [dbGet -p2 top.nets.sWires.layer.name li1 -e]]
set v1 [llength [dbGet -p2 top.nets.sVias.via.name L1M1* -e]]
pnr_note "li1 ECO: after  - li1 sWires $w1, L1M1 sVias $v1"
if {$w1 > 0 || $v1 > 0} { pnr_fail "li1 ECO: deletion incomplete ($w1 wires, $v1 vias left)" }

verifyConnectivity -type special -noAntenna -error 100000 -warning 100000 \
    > [pnr_rpt li1_eco connectivity_after.rpt]
verify_drc -limit 100000 -report [pnr_rpt li1_eco drc_after.rpt]
saveDesign [pnr_ckpt $dst]
pnr_note "li1 ECO complete: $src -> $dst; reports in reports/li1_eco/"
exit
