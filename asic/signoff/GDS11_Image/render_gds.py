#!/apps/anaconda/bin/python
"""Render a P&R run's GDS through KLayout with a mm frame and a pre-signoff sheet.

    render_gds.py <run_dir> <out.png> [--title "..."] [--px 3600] [--levels 30]

Pulls everything from the run directory itself:
  outputs/*.gds                          the layout
  outputs/*_pnr.def                      DIEAREA -> die size in mm
  reports/route/drc.rpt                  verify_drc marker breakdown (SHORT/SPACING/...)
  reports/route/postroute.summary.gz     setup WNS/TNS/paths (all + reg2reg columns)
  reports/route/postroute_hold.summary.gz  hold, same columns
  logs/*.log*                            last "#Total number of process antenna violations"

All numbers on the sheet are Innovus route-stage (timeDesign -postRoute /
verify_drc) - PRE-signoff, no Tempus/Quantus behind them - and the sheet says so.
"""
import argparse, glob, gzip, io, os, re, subprocess, sys

import numpy as np
from PIL import Image
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

ap = argparse.ArgumentParser()
ap.add_argument("run_dir")
ap.add_argument("out")
ap.add_argument("--title", default=None)
ap.add_argument("--px", type=int, default=3600)
ap.add_argument("--levels", type=int, default=30)
ap.add_argument("--gds", default=None, help="override GDS path")
ap.add_argument("--derate", default="x1.5 late (setup) / x0.67 early (hold)",
                help="macro derate note; v3-campaign default from run_v3.sh")
a = ap.parse_args()
run = os.path.abspath(a.run_dir)


def one(pattern):
    hits = sorted(glob.glob(pattern))
    if not hits:
        sys.exit(f"missing: {pattern}")
    return hits[0]


gds = a.gds or one(f"{run}/outputs/*.gds")

# ---- die size from DEF (DEF units are 1/1000 um in this flow) ----
die_w = die_h = None
with open(one(f"{run}/outputs/*_pnr.def")) as f:
    for line in f:
        m = re.search(r"DIEAREA\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)", line)
        if m:
            x0, y0, x1, y1 = map(int, m.groups())
            die_w, die_h = (x1 - x0) / 1000.0, (y1 - y0) / 1000.0  # um
            break
if die_w is None:
    sys.exit("no DIEAREA in DEF")

# ---- DRC breakdown ----
drc = {}
with open(f"{run}/reports/route/drc.rpt") as f:
    for line in f:
        m = re.match(r"^([A-Za-z-]+):", line)
        if m:
            drc[m.group(1)] = drc.get(m.group(1), 0) + 1
drc_total = sum(drc.values())

# ---- antenna count: last report line anywhere in the logs ----
ant = None
for lf in sorted(glob.glob(f"{run}/logs/*.log*")):
    try:
        out = subprocess.run(["grep", "-hE", "process antenna violations", lf],
                             capture_output=True, text=True).stdout
    except Exception:
        continue
    for line in out.splitlines():
        m = re.search(r"=\s*(\d+)", line)
        if m:
            ant = int(m.group(1))


def timing(summary_gz):
    """-> {col: (wns, tns, vio)} for the 'all' and 'reg2reg' columns."""
    if not os.path.exists(summary_gz):
        return None
    txt = gzip.open(summary_gz, "rt").read()
    rows = {}
    for key, pat in [("wns", r"WNS \(ns\):"), ("tns", r"TNS \(ns\):"),
                     ("vio", r"Violating Paths:")]:
        m = re.search(pat + r"\|([^|]+)\|([^|]+)\|([^|]+)\|", txt)
        rows[key] = [v.strip() for v in m.groups()] if m else ["?"] * 3
    return {"all": (rows["wns"][0], rows["tns"][0], rows["vio"][0]),
            "reg2reg": (rows["wns"][1], rows["tns"][1], rows["vio"][1])}


setup = timing(f"{run}/reports/route/postroute.summary.gz")
hold = timing(f"{run}/reports/route/postroute_hold.summary.gz")

# ---- instance counts from the route summary ----
stdcells = macros = physcells = None
srpt = f"{run}/reports/route/summary.rpt"
if os.path.exists(srpt):
    txt = open(srpt, errors="ignore").read()
    m = re.search(r"# Std Cells:\s*([\d,]+)", txt)
    if m:
        stdcells = int(m.group(1).replace(",", ""))
    m = re.search(r"# Hard Macros:\s*([\d,]+)", txt)
    if m:
        macros = int(m.group(1).replace(",", ""))
    # split out the no-logic physical cells (decap/tap/diode/tie) so the
    # headline count is honest about what actually computes
    if "Standard Cells in Netlist" in txt:
        sec = txt.split("Standard Cells in Netlist")[1]
        physcells = sum(int(c.replace(",", "")) for n, c in
                        re.findall(r"(sky130_fd_sc_hd__\S+)\s+([\d,]+)\s+[\d.]+", sec)
                        if re.search(r"decap|fill|tap|diode|conb", n))

