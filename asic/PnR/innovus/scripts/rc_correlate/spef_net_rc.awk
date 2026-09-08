# Per-net total R (sum of *RES entries) and total ground C (sum of *CAP entries with 2 fields) from a SPEF.
# Handles *NAME_MAP: names appear as *123; we keep them as-is (both SPEFs from the same DB share the map only if
# written by the same tool, so the join is done on the resolved name via the map when present).
/^\*NAME_MAP/{inmap=1; next} /^\*PORTS/{inmap=0} inmap && /^\*[0-9]+ /{ map[$1]=$2; next }
/^\*D_NET/{ net=$2; if (net in map) net=map[net]; sec=""; next }
/^\*RES/{sec="R"; next} /^\*CAP/{sec="C"; next} /^\*CONN/{sec=""; next}
/^\*END/{ if(net!=""){ printf "%s %.4f %.6f\n", net, R[net]+0, C[net]+0 }; net=""; sec=""; next }
sec=="R" && NF>=4 { R[net]+=$4 }
sec=="C" && NF==3 { C[net]+=$3 }
