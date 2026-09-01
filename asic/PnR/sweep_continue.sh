#!/usr/bin/env bash
set -uo pipefail
# Wait for the placement-sweep arms to finish, rank them by SETTLED post-place
# congestion, and continue the best N through CTS + route (stages 04-05) on the
# same run stamp - no re-placement, exactly how iteration 11 continued the
# E36(b') screen. Methodology: asic/PnR/DRC.md "Methodology: the placement sweep".
#
#   ./sweep_continue.sh [N] [arms...]        # default: best 1 of B C D E
#
# Ranking key is the LAST "Local HotSpot Analysis" reading before ccopt_design
# (the settled value) - never a mid-placement dip; see the 2026-08-31 correction
# in DRC.md. Ties break on horizontal overflow.
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUNS=$HERE/innovus/runs
N=${1:-1}; shift 2>/dev/null || true
ARMS=${*:-B C D E}

echo "[$(date +%H:%M)] waiting for arms: $ARMS"
while :; do
    pending=0
    for A in $ARMS; do
        tmux capture-pane -pt "sweep$A" -S -40 2>/dev/null | grep -qaE "^EXIT=" || pending=1
    done
    [[ $pending -eq 0 ]] && break
    sleep 120
done
echo "[$(date +%H:%M)] all arms finished; ranking"

RANK=$(for A in $ARMS; do
    d=$RUNS/20260831_sweep${A}_e36bp_fpiter7
    [[ -d $d ]] || continue
    read -r hot ovf < <(python3 - "$d" <<'PY'
import sys, os, re
d = sys.argv[1]; ldir = os.path.join(d, "logs")
logs = sorted((os.path.join(ldir,f) for f in os.listdir(ldir)
               if re.match(r"innovus_v3[ab]\.log\d*$", f)), key=os.path.getmtime)
hot = ovf = None
for lg in logs:
    for ln in open(lg, errors="ignore"):
        if "<CMD> ccopt_design" in ln: hot = hot; break
        m = re.match(r"^Local HotSpot Analysis: normalized max congestion hotspot area = ([\d.]+)", ln)
        if m: hot = float(m.group(1))
        m = re.search(r"Overflow after Early Global Route ([\d.]+)% H", ln)
        if m: ovf = float(m.group(1))
print(f"{hot if hot else 9e9} {ovf if ovf else 99}")
PY
)
    echo "$hot $ovf $A"
done | sort -n)

echo "$RANK" | awk '{printf "  arm %s: settled hotspot %s, ovfH %s%%\n", $3, $1, $2}'

# Control gate (added 2026-08-31 after arms B/C settled WORSE than the
# control): continuing an arm that lost to the default settings spends ~4 h of
# CTS+route proving something the placement number already said. Only arms that
# BEAT the control earn a route. CONTROL_HOT is iteration 11's settled
# post-place hotspot - the same design point with default knobs.
CONTROL_HOT=${CONTROL_HOT:-7174}
echo "control (iteration 11, default knobs) = $CONTROL_HOT"

i=0
while read -r hot ovf A; do
    if awk -v h="$hot" -v c="$CONTROL_HOT" 'BEGIN{exit !(h>=c)}'; then
        echo "  arm $A ($hot) did not beat the control ($CONTROL_HOT) - not continued"
        continue
    fi
    i=$((i+1)); [[ $i -gt $N ]] && break
    STAMP=20260831_sweep${A}_e36bp_fpiter7
    echo "[$(date +%H:%M)] continuing arm $A (hotspot $hot) through CTS+route"
    S=$(mktemp /tmp/cont_${A}_XXXX.sh)
    cat > "$S" <<EOF
export ASIC_NETLIST=$HERE/../PPA/genus/assoc_4/runs/20260831_140249_e36bp_ss1v76_d1p5_tb16_sram/netlist/Cache_16384B_assoc4_sram_mapped.v
export ASIC_FLOORPLAN=$HERE/floorplans/fp_iter7.tcl
export ASIC_PNR_RUN_STAMP=$STAMP
export ASIC_PNR_FROM=04 ASIC_PNR_TO=05
$(sed -n "s/^ *\([A-Z]\)) echo \"\(.*\)\" ;;/\2/p" "$HERE/sweep_place.sh" | sed -n "$(case $A in B) echo 1;; C) echo 2;; D) echo 3;; E) echo 4;; esac)p" | sed 's/^/export /')
$HERE/run_v3.sh b
echo EXIT=\$? \$(date)
sleep infinity
EOF
    tmux new-session -d -s "cont$A" "bash $S"
done <<< "$RANK"
echo "[$(date +%H:%M)] done launching"
