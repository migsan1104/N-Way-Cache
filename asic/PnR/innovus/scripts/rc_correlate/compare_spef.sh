#!/usr/bin/env bash
# compare_spef.sh <pre.spef> <ref.spef>  -> per-net R ratio (pre/ref) buckets and length-weighted totals
P=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd); W=${RC_CORR_WORK:-$P/work}; mkdir -p $W
awk -f $P/spef_net_rc.awk "$1" | LC_ALL=C sort > $W/_pre.txt
awk -f $P/spef_net_rc.awk "$2" | LC_ALL=C sort > $W/_ref.txt
LC_ALL=C join $W/_pre.txt $W/_ref.txt > $W/_joined.txt   # net Rpre Cpre Rref Cref
awk '{ n++; rp+=$2; rr+=$4; cp+=$3; cr+=$5;
       if($4>0){ r=$2/$4; if($4<20)b="ref R<20";else if($4<100)b="ref R 20-100";else if($4<500)b="ref R 100-500";else b="ref R>500";
                 cnt[b]++; sr[b]+=r; srp[b]+=$2; srr[b]+=$4 } }
     END{ printf "nets joined %d\nTOTAL R pre/ref = %.3f (pre %.0f, ref %.0f)  TOTAL C pre/ref = %.3f\n", n, rp/rr, rp, rr, cp/cr;
          for(b in cnt) printf "%-14s nets %7d  mean per-net ratio %.2f  summed ratio %.2f\n", b, cnt[b], sr[b]/cnt[b], srp[b]/srr[b] }' $W/_joined.txt
echo "== 8 largest ref-R nets: net Rpre Cpre Rref Cref"; sort -k4 -g -r $W/_joined.txt | head -8 | cut -c1-120
echo "== 8 largest pre/ref ratio among ref R>100"; awk '$4>100{printf "%.1f %s\n",$2/$4,$0}' $W/_joined.txt | sort -g -r | head -8 | cut -c1-120
