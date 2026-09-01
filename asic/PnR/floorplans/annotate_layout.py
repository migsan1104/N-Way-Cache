#!/usr/bin/env python3
"""Add dimension guides to an Innovus layout capture.

The raw GIFs from innovus/scripts/snap_floorplan.sh carry no scale - this
wraps one in a micron coordinate frame so a reader can size anything in the
picture: ruled axes, a scale bar, the die/core outline, and an area caption.

    python3 annotate_layout.py <in.gif> <out.png> [die_um] [--title "..."]
                              [--core-margin um] [--note "..."]

die_um defaults to 2700 (the v3-B ring die; v2/quadrant runs are 2574.6).
The design is drawn on black, so the die extent is found as the bounding box
of non-black pixels - no assumption about the tool's fit margin.
"""
import sys, argparse
import numpy as np
from PIL import Image
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("out")
ap.add_argument("die", nargs="?", type=float, default=2700.0)
ap.add_argument("--title", default=None)
ap.add_argument("--note", default="")
ap.add_argument("--core-margin", type=float, default=16.0)
a = ap.parse_args()

im = Image.open(a.src).convert("RGB")
arr = np.asarray(im)
# content = anything not near-black; the die is the tight bbox of it
mask = arr.max(axis=2) > 28
ys, xs = np.where(mask)
if len(xs) == 0:
    sys.exit("no content found in image")
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
crop = im.crop((x0, y0, x1 + 1, y1 + 1))

fig, ax = plt.subplots(figsize=(9.2, 9.2))
# image drawn in MICRON coordinates: (0,0) = die lower-left
ax.imshow(crop, extent=[0, a.die, 0, a.die], origin="upper", interpolation="nearest")

ax.set_xlim(-a.die * 0.06, a.die * 1.06)
ax.set_ylim(-a.die * 0.06, a.die * 1.06)
ax.set_aspect("equal")
step = 500 if a.die > 1500 else 200
ticks = list(np.arange(0, a.die + 1, step))
ax.set_xticks(ticks); ax.set_yticks(ticks)
ax.set_xticklabels([f"{int(t)}" for t in ticks], fontsize=8)
ax.set_yticklabels([f"{int(t)}" for t in ticks], fontsize=8)
ax.set_xlabel("x (µm)", fontsize=9); ax.set_ylabel("y (µm)", fontsize=9)
ax.grid(True, which="major", color="#888", alpha=0.25, lw=0.6, ls=":")
for s in ax.spines.values():
    s.set_color("#888")

# die + core outlines
ax.add_patch(Rectangle((0, 0), a.die, a.die, fill=False, ec="#00e5ff", lw=1.4))
m = a.core_margin
ax.add_patch(Rectangle((m, m), a.die - 2*m, a.die - 2*m, fill=False,
                       ec="#00e5ff", lw=0.8, ls="--", alpha=0.7))

# scale bar: one grid step, drawn just under the die
bar = step
ax.plot([0, bar], [-a.die*0.028, -a.die*0.028], color="black", lw=3.5, solid_capstyle="butt")
ax.text(bar/2, -a.die*0.022, f"{int(bar)} µm", ha="center", va="bottom",
        fontsize=9, fontweight="bold")

area_mm2 = (a.die / 1000.0) ** 2
cap = f"die {a.die:.0f} × {a.die:.0f} µm  =  {area_mm2:.2f} mm²   ·   core inset {m:g} µm"
ax.text(a.die, -a.die*0.020, cap, ha="right", va="top", fontsize=8.5, color="#333")
if a.note:
    ax.text(a.die/2, -a.die*0.088, a.note, ha="center", va="top",
            fontsize=8, color="#555")
if a.title:
    ax.set_title(a.title, fontsize=12, fontweight="bold", loc="left")

fig.savefig(a.out, dpi=150, bbox_inches="tight")
print("wrote", a.out)
