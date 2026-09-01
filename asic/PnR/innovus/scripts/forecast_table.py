#!/usr/bin/env python3
"""Congestion-forecast table across P&R runs (DRC.md companion).

For each run log, reports the eGR forecast (max hotspot + overflow H/V) at
three sampling points:
  place  = last reading before <CMD> ccopt_design   (settled stage-03 view)
  cts    = last reading between ccopt_design and <CMD> routeDesign
           (clock + post-CTS opt priced in)
  route  = last reading after routeDesign starts    (decision-grade, just
           before detail route)
Readings are the plain "Local HotSpot Analysis" lines (the "blockage
included" and "(3d)" variants are skipped so numbers stay comparable).

    python3 forecast_table.py [runs_dir]
"""
import os, re, sys

RUNS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "runs")

LABEL = [  # (substring of run dir, iteration label)
    ("160055_v3a", "3  v3-A quads"), ("160055_v3b", "4  v3-B ring"),
    ("205109_iter5", "5  ringhub"), ("233240_iter6", "6  quadfix"),
    ("g7a_clklayers", "7a clock NDR"), ("g7b_hubblock", "7  hub block"),
    ("g7d_e36b", "8  e36b netlist"), ("iter9_cornerdamp", "9  corner damp"),
    ("e36bpscreen", "11 e36bp x fp7"), ("iter10_e36bp", "10 e36bp+damp"),
    ("sweepB", "SwB cong=high"), ("sweepC", "SwC cong+gap2"),
    ("sweepD", "SwD cong+gap4"), ("sweepE", "SwE cong+gap2+d55"),
    ("iter12_e35", "12 e35 cong"), ("iter14_e35", "14 e35 armE"),
]

hot_re = re.compile(r"^Local HotSpot Analysis: normalized max congestion hotspot area = ([\d.]+)")
ovf_re = re.compile(r"(?:Overflow after Early Global Route|Early Global Route overflow of layer group \d+:) ([\d.]+)% H \+ ([\d.]+)% V")

def scan(logs):
    cts_at = route_at = None
    readings = []          # (lineno, hotspot or None, ovfH or None, ovfV)
    n = -1
    for log in logs:
      with open(log, errors="ignore") as f:
        for ln in f:
            n += 1
            if cts_at is None and "<CMD> ccopt_design" in ln: cts_at = n
            if route_at is None and "<CMD> routeDesign" in ln: route_at = n
            m = hot_re.match(ln)
            if m: readings.append((n, float(m.group(1)), None, None)); continue
            m = ovf_re.search(ln)
            if m: readings.append((n, None, float(m.group(1)), float(m.group(2))))
    def last(lo, hi):
        h = o = None
        for n, hs, oh, ov in readings:
            if lo <= n < hi:
                if hs is not None: h = hs
                if oh is not None: o = (oh, ov)
        return h, o
    big = 10**12
    return {"place": last(0, cts_at or big),
            "cts":   last(cts_at or big, route_at or big),
            "route": last(route_at or big, big)}

def fmt(h, o):
    hs = f"{h:8.0f}" if h is not None else "       -"
    os_ = f"{o[0]:5.1f}/{o[1]:4.1f}" if o else "     -    "
    return f"{hs}  {os_}"

print(f"{'iteration':<18}| {'place: hot  ovfH/V':>20} | {'cts: hot  ovfH/V':>20} | {'route: hot  ovfH/V':>20}")
print("-" * 88)
for d in sorted(os.listdir(RUNS)):
    lab = next((l for pat, l in LABEL if pat in d), None)
    if lab is None: continue
    ldir = os.path.join(RUNS, d, "logs")
    if not os.path.isdir(ldir): continue
    logs = sorted((os.path.join(ldir, f) for f in os.listdir(ldir)
                   if re.match(r"innovus_v3[ab]\.log\d*$", f)),
                  key=os.path.getmtime)
    if not logs: continue
    r = scan(logs)
    print(f"{lab:<18}| {fmt(*r['place']):>20} | {fmt(*r['cts']):>20} | {fmt(*r['route']):>20}")
