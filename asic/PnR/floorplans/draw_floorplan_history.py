#!/usr/bin/env python3
"""One picture of every macro floorplan the P&R campaign tried, to scale.

    python3 draw_floorplan_history.py        # writes floorplan_history.png here

Six panels, in the order they were tried (2026-08-25 .. 09-11). Geometry is
taken from the fp_*.tcl files (v3-A: fp_v3a.tcl; ring: fp_iter16.tcl; two
columns: fp_iter23_cols.tcl; quad: fp_iter23_quad.tcl with ASIC_FP_WAY_CHANNEL
260 = iter26b) and from draw_floorplans.py for v1/v2. The short black bar on
each macro is the LEF top edge - the side that carries the read port (dout1) -
so the picture shows which way every macro reads. Outcomes are the route-stage
DRC counts from DRC.md / FLOORPLAN.md.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

HERE = os.path.dirname(os.path.abspath(__file__))
MW, MH = 376.48, 446.235                      # sram_1rw1r_32_256_8 footprint, R0
WAY_COL = {0: "#4c78a8", 1: "#f58518", 2: "#54a24b", 3: "#e45756"}
LIM = 2960                                    # common axis extent: every die to the same scale


def macro(ax, x, y, way, orient="R0", label=None):
    w, h = (MW, MH) if orient in ("R0", "R180", "MX", "MY") else (MH, MW)
    ax.add_patch(Rectangle((x, y), w, h, fc=WAY_COL[way], ec="black", lw=0.6, alpha=0.85))
    t = 26
    if orient in ("R0", "MY"):
        bar = Rectangle((x, y + h - t), w, t)
    elif orient in ("R180", "MX"):
        bar = Rectangle((x, y), w, t)
    elif orient == "R90":
        bar = Rectangle((x, y), t, h)
    else:
        bar = Rectangle((x + w - t, y), t, h)
    bar.set(fc="black", ec="none")
    ax.add_patch(bar)
    ax.text(x + w / 2, y + h / 2, label or f"w{way}", ha="center", va="center",
            fontsize=6.5, color="white", fontweight="bold")


def region(ax, x0, y0, x1, y1, color, label, ls="--", hatch=None, fs=7):
    ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fc=color, ec=color,
                           lw=1.0, ls=ls, alpha=0.18, hatch=hatch))
    ax.text((x0 + x1) / 2, (y0 + y1) / 2, label, ha="center", va="center",
            fontsize=fs, color=color if color != "#222" else "#111", fontweight="bold")


def panel(ax, n, title, die, verdict, vcolor):
    ax.add_patch(Rectangle((0, 0), *die, fc="#f4f4f4", ec="black", lw=1))
    ax.add_patch(Rectangle((16, 16), die[0] - 32, die[1] - 32, fc="none", ec="gray", lw=0.5, ls=":"))
    ax.set_xlim(-40, LIM); ax.set_ylim(-40, LIM)
    ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
    for s in ax.spines.values():
        s.set_visible(False)
    ax.set_title(f"{n}. {title}", fontsize=10.5, loc="left", fontweight="bold")
    ax.text(0, -70, verdict, fontsize=7.6, va="top", color=vcolor, linespacing=1.35)
    ax.text(die[0], die[1] + 25, f"die {die[0]/1000:.2f} x {die[1]/1000:.2f} mm",
            fontsize=7, ha="right", va="bottom", color="#444")


fig, axes = plt.subplots(2, 3, figsize=(16.5, 12.4))
fig.subplots_adjust(left=0.02, right=0.98, top=0.87, bottom=0.06, wspace=0.08, hspace=0.36)
A = axes.ravel()

# ------------------------------------------------------------------ 1. v1
D1 = (2574.6, 2570.4)
ax = A[0]
panel(ax, 1, "v1: two macro columns per side, logic in the middle", D1,
      "run 1, 2026-08-25: 47.7k route DRC (met4 capacity + li1). The inner column\n"
      "blocks the outer column's read bus: 14-repeater detours, density 51 -> 78 %.\n"
      "Discarded (post-mortem in Innovus.md).", "#8b1a1a")
for i, y in enumerate([120, 640, 1160, 1680]):
    macro(ax, 40, y, 1, "R0", f"w1b{i}")
    macro(ax, 460, y, 0, "R0", f"w0b{i}")
    macro(ax, D1[0] - 40 - MW, y, 3, "R0", f"w3b{i}")
    macro(ax, D1[0] - 460 - MW, y, 2, "R0", f"w2b{i}")
region(ax, 880, 40, 1700, 2530, "#555", "all way logic\n+ hub", ls="-")

# ------------------------------------------------------------------ 2. v2
ax = A[1]
panel(ax, 2, "v2: central macro block, logic on the perimeter", D1,
      "iter2: 331k route DRC (1.8M after post-route opt). Every tag-read register\n"
      "sits on the far side of a 16-macro block from the compare logic: the critical\n"
      "paths are half-die wires. Dead.", "#8b1a1a")
cols = {1: 474, 0: 891, 2: 1307, 3: 1724}
rows = {3: 333, 0: 819, 2: 1305, 1: 1791}
for way, x in cols.items():
    for bank, y in rows.items():
        macro(ax, x, y, way, "R0", f"w{way}b{bank}")
region(ax, 18, 16, 456, 2353, "#555", "logic", ls="-")
region(ax, 2118, 16, 2556, 2353, "#555", "logic", ls="-")
ax.plot(1381, 1804, "k*", ms=11, zorder=6)
ax.text(1381, 2400, "S1 compare hub\n(inside the block)", fontsize=7, ha="center")

# ------------------------------------------------------------------ 3. v3-A quadrant tiles
ax = A[2]
panel(ax, 3, "v3-A: quadrant tiles, read ports face a channel", D1,
      "iter3 / iter6: 640k DRC markers, 79 % density, centre-south jam; iter6's\n"
      "decongestion (regions pulled off the centrelines) trended worse and was killed.\n"
      "Each way's 2x2 tile reads into its own 120 um channel - right idea, wrong hub.", "#8b1a1a")
EDGE, GAPX, CHAN = 60.0, 40.0, 120.0
for w, (axr, ayr) in {0: ("low", "low"), 1: ("low", "high"), 2: ("high", "low"), 3: ("high", "high")}.items():
    x0 = EDGE if axr == "low" else D1[0] - EDGE - 2 * MW - GAPX
    ylow = EDGE if ayr == "low" else D1[1] - EDGE - 2 * MH - CHAN
    b = 0
    for yy, oo in [(ylow, "R0"), (ylow + MH + CHAN, "R180")]:
        for cc in range(2):
            macro(ax, x0 + cc * (MW + GAPX), yy, w, oo, f"w{w}b{b}")
            b += 1
    rx0 = EDGE + 2 * MW + GAPX + 30 if axr == "low" else D1[0] / 2 + 20
    rx1 = D1[0] / 2 - 20 if axr == "low" else D1[0] - (EDGE + 2 * MW + GAPX + 30)
    ry0 = 40.0 if ayr == "low" else D1[1] / 2 + 20
    ry1 = D1[1] / 2 - 20 if ayr == "low" else D1[1] - 40
    region(ax, rx0, ry0, rx1, ry1, WAY_COL[w], f"way{w}\nregion")
region(ax, D1[0] / 2 - 420, D1[1] / 2 - 420, D1[0] / 2 + 420, D1[1] / 2 + 420, "#222", "hub 840", ls="-")

# ------------------------------------------------------------------ 4. ring
D4 = (2900.0, 2900.0)
ax = A[3]
panel(ax, 4, "v3-B ring: one way per edge, read ports face inward", D4,
      "iter4 50k -> iter5 133k -> iter7 (40 % hub blockage) 2.9k -> iter16b / iter19b\n"
      "route DRC 0, antenna 0: first package through DRC, LVS, IR, EM and GLS.\n"
      "Honest Tempus: 110 MHz - the hub reaches three ways over 2.2-2.8 mm of wire.", "#7a5c00")
E4, GAP, HALO = 40.0, 40.0, 8.0
row_len = 4 * MW + 3 * GAP
x0 = (D4[0] - row_len) / 2
for b in range(4):
    p = x0 + b * (MW + GAP)
    macro(ax, p, E4, 0, "R0", f"w0b{b}")
    macro(ax, p, D4[1] - E4 - MH, 1, "R180", f"w1b{b}")
    macro(ax, E4, p, 2, "R270", f"w2b{b}")
    macro(ax, D4[0] - E4 - MH, p, 3, "R90", f"w3b{b}")
inner = E4 + MH + HALO + 6
D = 380.0
lo, hi = inner, D4[0] - inner
region(ax, lo, lo, hi, lo + D, WAY_COL[0], "way0 wedge")
region(ax, lo, hi - D, hi, hi, WAY_COL[1], "way1 wedge")
region(ax, lo, lo + D, lo + D, hi - D, WAY_COL[2], "way2\nwedge")
region(ax, hi - D, lo + D, hi, hi - D, WAY_COL[3], "way3\nwedge")
h0, h1 = lo + D, hi - D
region(ax, h0, h0, h1, h1, "#222", "hub\n40 % place blockage", ls="-", hatch="xx", fs=8)
ax.annotate("", xy=(2500, 1450), xytext=(400, 1450),
            arrowprops=dict(arrowstyle="<->", color="#8b1a1a", lw=1.2))
ax.text(1450, 1300, "refill bus: 2.2-2.8 mm", ha="center", fontsize=7, color="#8b1a1a")

# ------------------------------------------------------------------ 5. two columns
ax = A[4]
panel(ax, 5, "two columns (iter23 cols): hub in the centre channel", D4,
      "2026-09-07 screen: does not fit at 2900 um. The array registers pull into the\n"
      "160 um slot beside the pins; 13-18k cells unplaceable (78 % vs the 55 % cap).\n"
      "Killed at legalization, twice.", "#8b1a1a")
CH, STRIP = 160.0, 130.0
BW = 2 * MH + CH
WH = 2 * MW + GAP
BH = 2 * WH + GAP
xL, xR = E4, D4[0] - E4 - BW
yB = (D4[1] - BH) / 2
yT = yB + WH + GAP
def way2x2(w, bx, by):
    xl, xr = bx, bx + MH + CH
    macro(ax, xl, by, w, "R270", f"w{w}b0")
    macro(ax, xl, by + MW + GAP, w, "R270", f"w{w}b1")
    macro(ax, xr, by, w, "R90", f"w{w}b2")
    macro(ax, xr, by + MW + GAP, w, "R90", f"w{w}b3")
way2x2(0, xL, yB); way2x2(2, xL, yT); way2x2(3, xR, yB); way2x2(1, xR, yT)
region(ax, xL + BW + STRIP, 16, xR - STRIP, D4[1] - 16, "#222", "hub\nchannel", ls="-")
for w, (bx, by) in {0: (xL, yB), 2: (xL, yT), 3: (xR, yB), 1: (xR, yT)}.items():
    ax.text(bx + MH + CH / 2, by + WH / 2, "160 um\nslot", ha="center", va="center", fontsize=6, color="#8b1a1a")

# ------------------------------------------------------------------ 6. quad (iter26b)
ax = A[5]
panel(ax, 6, "quad (iter23q -> iter26b): one way per quadrant", D4,
      "SIGNED OFF 2026-09-11: 188.7 MHz (5.3 ns) in Tempus SI, DRC/LVS/IR/EM clean, GLS\n"
      "PASS. Hub-to-array reach ~1 mm (ring: 2.6 mm); channel widened 160 -> 260 um\n"
      "(route DRC 5,932 -> 3,089 -> 5, legalized to 0). Placement WNS -2.1 vs ring -3.4.", "#1c6b2c")
CH, STRIP = 260.0, 260.0
BW = 2 * MH + CH
BH = 2 * MW + GAP
xL, xR = E4, D4[0] - E4 - BW
yB, yT = E4, D4[1] - E4 - BH
def block(w, bx, by):
    xl, xr = bx, bx + MH + CH
    macro(ax, xl, by, w, "R270", f"w{w}b0")
    macro(ax, xl, by + MW + GAP, w, "R270", f"w{w}b1")
    macro(ax, xr, by, w, "R90", f"w{w}b2")
    macro(ax, xr, by + MW + GAP, w, "R90", f"w{w}b3")
block(0, xL, yB); block(3, xR, yB); block(2, xL, yT); block(1, xR, yT)
region(ax, xL, yB, xL + BW + STRIP, yB + BH + STRIP, WAY_COL[0], "", ls="--")
region(ax, xR - STRIP, yB, xR + BW, yB + BH + STRIP, WAY_COL[3], "", ls="--")
region(ax, xL, yT - STRIP, xL + BW + STRIP, yT + BH, WAY_COL[2], "", ls="--")
region(ax, xR - STRIP, yT - STRIP, xR + BW, yT + BH, WAY_COL[1], "", ls="--")
for w, (bx, by) in {0: (xL, yB), 3: (xR, yB), 2: (xL, yT), 1: (xR, yT)}.items():
    ax.text(bx + MH + CH / 2, by + BH / 2, f"way{w}\ncells", ha="center", va="center", fontsize=6.5,
            color=WAY_COL[w], fontweight="bold")
region(ax, 600, yB + BH + STRIP, D4[0] - 600, yT - STRIP, "#222",
       "hub band: compare / select, MSHRs,\nresponse unit, 40 % place blockage", ls="-", hatch="xx", fs=7.5)
ax.plot(16, 1432, "k>", ms=7); ax.text(60, 1432, "clk pin", fontsize=6.5, va="center")

fig.suptitle("Floorplan history: six placements of the same 16 SRAM macros and ~145k standard cells "
             "(SKY130, 16 KB 4-way cache)", fontsize=14, fontweight="bold", x=0.02, ha="left", y=0.985)
fig.text(0.02, 0.925, "Coloured boxes = SRAM macros by way; black bar = the macro edge carrying the read port (dout1); "
         "tinted areas = soft placement regions;\nhatched = the shared-logic hub with its partial placement blockage. "
         "All six panels are drawn to the same scale. Verdicts: route-stage DRC from DRC.md / FLOORPLAN.md.",
         fontsize=9.5, color="#444")
out = os.path.join(HERE, "floorplan_history.png")
fig.savefig(out, dpi=150)
print("wrote", out)
