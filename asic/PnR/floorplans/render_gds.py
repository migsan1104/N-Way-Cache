#!/usr/bin/env python3
"""Render a GDSII to PNG with a micron coordinate frame.

KLayout is not installed on this server, so this is the project's GDS viewer.
Needs gdstk (user-installed for /apps/anaconda/bin/python3.9, 2026-09-01):

    /apps/anaconda/bin/python3.9 render_gds.py <in.gds> <out.png> [--title T]

Draws the TOP cell's own polygons - after `streamOut -merge` that is the
routing - coloured per metal layer, plus every placed cell/macro reference as
an outline so the floorplan reads. Axes are microns, with a scale bar and an
area caption, matching annotate_layout.py so GDS and Innovus captures can sit
side by side.
"""
import sys, time, argparse
import gdstk
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.patches import Rectangle

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("out")
ap.add_argument("--title", default=None)
ap.add_argument("--note", default="")
ap.add_argument("--max-polys", type=int, default=400000,
                help="per-layer polygon cap; above this the layer is subsampled")
a = ap.parse_args()

# sky130 GDS layer numbers -> (name, colour, draw order)
LAYERS = {67: ("li1", "#8b0000"), 68: ("met1", "#1f77b4"), 69: ("met2", "#2ca02c"),
          70: ("met3", "#ff7f0e"), 71: ("met4", "#d62728"), 72: ("met5", "#9467bd")}

t0 = time.time()
lib = gdstk.read_gds(a.src)
top = lib.top_level()[0]
print(f"read {a.src} in {time.time()-t0:.0f}s; top cell = {top.name}")

bb = top.bounding_box()
(x0, y0), (x1, y1) = bb
W, H = x1 - x0, y1 - y0
print(f"bbox {W:.1f} x {H:.1f} um")

fig, ax = plt.subplots(figsize=(11, 11))

# cell placements (macros + std cells) as light outlines
refs = top.references
print(f"{len(refs)} placed references")
mac = []
for r in refs:
    rb = r.bounding_box()
    if rb is None: continue
    (a0, b0), (a1, b1) = rb
    if (a1 - a0) > 100 and (b1 - b0) > 100:      # macros only; std cells are tiny
        mac.append(Rectangle((a0 - x0, b0 - y0), a1 - a0, b1 - b0))
if mac:
    ax.add_collection(PolyCollection([m.get_verts() for m in mac], facecolors="#dddddd",
                                     edgecolors="#444444", linewidths=0.8, zorder=1))
    print(f"{len(mac)} macro-sized references drawn")

# routing polygons, per layer
polys = top.polygons
print(f"{len(polys)} top-level polygons")
by_layer = {}
for p in polys:
    by_layer.setdefault(p.layer, []).append(p)
for lay in sorted(by_layer):
    name, col = LAYERS.get(lay, (f"layer{lay}", "#999999"))
    plist = by_layer[lay]
    step = max(1, len(plist) // a.max_polys)
    verts = [p.points - [x0, y0] for p in plist[::step]]
    ax.add_collection(PolyCollection(verts, facecolors=col, edgecolors="none",
                                     alpha=0.75, zorder=2))
    print(f"  {name:5s} (layer {lay}): {len(plist)} polys, drew {len(verts)}")

ax.set_xlim(-W * 0.04, W * 1.04); ax.set_ylim(-H * 0.04, H * 1.04)
ax.set_aspect("equal")
step_um = 500 if W > 1500 else 200
ticks = [t for t in range(0, int(W) + 1, step_um)]
ax.set_xticks(ticks); ax.set_yticks([t for t in range(0, int(H) + 1, step_um)])
ax.set_xlabel("x (µm)", fontsize=9); ax.set_ylabel("y (µm)", fontsize=9)
ax.tick_params(labelsize=8)
ax.grid(True, color="#888", alpha=0.25, lw=0.6, ls=":")
ax.add_patch(Rectangle((0, 0), W, H, fill=False, ec="#00bcd4", lw=1.4, zorder=3))
ax.plot([0, step_um], [-H * 0.025, -H * 0.025], color="black", lw=3.5, solid_capstyle="butt")
ax.text(step_um / 2, -H * 0.019, f"{step_um} µm", ha="center", va="bottom",
        fontsize=9, fontweight="bold")
ax.text(W, -H * 0.018, f"GDSII  ·  {W:.0f} × {H:.0f} µm = {W*H/1e6:.2f} mm²",
        ha="right", va="top", fontsize=8.5, color="#333")
handles = [plt.Line2D([], [], color=LAYERS[l][1], lw=6, label=LAYERS[l][0])
           for l in sorted(by_layer) if l in LAYERS]
if handles: ax.legend(handles=handles, loc="upper right", fontsize=8, framealpha=0.9)
if a.title: ax.set_title(a.title, fontsize=12, fontweight="bold", loc="left")
if a.note: ax.text(W / 2, -H * 0.055, a.note, ha="center", va="top", fontsize=8, color="#555")

fig.savefig(a.out, dpi=150, bbox_inches="tight")
print("wrote", a.out, f"({time.time()-t0:.0f}s total)")
