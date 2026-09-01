#!/usr/bin/env python3
"""compare.py expected_lef.csv native.spef qrc.spef

Per test net: total capacitance from the LEF model (area*Ca + perim*Ce),
from Innovus native extraction, and from Quantus; plus the wire resistance
Quantus reports vs Rsq*L/W. Ratios are what the README's validation bar
(+-15 % cap on plates, exact R) is judged on.
"""
import re
import sys


def spef_totals(path):
    """{net: (total_cap_fF, total_res_ohm)} from a SPEF."""
    unit_c = 1.0  # multiplier to fF
    unit_r = 1.0
    caps, ress = {}, {}
    names = {}   # *NAME_MAP index -> net name
    net = None
    section = None
    with open(path) as f:
        for line in f:
            t = line.split()
            if not t:
                continue
            if t[0] == "*NAME_MAP":
                section = "*NAME_MAP"
            elif section == "*NAME_MAP" and t[0].startswith("*") and len(t) == 2 and t[0][1:].isdigit():
                names[t[0]] = t[1]
            elif t[0] == "*C_UNIT":
                unit_c = float(t[1]) * {"FF": 1.0, "PF": 1000.0}[t[2].upper()]
            elif t[0] == "*R_UNIT":
                unit_r = float(t[1]) * {"OHM": 1.0, "KOHM": 1000.0}[t[2].upper()]
            elif t[0] == "*D_NET":
                net = names.get(t[1], t[1])
                caps[net] = float(t[2]) * unit_c
                ress[net] = 0.0
                section = None
            elif t[0] in ("*CONN", "*CAP", "*RES", "*PORTS"):
                section = t[0]
            elif t[0] == "*END":
                net = None
            elif section == "*RES" and net and len(t) >= 4:
                try:
                    ress[net] += float(t[3]) * unit_r
                except ValueError:
                    pass
    return caps, ress


exp = {}
with open(sys.argv[1]) as f:
    next(f)
    for line in f:
        net, lay, area, perim, c, r = line.strip().split(",")
        exp[net] = (lay, float(c), float(r))

nat_c, nat_r = spef_totals(sys.argv[2])
qrc_c, qrc_r = spef_totals(sys.argv[3])

print("%-8s %-5s %10s %10s %10s %8s %8s   %9s %9s %8s" % (
    "net", "layer", "C_lef fF", "C_nat fF", "C_qrc fF", "qrc/lef", "qrc/nat", "R_exp", "R_qrc", "R ratio"))
for net, (lay, c_lef, r_exp) in exp.items():
    cn = nat_c.get(net, float("nan"))
    cq = qrc_c.get(net, float("nan"))
    rq = qrc_r.get(net, float("nan"))
    print("%-8s %-5s %10.3f %10.3f %10.3f %8.2f %8.2f   %9.2f %9.2f %8.2f" % (
        net, lay, c_lef, cn, cq, cq / c_lef if c_lef else float("nan"),
        cq / cn if cn else float("nan"), r_exp, rq, rq / r_exp if r_exp else float("nan")))
