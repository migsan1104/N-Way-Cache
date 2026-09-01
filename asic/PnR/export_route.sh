#!/usr/bin/env bash
set -uo pipefail
# Export a GATED route to GDS/DEF/SDF/netlist.
#
#   ./export_route.sh <run_stamp> [netlist.v]
#
# Stage 06 normally restores 05_route_opt.enc - the post-route-OPTIMISED
# database. A run that failed the stage-05 DRC gate never wrote one (the gate
# stops before post-route opt, deliberately: that opt is measured to multiply
# a DRC-heavy route's violations, x2.7 and x5.5). This script restores the
# ROUTED database (05_route.enc) by hand and then sources stage 06 unchanged -
# 06's own restore is skipped because a design is already open.
#
# The GDS carries whatever DRC violations the route had. That is the point:
# it exercises export + gives Magic DRC / netgen LVS a real target without
# waiting for a clean route.
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STAMP=${1:?usage: export_route.sh <run_stamp> [netlist.v]}
RUN=$HERE/innovus/runs/$STAMP
[[ -d $RUN/checkpoints/05_route.enc.dat ]] || { echo "no 05_route.enc in $RUN" >&2; exit 1; }
S=$HERE/innovus/scripts
cat > "$RUN/export_route.tcl" <<EOF
source $S/innovus_config.tcl
pnr_restore_stage 05_route.enc

# ASIC_QRC_TECH on a RESTORED design (2026-08-31): restoreDesign brings back the
# MMMC setup that was baked into the checkpoint at stage 00 - mmmc.tcl does NOT
# re-run, so exporting an old checkpoint with ASIC_QRC_TECH newly set has no
# effect and extraction still fails with IMPEXT-3491. The RC corners have to be
# updated in-session instead. (Same reason stage 06 alone cannot switch corners.)
set _qrc [config_env ASIC_QRC_TECH {}]
if {\$_qrc ne ""} {
    if {![file readable \$_qrc]} { error "ASIC_QRC_TECH not readable: \$_qrc" }
    foreach _c {rc_slow rc_fast} {
        if {[catch {update_rc_corner -name \$_c -qx_tech_file \$_qrc} _m]} {
            puts "WARN: update_rc_corner \$_c failed: \$_m"
        } else {
            puts "INFO: rc corner \$_c now extracts through Quantus (\$_qrc)"
        }
    }
}
source $S/06_export.tcl
exit
EOF
source /apps/settings
source "$HERE/innovus/env.sh"
[[ $# -ge 2 ]] && export ASIC_NETLIST=$2
export ASIC_PNR_RUN_STAMP=$STAMP
cd "$RUN"
innovus -no_gui -files "$RUN/export_route.tcl" -log logs/export_route
echo "EXIT=$? $(date)"
ls -la "$RUN/outputs/"