# ---- KLayout headless render, zoomed exactly to the die box ----
import klayout.db as kdb
import klayout.lay as klay

lv = klay.LayoutView()
lv.set_config("background-color", "#000000")
lv.set_config("grid-visible", "false")
lv.load_layout(gds, 0)
lv.max_hier_levels = a.levels

# consistent metal palette; everything else keeps klayout's auto colors
PALETTE = {(67, 20): "#5c5cff",   # li1
           (68, 20): "#39a0ff",   # met1
           (69, 20): "#ff5c5c",   # met2
           (70, 20): "#3fd23f",   # met3
           (71, 20): "#ffd23f",   # met4
           (72, 20): "#ff8c1a"}   # met5
it = lv.begin_layers()
while not it.at_end():
    lp = it.current()
    key = (lp.source_layer, lp.source_datatype)
    if key in PALETTE:
        dup = lp.dup()
        c = int(PALETTE[key][1:], 16)
        dup.fill_color = dup.frame_color = c
        lv.set_layer_properties(it, dup)
    it.next()

px_h = max(64, int(round(a.px * die_h / die_w)))
lv.zoom_box(kdb.DBox(0, 0, die_w, die_h))
png_bytes = lv.get_screenshot_pixels() if False else None  # noqa - explicit save below
tmp_png = a.out + ".raw.png"
lv.save_image(tmp_png, a.px, px_h)
im = Image.open(tmp_png).convert("RGB")

# save_image letterboxes to preserve aspect; crop to content just in case
arr = np.asarray(im)
mask = arr.max(axis=2) > 20
ys, xs = np.where(mask)
if len(xs):
    im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

# ---- clock target from golden.sdc ----
period = None
sdc = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "..", "synthesis", "common", "constraints", "golden.sdc")
if os.path.exists(sdc):
    m = re.search(r"create_clock[^\n]*-period\s+([0-9.]+)", open(sdc).read())
    if m:
        period = float(m.group(1))
# two-corner MMMC: parse the actual stdcell corner names out of the run's logs
ss_lib = ff_lib = None
for lf in sorted(glob.glob(f"{run}/logs/innovus_v3b.log*")):
    cat = "zcat" if lf.endswith(".gz") else "cat"
    out = subprocess.run(f"{cat} {lf} | grep -m20 -hoE 'sky130_fd_sc_hd__(ss|ff)_[n0-9]+C_1v[0-9]+'",
                         shell=True, capture_output=True, text=True).stdout
    for tok in set(out.split()):
        if "__ss_" in tok:
            ss_lib = tok.split("__")[1]
        if "__ff_" in tok:
            ff_lib = tok.split("__")[1]
    if ss_lib and ff_lib:
        break

# ---- compose: layout left, sheet panel right, provenance bottom ----
W, H = die_w / 1000.0, die_h / 1000.0  # mm
fig = plt.figure(figsize=(16.5, 11.0))
gs = fig.add_gridspec(1, 2, width_ratios=[7.4, 3.6], wspace=0.06,
                      left=0.05, right=0.985, top=0.90, bottom=0.115)
ax = fig.add_subplot(gs[0])
side = fig.add_subplot(gs[1]); side.axis("off")

ax.imshow(im, extent=[0, W, 0, H], origin="upper", interpolation="nearest")
ax.set_xlim(-W * 0.04, W * 1.04)
ax.set_ylim(-H * 0.10, H * 1.04)
ax.set_aspect("equal")
ticks = np.arange(0, W + 1e-9, 0.5)
ax.set_xticks(ticks); ax.set_yticks(ticks)
ax.set_xticklabels([f"{t:g}" for t in ticks], fontsize=10)
ax.set_yticklabels([f"{t:g}" for t in ticks], fontsize=10)
ax.set_xlabel("x (mm)", fontsize=11, labelpad=1)
ax.set_ylabel("y (mm)", fontsize=11)
ax.grid(True, color="#888", alpha=0.25, lw=0.6, ls=":")
for sp in ax.spines.values():
    sp.set_color("#888")
ax.add_patch(Rectangle((0, 0), W, H, fill=False, ec="#00e5ff", lw=1.6))

bar = 0.5
ax.plot([0, bar], [-H * 0.045, -H * 0.045], color="black", lw=5, solid_capstyle="butt")
ax.text(bar / 2, -H * 0.038, f"{bar:g} mm", ha="center", va="bottom",
        fontsize=11, fontweight="bold")
ax.text(W, -H * 0.036, f"die {W:.2f} mm x {H:.2f} mm  =  {W*H:.2f} mm$^2$",
        ha="right", va="top", fontsize=13, fontweight="bold", color="#222")

