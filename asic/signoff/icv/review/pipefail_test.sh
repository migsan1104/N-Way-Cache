set -euo pipefail
cmd() { echo "License denied!"; exit 67; }
cmd 2>&1 | tee pf_stdout.log
rc=${PIPESTATUS[0]}
echo "# icv exit code: $rc"
if grep -q "License denied" pf_stdout.log; then echo "# LICENSE DENIED guard reached"; fi
exit "$rc"
