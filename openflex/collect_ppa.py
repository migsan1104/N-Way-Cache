#!/usr/bin/env python3
"""Collect the per-associativity PPA results into one table.

Reads openflex/PPA/assoc_<N>/cache<N>.csv (headerless, one data row) and the
newest post-route power report in openflex/PPA/assoc_<N>/power/, then emits
a markdown table and, with --png, regenerates the summary chart.

CSV column order is the YAML `parameters:` keys, then fMax, then a
(used, total) pair per resource type:
  0 CACHE_BYTES | 1 ASSOC | 2 fMax | 3 LUT used | 4 LUT total
  5 LUTAsLogic used/total | 7 LUTAsMem used/total | 9 REG used | 10 REG total
"""

import argparse
import csv
import glob
import os
import re
import sys

ASSOCS = [1, 2, 4, 8, 16]

I_CACHE_BYTES, I_ASSOC, I_FMAX, I_LUT, I_REG = 0, 1, 2, 3, 9


def read_csv_row(ppa_dir, assoc):
    path = os.path.join(ppa_dir, f"assoc_{assoc}", f"cache{assoc}.csv")
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return None
    with open(path) as fh:
        rows = [r for r in csv.reader(fh) if r and not r[0].startswith("CACHE_BYTES")]
    if not rows:
        return None
    r = rows[-1]
    row_assoc = int(r[I_ASSOC])
    if row_assoc != assoc:
        # Guards against the shared-build-dir mix-up: a row landing in the
        # wrong folder means the run scraped another run's report.
        print(f"WARNING: {path} holds ASSOC={row_assoc}, expected {assoc}",
              file=sys.stderr)
    return {
        "cache_bytes": int(r[I_CACHE_BYTES]),
        "assoc": row_assoc,
        "fmax": float(r[I_FMAX]),
        "lut": int(r[I_LUT]),
        "reg": int(r[I_REG]),
        "mtime": os.path.getmtime(path),
    }


def read_power(ppa_dir, assoc):
    pats = sorted(glob.glob(os.path.join(ppa_dir, f"assoc_{assoc}", "power", "*.rpt")),
                  key=os.path.getmtime)
    if not pats:
        return {}
    path = pats[-1]
    fields = {
        "dynamic": r"Dynamic \(W\)",
        "static": r"Device Static \(W\)",
        "total": r"Total On-Chip Power \(W\)",
    }
    out = {"power_report": os.path.basename(path)}
    with open(path, errors="ignore") as fh:
        text = fh.read()
    for key, label in fields.items():
        m = re.search(r"\|\s*" + label + r"\s*\|\s*([0-9.]+)\s*\|", text)
        if m:
            out[key] = float(m.group(1))
    return out


def verify_fmax(ppa_dir, assoc, fmax, clk_period=1.0):
    """Fmax = 1000/(clk_period - WNS). Recompute it from the route report that
    sits in the same folder; a mismatch means the CSV and the reports disagree."""
    path = os.path.join(ppa_dir, f"assoc_{assoc}", "outputs",
                        "post_route_timing_summary.rpt")
    if not os.path.isfile(path):
        return None
    with open(path, errors="ignore") as fh:
        lines = fh.readlines()
    for i, line in enumerate(lines):
        if "WNS(ns)" in line and i + 2 < len(lines):
            parts = lines[i + 2].split()
            if parts:
                try:
                    wns = float(parts[0])
                except ValueError:
                    continue
                return 1000.0 / (clk_period - wns)
    return None


def collect(ppa_dir):
    rows = []
    for a in ASSOCS:
        rec = read_csv_row(ppa_dir, a)
        if rec is None:
            print(f"WARNING: no CSV data for assoc {a}", file=sys.stderr)
            continue
        rec.update(read_power(ppa_dir, a))
        rec["fmax_from_report"] = verify_fmax(ppa_dir, a, rec["fmax"])
        rows.append(rec)
    return rows


