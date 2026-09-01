#!/usr/bin/env python3
"""Schematic, to-scale floorplan pictures for FLOORPLAN.md.

v2 uses the measured macro coordinates from run 1 (placement_geography.txt);
v1, v3-A and v3-B are drawn from their descriptions. The short thick bar on
each macro is its TOP edge in the LEF - the edge that carries dout1 - so the
picture shows which way every macro's read port faces.

    python3 draw_floorplans.py          # writes fp_v1.png .. fp_v3b.png here
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

DIE = (2574.6, 2570.4)
CORE = ((16.1, 16.3), (2558.5, 2554.1))
MW, MH = 376.48, 446.235          # macro size, R0
HERE = os.path.dirname(os.path.abspath(__file__))
WAY_COL = {0: "#4c78a8", 1: "#f58518", 2: "#54a24b", 3: "#e45756"}


def macro(ax, x, y, way, orient="R0", label=None):
    """Draw one macro with lower-left (x, y) in the given orientation and a
    bar on the LEF top edge (dout1)."""
    w, h = (MW, MH) if orient in ("R0", "R180", "MX", "MY") else (MH, MW)
    ax.add_patch(Rectangle((x, y), w, h, fc=WAY_COL[way], ec="black", lw=0.8, alpha=0.85))
    t = 22
    if orient in ("R0", "MY"):
        bar = Rectangle((x, y + h - t), w, t)
    elif orient in ("R180", "MX"):
        bar = Rectangle((x, y), w, t)
    elif orient == "R90":                     # top edge -> left side
        bar = Rectangle((x, y), t, h)
    else:                                     # R270: top edge -> right side
        bar = Rectangle((x + w - t, y), t, h)
    bar.set(fc="black", ec="none")
    ax.add_patch(bar)
    ax.text(x + w / 2, y + h / 2, label or f"w{way}", ha="center", va="center",
            fontsize=7, color="white", fontweight="bold")


def region(ax, x0, y0, x1, y1, color, label, ls="--"):
    ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fc=color, ec=color,
                           lw=1.2, ls=ls, alpha=0.18))
    ax.text((x0 + x1) / 2, y1 - 40, label, ha="center", va="top", fontsize=8, color=color)


def canvas(title, sub):
    fig, ax = plt.subplots(figsize=(6.4, 6.6))
    ax.add_patch(Rectangle((0, 0), *DIE, fc="#f4f4f4", ec="black", lw=1))
    (cx0, cy0), (cx1, cy1) = CORE
    ax.add_patch(Rectangle((cx0, cy0), cx1 - cx0, cy1 - cy0, fc="none", ec="gray", lw=0.6, ls=":"))
    ax.set_xlim(-60, DIE[0] + 60); ax.set_ylim(-60, DIE[1] + 60)
    ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
    ax.set_title(title, fontsize=11, loc="left")
    ax.text(0, -30, sub, fontsize=7.5, va="top", color="#444")
    for s in ax.spines.values():
        s.set_visible(False)
    return fig, ax


def save(fig, name):
    p = os.path.join(HERE, name)
    fig.savefig(p, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print("wrote", p)


# --------------------------------------------------------------------------- v2
fig, ax = canvas("v2 - central macro block, logic on the perimeter (run 1)",
                 "measured, run 1 stage 03; columns way1/way0/way2/way3, 40 um channels, all R0 "
                 "(dout1 edges all face UP); S1 compare hub centroid (1381,1804)")
cols = {1: 474, 0: 891, 2: 1307, 3: 1724}
rows = {3: 333, 0: 819, 2: 1305, 1: 1791}
for way, x in cols.items():
    for bank, y in rows.items():
        macro(ax, x, y, way, "R0", f"w{way}b{bank}")
region(ax, 18, 16, 1832, 2353, WAY_COL[0], "way0 logic bbox (1814x2336)")
region(ax, 18, 1205, 874, 1624, "#9a3fb5", "PLRU")
ax.plot(1381, 1804, "k*", ms=12); ax.text(1400, 1830, "S1 compare", fontsize=8)
for way, c in [(0, (852, 1255)), (1, (385, 2214)), (2, (2180, 673)), (3, (2208, 2111))]:
    ax.plot(*c, "o", color=WAY_COL[way], mec="black", ms=8)
    ax.annotate("", xy=(1381, 1804), xytext=c, arrowprops=dict(arrowstyle="->", color=WAY_COL[way], lw=1.2))
ax.text(30, 2500, "dots = way tag-read register centroids; arrows = the critical-path distance",
        fontsize=7)
save(fig, "fp_v2.png")

# --------------------------------------------------------------------------- v1
fig, ax = canvas("v1 - two macro columns per side, logic in the middle (discarded)",
                 "schematic from the 08-25 post-mortem: inner-column dout1 buses detour around "
                 "the outer column (14-repeater chains), density 51->78 %")
# left: ways 0,1 in two columns; right: ways 2,3. All R0 as it was run.
for i, y in enumerate([120, 640, 1160, 1680]):
    macro(ax, 40, y, 1, "R0", f"w1b{i}")
    macro(ax, 460, y, 0, "R0", f"w0b{i}")
    macro(ax, DIE[0] - 40 - MW, y, 3, "R0", f"w3b{i}")
    macro(ax, DIE[0] - 460 - MW, y, 2, "R0", f"w2b{i}")
region(ax, 880, 40, 1700, 2530, "#555", "all way logic + hub", ls="-")
ax.annotate("", xy=(900, 900), xytext=(230, 560),
            arrowprops=dict(arrowstyle="->", color="black", lw=1.4, connectionstyle="arc3,rad=-0.5"))
ax.text(120, 2380, "inner column blocks\nthe outer column's\nread bus", fontsize=7)
save(fig, "fp_v1.png")

# --------------------------------------------------------------------------- v3-A
fig, ax = canvas("v3-A - quadrant tiles: each way = 2x2 macros + its own logic (planned)",
                 "top (dout1) edges face the quadrant's inner corner via a horizontal channel; "
                 "fence per way; hub region at the centre; all die edges free for pins")
gap = 40
tiles = {1: (60, DIE[1] - 60), 0: (60, 60), 2: (DIE[0] - 60, 60), 3: (DIE[0] - 60, DIE[1] - 60)}
for way, (ax0, ay0) in tiles.items():
    sx = 1 if ax0 < DIE[0] / 2 else -1
    sy = 1 if ay0 < DIE[1] / 2 else -1
    # two columns of two; lower row faces up, upper row faces down -> channel between rows
    for ci in range(2):
        for ri in range(2):
            x = ax0 + sx * (ci * (MW + gap)) - (MW if sx < 0 else 0)
            y = ay0 + sy * (ri * (MH + gap)) - (MH if sy < 0 else 0)
            # innermost row faces outward toward the channel between rows
            if sy > 0:
                orient = "R0" if ri == 0 else "R180"
            else:
                orient = "R0" if ri == 1 else "R180"
            macro(ax, x, y, way, orient, f"w{way}")
    # fence: quadrant, with the logic area on the inner side of the macros
    fx0 = 40 if sx > 0 else DIE[0] / 2 + 440
    fx1 = DIE[0] / 2 - 440 if sx > 0 else DIE[0] - 40
    fy0 = 40 if sy > 0 else DIE[1] / 2 + 440
    fy1 = DIE[1] / 2 - 440 if sy > 0 else DIE[1] - 40
    region(ax, fx0, fy0, fx1, fy1, WAY_COL[way], f"way{way} fence")
region(ax, DIE[0] / 2 - 420, DIE[1] / 2 - 420, DIE[0] / 2 + 420, DIE[1] / 2 + 420, "#222", "hub (S1 select,\nResponse, MSHR/RS)", ls="-")
save(fig, "fp_v3a.png")

# --------------------------------------------------------------------------- v3-B
fig, ax = canvas("v3-B - true ring: one way per side, all dout1 edges face inward (planned)",
                 "bottom R0, top R180, left R270, right R90 (Innovus rotates CCW; verify vs LEF); ~1.6 mm square inside "
                 "for logic; hub at centre; corners dead; pin gaps needed at corners")
m = 60
row_x0 = (DIE[0] - (4 * MW + 3 * gap)) / 2
for i in range(4):
    x = row_x0 + i * (MW + gap)
    macro(ax, x, m, 0, "R0", f"w0b{i}")
    macro(ax, x, DIE[1] - m - MH, 1, "R180", f"w1b{i}")
    y = row_x0 + i * (MW + gap)
    macro(ax, m, y, 2, "R270", f"w2b{i}")           # vertical: w=MH,h=MW; top edge -> right (inward)
    macro(ax, DIE[0] - m - MH, y, 3, "R90", f"w3b{i}")  # top edge -> left (inward)
inner = m + MH + 30
# wedges
region(ax, inner, inner, DIE[0] - inner, inner + 380, WAY_COL[0], "way0 wedge")
region(ax, inner, DIE[1] - inner - 380, DIE[0] - inner, DIE[1] - inner, WAY_COL[1], "way1 wedge")
region(ax, inner, inner + 400, inner + 380, DIE[1] - inner - 400, WAY_COL[2], "way2\nwedge")
region(ax, DIE[0] - inner - 380, inner + 400, DIE[0] - inner, DIE[1] - inner - 400, WAY_COL[3], "way3\nwedge")
region(ax, inner + 400, inner + 400, DIE[0] - inner - 400, DIE[1] - inner - 400, "#222", "hub", ls="-")
for cx, cy in [(m, m), (DIE[0] - m - 300, m), (m, DIE[1] - m - 300), (DIE[0] - m - 300, DIE[1] - m - 300)]:
    ax.add_patch(Rectangle((cx, cy), 300, 300, fc="none", ec="gray", hatch="//", lw=0.5))
ax.text(m + 150, m + 150, "dead /\npins", ha="center", va="center", fontsize=6.5, color="gray")
save(fig, "fp_v3b.png")


# --------------------------------------------------------------------- iter5
# As-run geometry from fp_iter5.tcl (die 2700, wedge 380 -> hub 940), with the
# route-DRC 500 um bin histogram from the run's drc.rpt overlaid in red.
def canvas2(title, sub, die):
    fig, ax = plt.subplots(figsize=(6.4, 6.6))
    ax.add_patch(Rectangle((0, 0), *die, fc="#f4f4f4", ec="black", lw=1))
    ax.add_patch(Rectangle((16, 16), die[0] - 32, die[1] - 32, fc="none", ec="gray", lw=0.6, ls=":"))
    ax.set_xlim(-60, die[0] + 60); ax.set_ylim(-60, die[1] + 60)
    ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
    ax.set_title(title, fontsize=11, loc="left")
    ax.text(0, -30, sub, fontsize=7.5, va="top", color="#444")
    for s in ax.spines.values():
        s.set_visible(False)
    return fig, ax

D5 = 2700.0
EDGE5 = 40.0
row5 = 4 * MW + 3 * gap
x5 = (D5 - row5) / 2
fig, ax = canvas2("iteration 5 - ring, hub 940 um + density cap 0.62 (run, GATED)",
                  "as run 20260830_205109: postCTS -0.949 ns (campaign best) but route left 133k DRCs;\n"
                  "red squares = verify_drc 500 um spatial bins (area ~ sqrt(count), top 8 of the 100k-capped report)",
                  (D5, D5))
for b in range(4):
    p = x5 + b * (MW + gap)
    macro(ax, p, EDGE5, 0, "R0", f"w0b{b}")
    macro(ax, p, D5 - EDGE5 - MH, 1, "R180", f"w1b{b}")
    macro(ax, EDGE5, p, 2, "R270", f"w2b{b}")
    macro(ax, D5 - EDGE5 - MH, p, 3, "R90", f"w3b{b}")
lo5 = EDGE5 + MH + 8 + 6
hi5 = D5 - lo5
DP5 = 380.0
region(ax, lo5, lo5, hi5, lo5 + DP5, WAY_COL[0], "way0 wedge")
region(ax, lo5, hi5 - DP5, hi5, hi5, WAY_COL[1], "way1 wedge")
region(ax, lo5, lo5 + DP5, lo5 + DP5, hi5 - DP5, WAY_COL[2], "way2\nwedge")
region(ax, hi5 - DP5, lo5 + DP5, hi5, hi5 - DP5, WAY_COL[3], "way3\nwedge")
region(ax, lo5 + DP5, lo5 + DP5, hi5 - DP5, hi5 - DP5, "#222", "hub 940", ls="-")
BINS5 = {(1500, 1000): 24042, (1500, 1500): 22965, (1000, 1500): 16454, (1000, 1000): 13933,
         (1500, 500): 6512, (1000, 500): 3918, (500, 1000): 3036, (500, 1500): 2736}
mx5 = max(BINS5.values())
for (bx, by), n in BINS5.items():
    s = 500 * (n / mx5) ** 0.5
    ax.add_patch(Rectangle((bx + 250 - s / 2, by + 250 - s / 2), s, s,
                           fc="red", ec="darkred", alpha=0.45, lw=1.0, zorder=5))
    ax.text(bx + 250, by + 250, f"{round(n/1000)}k", ha="center", va="center",
            fontsize=7, color="white", zorder=6, fontweight="bold")
save(fig, "fp_iter5.png")

# --------------------------------------------------------------------- iter6
# As-run geometry from fp_iter6.tcl (v2-size die, quadrant tiles, regions
# pulled 120 um off both centerlines, hub guide 1040, density cap 0.62).
D6W, D6H = 2574.6, 2570.4
EDGE6, CHAN, GAPX = 60.0, 120.0, 40.0
fig, ax = canvas2("iteration 6 - quadrant tiles + decongestion (killed in place_opt)",
                  "run 20260830_233240: way regions 120 um off the centerlines (was 20), hub 1040, cap 0.62;\n"
                  "stage-03 eGR hotspot forecast 2317 -> 3482 -> 5321 (iter4 finished at 4462) - trending worse at kill",
                  (D6W, D6H))
for w, (axr, ayr) in {0: ("low", "low"), 1: ("low", "high"),
                      2: ("high", "low"), 3: ("high", "high")}.items():
    xq = EDGE6 if axr == "low" else D6W - EDGE6 - 2 * MW - GAPX
    ylow = EDGE6 if ayr == "low" else D6H - EDGE6 - 2 * MH - CHAN
    b = 0
    for yy, oo in [(ylow, "R0"), (ylow + MH + CHAN, "R180")]:
        for cc in range(2):
            macro(ax, xq + cc * (MW + GAPX), yy, w, oo, f"w{w}b{b}")
            b += 1
    rx0 = EDGE6 + 2 * MW + GAPX + 30 if axr == "low" else D6W / 2 + 120
    rx1 = D6W / 2 - 120 if axr == "low" else D6W - (EDGE6 + 2 * MW + GAPX + 30)
    ry0 = 40.0 if ayr == "low" else D6H / 2 + 120
    ry1 = D6H / 2 - 120 if ayr == "low" else D6H - 40
    region(ax, rx0, ry0, rx1, ry1, WAY_COL[w], f"way{w} region")
region(ax, D6W / 2 - 520, D6H / 2 - 520, D6W / 2 + 520, D6H / 2 + 520, "#222", "hub 1040", ls="-")
save(fig, "fp_iter6.png")

# --------------------------------------------------------------------- iter7
# Iteration 7 (G7b) = the iter5 ring with the 40% partial placement blockage
# over the hub - the change that took route DRC 133k -> 2,859.
fig, ax = canvas2("iteration 7 - ring + 40% partial place blockage over the hub (BREAKTHROUGH)",
                  "fp_iter7.tcl, run 20260831_g7b_hubblock: route DRC 2,859 (47x better than iter5),\n"
                  "hub bins clean; residue = displaced FE_OFN buffer clusters at 3 region corners (x)",
                  (D5, D5))
for b in range(4):
    p = x5 + b * (MW + gap)
    macro(ax, p, EDGE5, 0, "R0", f"w0b{b}")
    macro(ax, p, D5 - EDGE5 - MH, 1, "R180", f"w1b{b}")
    macro(ax, EDGE5, p, 2, "R270", f"w2b{b}")
    macro(ax, D5 - EDGE5 - MH, p, 3, "R90", f"w3b{b}")
region(ax, lo5, lo5, hi5, lo5 + DP5, WAY_COL[0], "way0 wedge")
region(ax, lo5, hi5 - DP5, hi5, hi5, WAY_COL[1], "way1 wedge")
region(ax, lo5, lo5 + DP5, lo5 + DP5, hi5 - DP5, WAY_COL[2], "way2\nwedge")
region(ax, hi5 - DP5, lo5 + DP5, hi5, hi5 - DP5, WAY_COL[3], "way3\nwedge")
h0, h1 = lo5 + DP5, hi5 - DP5
ax.add_patch(Rectangle((h0, h0), h1 - h0, h1 - h0, fc="#888", ec="#222",
                       hatch="xx", alpha=0.35, lw=1.4))
ax.text((h0 + h1) / 2, (h0 + h1) / 2, "hub 940\n40% place blockage\n(<=60% cell density)",
        ha="center", va="center", fontsize=8.5, fontweight="bold", color="#111")
for bx, by in [(500, 2000), (0, 2000), (1000, 500)]:
    ax.text(bx + 250, by + 250, "x", ha="center", va="center", fontsize=14,
            color="darkred", fontweight="bold")
save(fig, "fp_iter7.png")