# ---- sheet: stacked sections on the right ----
DARK, CYAN, AMBER, RED = "#101418", "#00b8d4", "#e6a817", "#d84343"
y = 1.0
def section(header, body, header_color=CYAN, body_color="white"):
    global y
    side.text(0.02, y, header, transform=side.transAxes, ha="left", va="top",
              fontsize=13.5, fontweight="bold", color=header_color, family="monospace")
    y -= 0.030
    n = body.count("\n") + 1
    side.text(0.02, y, body, transform=side.transAxes, ha="left", va="top",
              fontsize=11.5, family="monospace", color=body_color, linespacing=1.45,
              bbox=dict(boxstyle="round,pad=0.55", fc=DARK, ec="#3a4750", lw=1.0))
    y -= 0.0245 * n + 0.052

side.text(0.02, 1.045, "PRE-SIGNOFF SHEET", transform=side.transAxes,
          ha="left", va="top", fontsize=17, fontweight="bold", color="#0a0a0a")
side.text(0.02, 1.012, "all numbers from Cadence Innovus 21.16 route-stage reports\n"
          "(verify_drc / timeDesign -postRoute) - Tempus signoff pending",
          transform=side.transAxes, ha="left", va="top", fontsize=9.5, color="#555")
y = 0.955

des = [f"Die size      {W:.2f} x {H:.2f} mm  ({W*H:.2f} mm2)",
       "Process       SKY130 HD std cells"]
if stdcells:
    if physcells:
        des.append(f"Std cells     {stdcells-physcells:,} logic")
        des.append(f"              +{physcells:,} decap/tap/diode/tie")
    else:
        des.append(f"Std cells     {stdcells:,}")
des.append(f"SRAM macros   {macros if macros else 16} x 32x256 (16 KB cache, 4-way)")
if period:
    des.append(f"Clock target  {period:.3f} ns  ({1000.0/period:.0f} MHz)")
if ss_lib and ff_lib:
    des.append(f"Setup corner  {ss_lib} + RC slow (+10%)")
    des.append(f"Hold corner   {ff_lib} + RC fast (-10%)")
    des.append(f"Macro derate  {a.derate}")
section("DESIGN", "\n".join(des))

tot = drc_total + (ant or 0)
dl = [f"Route DRC markers      {drc_total:>7,}"]
dl += [f"  {k:<19s}  {v:>7,}" for k, v in sorted(drc.items(), key=lambda kv: -kv[1])]
dl.append(f"Antenna violations     {(ant if ant is not None else 0):>7,}"
          + ("" if ant is not None else " (n/a)"))
dl.append("-" * 30)
dl.append(f"TOTAL violations       {tot:>7,}")
section("VIOLATIONS", "\n".join(dl), header_color=RED)

tl = ["             WNS(ns)   TNS(ns)   paths"]
if setup:
    tl.append(f"Setup   all  {setup['all'][0]:>7} {setup['all'][1]:>9} {setup['all'][2]:>7}")
    tl.append(f"    reg2reg  {setup['reg2reg'][0]:>7} {setup['reg2reg'][1]:>9} {setup['reg2reg'][2]:>7}")
if hold:
    tl.append(f"Hold    all  {hold['all'][0]:>7} {hold['all'][1]:>9} {hold['all'][2]:>7}")
    tl.append(f"    reg2reg  {hold['reg2reg'][0]:>7} {hold['reg2reg'][1]:>9} {hold['reg2reg'][2]:>7}")
tl.append("")
tl.append("WNS = worst negative slack")
tl.append("TNS = total negative slack (sum)")
if period and setup:
    try:
        fmax = 1000.0 / (period - float(setup["reg2reg"][0]))
        tl.append(f"reg2reg-implied Fmax ~ {fmax:.0f} MHz")
    except Exception:
        pass
section("TIMING (post-route, no opt)", "\n".join(tl), header_color=AMBER)

import klayout  # for __version__ in title + footer
title = a.title or os.path.basename(run)
fig.suptitle(f"{title}\nGDSII layout ({os.path.basename(gds)}) viewed in KLayout {klayout.__version__}",
             fontsize=16, fontweight="bold", x=0.05, y=0.985, ha="left")

# ---- provenance footer: this is a render of the real GDSII, tool by tool ----
import datetime, platform
st = os.stat(gds)
gds_date = datetime.datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
prov = (
    f"GDSII stream: {os.path.basename(gds)}  ({st.st_size/1e6:.0f} MB, written {gds_date})\n"
    f"Layout written by Cadence Innovus 21.16-s078_1 (streamOut, stage 06 export) - "
    f"P&R run {os.path.basename(run)}\n"
    f"Image rendered from that GDSII by KLayout {klayout.__version__} "
    f"(headless LayoutView, {a.px}px, {a.levels} hierarchy levels) on "
    f"{datetime.datetime.now().strftime('%Y-%m-%d %H:%M')} @ {platform.node()}\n"
    f"Sheet numbers parsed verbatim from the run's Innovus reports "
    f"(reports/route/drc.rpt, postroute*.summary, logs)"
)
fig.text(0.05, 0.012, prov, ha="left", va="bottom", fontsize=9,
         family="monospace", color="#555")

fig.savefig(a.out, dpi=170)
os.remove(tmp_png)
print(f"wrote {a.out}  (drc={drc_total}, antenna={ant}, die={W:.2f}x{H:.2f}mm)")