def markdown(rows):
    head = ("| Associativity (ways) | Fmax (MHz) | LUTs (Used) | FFs/REGs (Used) "
            "| Dynamic Power (W) | Static Power (W) | Total Power (W) |")
    sep = "|---:|---:|---:|---:|---:|---:|---:|"
    out = [head, sep]
    best = max(rows, key=lambda r: r["fmax"]) if rows else None
    for r in rows:
        f = f"**{r['fmax']:.1f}**" if r is best else f"{r['fmax']:.1f}"
        out.append(
            f"| {r['assoc']} | {f} | {r['lut']:,} | {r['reg']:,} | "
            f"{r.get('dynamic', float('nan')):.3f} | {r.get('static', float('nan')):.3f} | "
            f"{r.get('total', float('nan')):.3f} |")
    return "\n".join(out)


def make_png(rows, path, cache_kb):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    bg, fg, grid = "#0d1526", "#ffffff", "#2b3a52"
    hdr = "#16233b"

    cols = ["Associativity\n(ways)", "Fmax\n(MHz)", "LUTs\n(Used)", "FFs/REGs\n(Used)",
            "Dynamic Power\n(W)", "Static Power\n(W)", "Total Power\n(W)"]
    cells = [[f"{r['assoc']}", f"{r['fmax']:.1f}", f"{r['lut']:,}", f"{r['reg']:,}",
              f"{r.get('dynamic', 0):.3f}", f"{r.get('static', 0):.3f}",
              f"{r.get('total', 0):.3f}"] for r in rows]

    fig = plt.figure(figsize=(15.6, 7.9), dpi=200)
    fig.patch.set_facecolor(bg)
    # Table occupies the lower ~78%; the title and the "Overall" rule sit above it.
    ax = fig.add_axes([0.035, 0.02, 0.94, 0.78])
    ax.set_facecolor(bg)
    ax.axis("off")

    fig.text(0.5, 0.965, f"FPGA Cache PPA Scaling by Associativity ({cache_kb} KB)",
             ha="center", va="top", color=fg, fontsize=23, fontweight="bold")
    fig.text(0.035, 0.875, "Overall", ha="left", va="top", color=fg,
             fontsize=17, fontweight="bold")
    fig.add_artist(plt.Line2D([0.035, 0.975], [0.828, 0.828],
                              color=grid, lw=1.2))

    tbl = ax.table(cellText=cells, colLabels=cols, cellLoc="center", loc="center",
                   bbox=[0.0, 0.0, 1.0, 1.0])
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(13)
    for (row, _), cell in tbl.get_celld().items():
        cell.set_edgecolor(grid)
        cell.set_linewidth(1.0)
        cell.set_facecolor(hdr if row == 0 else bg)
        cell.set_text_props(color=fg, fontweight="normal")
        cell.set_height(0.16 if row == 0 else 0.14)

    fig.savefig(path, facecolor=bg, bbox_inches="tight", pad_inches=0.35)
    plt.close(fig)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ppa-dir", default=None)
    p.add_argument("--png", default=None)
    p.add_argument("--check", action="store_true",
                   help="cross-check each Fmax against its own route report")
    a = p.parse_args()

    ppa_dir = a.ppa_dir or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "PPA")
    rows = collect(ppa_dir)
    if not rows:
        sys.exit("no results found")

    print(markdown(rows))

    if a.check:
        print("\nFmax cross-check (CSV vs post_route_timing_summary.rpt):",
              file=sys.stderr)
        for r in rows:
            got = r["fmax_from_report"]
            if got is None:
                print(f"  assoc {r['assoc']:>2}: no route report", file=sys.stderr)
            else:
                ok = "ok" if abs(got - r["fmax"]) < 0.5 else "MISMATCH"
                print(f"  assoc {r['assoc']:>2}: csv={r['fmax']:8.3f}  "
                      f"report={got:8.3f}  {ok}", file=sys.stderr)

    sizes = {r["cache_bytes"] for r in rows}
    if len(sizes) > 1:
        print(f"WARNING: mixed CACHE_BYTES across rows: {sizes}", file=sys.stderr)

    if a.png:
        make_png(rows, a.png, sorted(sizes)[0] // 1024)
        print(f"\nwrote {a.png}", file=sys.stderr)


if __name__ == "__main__":
    main()
