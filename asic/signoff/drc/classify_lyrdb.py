#!/usr/bin/env python3
"""Classify a KLayout DRC report (.lyrdb) by location against the SRAM macro
ring of the cache floorplans (fp_iter5..fp_iter17 geometry: 4 macros per side,
MW 376.48 x MH 446.235, GAP 40, rows centred on the die).

    classify_lyrdb.py <drc.lyrdb> --die 2900 --edge 40 [--tol 1.0]

Prints: total items, items inside macro footprints (vendor GDS, foundry-
waived bitcell patterns), items outside, and the outside items per rule
category, split into routing layers (m1..m5/via*) and std-cell layers
(li/ct/poly/diff...). Same method as the 2026-09-02 iter14 verdict
(drc.md "KLAYOUT VERDICT"), which lived in a session scratchpad.
"""
import argparse, re, sys, collections
p = argparse.ArgumentParser()
p.add_argument('lyrdb'); p.add_argument('--die', type=float, required=True)
p.add_argument('--edge', type=float, required=True); p.add_argument('--tol', type=float, default=1.0)
p.add_argument('--gap', type=float, default=40.0)
a = p.parse_args()
MW, MH = 376.48, 446.235
row = 4*MW + 3*a.gap; x0 = (a.die - row)/2.0
boxes = []
for b in range(4):
    s = x0 + b*(MW + a.gap)
    boxes.append((s, a.edge, s+MW, a.edge+MH))                      # bottom
    boxes.append((s, a.die-a.edge-MH, s+MW, a.die-a.edge))          # top
    boxes.append((a.edge, s, a.edge+MH, s+MW))                      # left
    boxes.append((a.die-a.edge-MH, s, a.die-a.edge, s+MW))          # right
t = a.tol
def inside(x, y):
    return any(x1-t <= x <= x2+t and y1-t <= y <= y2+t for x1, y1, x2, y2 in boxes)
num = re.compile(r'-?\d+(?:\.\d+)?')
cat_re = re.compile(r"<category>'?([^'<]+)'?</category>")
item_re = re.compile(r'<item>(.*?)</item>', re.S)
val_re = re.compile(r'<value>(.*?)</value>', re.S)
txt = open(a.lyrdb, encoding='utf-8', errors='replace').read()
tot = ins = out = 0
outc = collections.Counter(); inc = collections.Counter(); nogeo = 0
for m in item_re.finditer(txt):
    body = m.group(1); tot += 1
    c = cat_re.search(body); cat = c.group(1) if c else '?'
    v = val_re.search(body)
    nums = num.findall(v.group(1)) if v else []
    if len(nums) < 2: nogeo += 1; continue
    xs = [float(n) for n in nums[0::2]]; ys = [float(n) for n in nums[1::2]]
    cx, cy = sum(xs)/len(xs), sum(ys)/len(ys)
    if inside(cx, cy): ins += 1; inc[cat] += 1
    else: out += 1; outc[cat] += 1
routing = lambda k: bool(re.match(r'(m[1-5]|via[1-4]?|via)\b', k))
print(f"items total {tot}  inside-macro {ins}  outside {out}  no-geometry {nogeo}")
ro = {k: v for k, v in outc.items() if routing(k)}; so = {k: v for k, v in outc.items() if not routing(k)}
print(f"outside on routing layers: {sum(ro.values())}  -> " + ', '.join(f'{k} {v}' for k, v in sorted(ro.items(), key=lambda kv: -kv[1])))
print(f"outside on std-cell layers: {sum(so.values())}  -> " + ', '.join(f'{k} {v}' for k, v in sorted(so.items(), key=lambda kv: -kv[1])[:12]))
print("inside-macro top categories: " + ', '.join(f'{k} {v}' for k, v in inc.most_common(6)))
