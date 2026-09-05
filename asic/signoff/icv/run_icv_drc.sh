#!/usr/bin/env bash
# run_icv_drc.sh -- run (or just print) a Synopsys IC Validator DRC on a GDS with the
# minimal sky130 BEOL runset in this directory.
#
# *** Side project. By default this only PRINTS the command; pass --run to launch.
# *** 2026-09-05: a --run ends in "License denied!" (exit 67) on this server: the
#     installed ICV T-2022.03-SP3-4 asks for ICValidator-Manager / -Manager-2020 and the
#     server only has ICValidator-Manager-Apex (needs ICV >= U-2022.12). See SIV.md 6.
#
# Usage:
#   run_icv_drc.sh [--run] <layout.gds> <topcell> [runset.rs] [run_dir] [cpus]
#
#   layout.gds  GDSII (may be gzipped; ICV auto-detects)
#   topcell     top cell name, or "*" to let ICV pick it (icv -c '*')
#   runset.rs   defaults to sky130_beol_min.rs next to this script
#   run_dir     where ICV writes <cell>.LAYOUT_ERRORS, <cell>.sum, <cell>.vue,
#               <cell>.err and run_details/; defaults to ./icv_run_<timestamp>
#   cpus        local CPUs via -host_init <n>; default 1, hard-capped at 4 (ICV_MAX_CPUS)
#               because Innovus signoff jobs share this machine. 1 Apex key = 4 CPUs.
#
# Environment: nothing is on PATH in a fresh shell. The script sources
# /apps/settings itself (SYNOPSYS_HOME, ICV_HOME, SNPSLMD_LICENSE_FILE), so it can
# be called from a bare shell:
#   bash asic/signoff/icv/run_icv_drc.sh --run out.gds Cache_16384B_assoc4_sram
#
# License note: an ICV DRC run checks out ICValidator-Manager-Apex (or -Manager /
# -Manager-2020) plus ICValidator2-GeometryEngine (icvug1.pdf ch. 2). Feature
# availability could not be verified with lmstat from this host on 2026-09-04
# (see SIV.md); the first --run is the real test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN=0
if [[ "${1:-}" == "--run" ]]; then
    RUN=1
    shift
fi

if [[ $# -lt 2 ]]; then
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi

GDS="$(readlink -f "$1")"
TOPCELL="$2"
RUNSET="$(readlink -f "${3:-$SCRIPT_DIR/sky130_beol_min.rs}")"
RUN_DIR="${4:-$PWD/icv_run_$(date +%Y%m%d_%H%M%S)}"
CPUS="${5:-1}"
ICV_MAX_CPUS="${ICV_MAX_CPUS:-4}"
if ! [[ "$CPUS" =~ ^[0-9]+$ ]] || [[ "$CPUS" -lt 1 ]]; then
    echo "error: cpus must be a positive integer (got '$CPUS')" >&2
    exit 1
fi
if [[ "$CPUS" -gt "$ICV_MAX_CPUS" ]]; then
    echo "error: cpus=$CPUS exceeds the cap ICV_MAX_CPUS=$ICV_MAX_CPUS (Innovus jobs share this host)" >&2
    exit 1
fi

if [[ ! -f "$GDS" ]]; then
    echo "error: GDS not found: $GDS" >&2
    exit 1
fi
if [[ ! -f "$RUNSET" ]]; then
    echo "error: runset not found: $RUNSET" >&2
    exit 1
fi

# -c/-i/-f override library() in the runset; -vue writes the VUE error database next
# to the LAYOUT_ERRORS file; -host_init <n> = local CPUs (this ICV has no -dp option;
# multicore licensing: one Manager key per 4 CPUs, icvug1.pdf ch. 2).
CMD=(icv -c "$TOPCELL" -i "$GDS" -f GDSII -host_init "$CPUS" -vue "$RUNSET")

echo "# run dir : $RUN_DIR"
echo "# command : cd $RUN_DIR && source /apps/settings && ${CMD[*]}"
echo "# results : $RUN_DIR/<cell>.LAYOUT_ERRORS (first line CLEAN or ERRORS), <cell>.sum, <cell>.err"

if [[ $RUN -eq 0 ]]; then
    echo "# dry run only -- pass --run as the first argument to launch ICV"
    exit 0
fi

mkdir -p "$RUN_DIR"
cd "$RUN_DIR"
# shellcheck disable=SC1091
source /apps/settings >/dev/null 2>&1 || { echo "error: cannot source /apps/settings" >&2; exit 1; }
command -v icv >/dev/null || { echo "error: icv not on PATH after sourcing /apps/settings" >&2; exit 1; }

"${CMD[@]}" 2>&1 | tee icv_stdout.log
rc=${PIPESTATUS[0]}

echo "# icv exit code: $rc"
if grep -q "License denied" icv_stdout.log 2>/dev/null; then
    echo "# LICENSE DENIED -- do not retry in a loop; see run_details/licmsg and SIV.md section 6" >&2
fi
for f in *.LAYOUT_ERRORS; do
    [[ -f "$f" ]] && { echo "# $f:"; head -n 1 "$f"; }
done
exit "$rc"
