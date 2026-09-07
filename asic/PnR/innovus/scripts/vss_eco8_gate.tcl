# vss_eco8_gate.tcl - 2026-09-07. Re-gate an eco8 result. eco8's gate asked
# for verifyConnectivity IMPVFC-96 = 0, but every remaining "unconnected
# terminal" is a VPB (VDD) or VNB (VSS) well/substrate pin - Innovus reports
# those for every cell because they connect by well abutment, not wiring
# (17,045 VPB / >200,000 VNB, 0 real pins). The stripes did their job: VDD
# disconnected pieces 235 -> 0. Gate here = verify_drc 0, antenna 0,
# disconnected pieces 0 on both nets, unconnected NON-well pins 0 on both.
#   ASIC_ECO_SRC  checkpoint (07_vssfix8_dirty.enc)
#   ASIC_ECO_DST  checkpoint to write when clean (07_vssfix.enc)
source /ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/scripts/innovus_config.tcl
set _src [config_env ASIC_ECO_SRC 07_vssfix8_dirty.enc]
set _dst [config_env ASIC_ECO_DST 07_vssfix.enc]
pnr_restore_stage $_src
set fh [open [pnr_rpt vss_eco8 gate.txt] w]
proc lq {msg} { global fh; puts $fh "LEGALQ $msg"; flush $fh; puts "INFO: $msg" }
proc conn {net rpt} {
    verifyConnectivity -type special -net $net -noAntenna -error 300000 -warning 50 -report $rpt
    set f [open $rpt r]; set real 0; set well 0; set t ""
    while {[gets $f l] >= 0} {
        append t $l "\n"
        if {[regexp {Pin Pin: ([^;]+);} $l -> pin]} { if {[regexp {/(VPB|VNB)$} $pin]} { incr well } else { incr real; if {$real <= 5} { lq "  real unconnected pin on $net: $pin" } } }
    }
    close $f
    set p 0; regexp {(\d+) Problem\(s\) \(IMPVFC-200\)} $t -> p
    return [list $real $well $p]
}
lassign [conn VDD [pnr_rpt vss_eco8 gate_conn_vdd.rpt]] rv wv pv
lassign [conn VSS [pnr_rpt vss_eco8 gate_conn_vss.rpt]] rs ws ps
clearDrc
verify_drc -limit 100000 -report [pnr_rpt vss_eco8 gate_drc.rpt]
set d [llength [dbGet -e top.markers]]
verifyProcessAntenna -report [pnr_rpt vss_eco8 gate_antenna.rpt]
set f [open [pnr_rpt vss_eco8 gate_antenna.rpt] r]; set t [read $f]; close $f
set a -1; if {[regexp {No Violations Found} $t]} { set a 0 } elseif {[regexp {Total number of process antenna violations:\s*(\d+)} $t -> a]} {}
lq "VSS ECO8 GATE: verify_drc = $d antenna = $a | VDD real-pin unconnected = $rv (well pins $wv) pieces = $pv | VSS real-pin unconnected = $rs (well pins $ws) pieces = $ps"
pnr_note "VSS ECO8 GATE: verify_drc = $d antenna = $a real_unconnected VDD=$rv VSS=$rs pieces VDD=$pv VSS=$ps"
if {$d == 0 && $a == 0 && $rv == 0 && $rs == 0 && $pv == 0 && $ps == 0} { saveDesign [pnr_ckpt $_dst]; close $fh; exit 0 }
close $fh; exit 2
