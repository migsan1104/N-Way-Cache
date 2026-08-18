#!/usr/bin/env bash
set -euo pipefail

# Remove regenerable synthesis output.
#
# Usage:
#   ./clean.sh                # drop work databases and logs, keep reports+netlists
#   ./clean.sh --all          # drop the whole PPA tree
#   ./clean.sh --tool dc      # restrict to one tool
#   ./clean.sh -n             # dry run: list what would be removed
#
# Reports and netlists are the results worth keeping; work/ databases and tool
# logs are large and reproduced by re-running the flow.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PPA_ROOT="$SCRIPT_DIR/PPA"

ALL=0
DRY=0
TOOLS="genus dc"

while (( $# )); do
    case "$1" in
        --all) ALL=1 ;;
        --tool) shift; TOOLS="${1:?--tool needs a value}" ;;
        -n|--dry-run) DRY=1 ;;
        -h|--help) awk '/^#/ && NR>1 {sub(/^# ?/, ""); print; seen=1; next} seen {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "ERROR: unknown argument '$1'" >&2; exit 1 ;;
    esac
    shift
done

if [[ ! -d "$PPA_ROOT" ]]; then
    echo "Nothing to clean: $PPA_ROOT does not exist."
    exit 0
fi

targets=()
for tool in $TOOLS; do
    tool_dir="$PPA_ROOT/$tool"
    [[ -d "$tool_dir" ]] || continue
    if (( ALL )); then
        targets+=("$tool_dir")
    else
        while IFS= read -r d; do targets+=("$d"); done \
            < <(find "$tool_dir" -mindepth 2 -maxdepth 2 -type d \( -name work -o -name logs \))
    fi
done
[[ -d "$PPA_ROOT/sweep_logs" ]] && targets+=("$PPA_ROOT/sweep_logs")

if (( ${#targets[@]} == 0 )); then
    echo "Nothing to clean."
    exit 0
fi

total=$(du -sch "${targets[@]}" 2>/dev/null | tail -1 | cut -f1)
echo "Removing ${#targets[@]} director$([[ ${#targets[@]} == 1 ]] && echo y || echo ies) (${total}):"
printf '  %s\n' "${targets[@]#$SCRIPT_DIR/}"

if (( DRY )); then
    echo "(dry run: nothing removed)"
    exit 0
fi

rm -rf "${targets[@]}"
echo "Done."
