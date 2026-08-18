#!/usr/bin/env python3
"""Collect ASIC synthesis PPA results into one table per tool.

Reads asic/PPA/<tool>/assoc_<N>/reports/ for every associativity that has been
run and prints a markdown table for each tool. Genus and Design Compiler write
different report formats, so each has its own parser, but both are reduced to
the same set of columns so the two tables can be compared side by side.

Usage:
    ./collect_ppa.py                  # every tool, every associativity found
    ./collect_ppa.py --tool dc        # one tool
    ./collect_ppa.py --markdown out.md
"""

import argparse
import glob
import os
import re
import sys

TOOLS = ("genus", "dc")
TOOL_LABEL = {"genus": "Cadence Genus", "dc": "Synopsys Design Compiler"}

# Power values appear with a unit suffix that varies by magnitude.
POWER_SCALE = {"W": 1.0, "mW": 1e-3, "uW": 1e-6, "nW": 1e-9, "pW": 1e-12}


def _f(text, pattern, group=1, cast=float, flags=re.M):
    m = re.search(pattern, text, flags)
    if not m:
        return None
    try:
        return cast(m.group(group))
    except (ValueError, IndexError):
        return None


def _read(path):
    if not os.path.isfile(path):
        return ""
    with open(path, errors="ignore") as fh:
        return fh.read()


def _power(value, unit):
    if value is None:
        return None
    return value * POWER_SCALE.get(unit, 1.0)


def parse_dc(run_dir):
    """Design Compiler: report_qor + report_area + report_power."""
    qor = _read(os.path.join(run_dir, "reports", "qor.rpt"))
    area = _read(os.path.join(run_dir, "reports", "cell_area.rpt"))
    power = _read(os.path.join(run_dir, "reports", "power.rpt"))
    if not qor:
        return None

    out = {
        "period": _f(qor, r"Critical Path Clk Period:\s*([-\d.]+)"),
        "path": _f(qor, r"Critical Path Length:\s*([-\d.]+)"),
        "slack": _f(qor, r"Critical Path Slack:\s*([-\d.]+)"),
        "tns": _f(qor, r"Total Negative Slack:\s*([-\d.]+)"),
        "violating": _f(qor, r"No\. of Violating Paths:\s*([-\d.]+)", cast=lambda v: int(float(v))),
        "cells": _f(qor, r"Leaf Cell Count:\s*(\d+)", cast=int),
        "seq": _f(qor, r"Sequential Cell Count:\s*(\d+)", cast=int),
        "macros": _f(qor, r"Macro Count:\s*(\d+)", cast=int),
        "area": _f(area, r"Total cell area:\s*([\d.]+)"),
        "cache_bytes": _f(qor, r"CACHE_BYTES(\d+)", cast=int),
    }

    m = re.search(r"Total Dynamic Power\s*=\s*([\d.]+)\s*(\w+)", power)
    dyn = _power(float(m.group(1)), m.group(2)) if m else None
    m = re.search(r"Cell Leakage Power\s*=\s*([\d.]+)\s*(\w+)", power)
    leak = _power(float(m.group(1)), m.group(2)) if m else None
    out["dynamic"] = dyn
    out["leakage"] = leak
    out["total_power"] = None if dyn is None else dyn + (leak or 0.0)
    return out


def parse_genus(run_dir):
    """Genus: report_qor + report_area + report_power (Joules)."""
    qor = _read(os.path.join(run_dir, "reports", "qor.rpt"))
    area = _read(os.path.join(run_dir, "reports", "area.rpt"))
    power = _read(os.path.join(run_dir, "reports", "power.rpt"))
    if not qor:
        return None

    # Genus reports timing in picoseconds.
    period_ps = _f(qor, r"^clk\s+([\d.]+)\s*$", cast=float)
    row = re.search(r"^clk\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s*$", qor, re.M)
    slack_ps = float(row.group(1)) if row else None
    tns_ps = float(row.group(2)) if row else None
    violating = int(row.group(3)) if row else None

    out = {
        "period": None if period_ps is None else period_ps / 1000.0,
        "slack": None if slack_ps is None else slack_ps / 1000.0,
        "tns": None if tns_ps is None else tns_ps / 1000.0,
        "violating": violating,
        "cells": _f(qor, r"Leaf Instance Count\s+(\d+)", cast=int),
        "seq": _f(qor, r"Sequential Instance Count\s+(\d+)", cast=int),
        "macros": 0,
    }
    out["path"] = (None if out["period"] is None or out["slack"] is None
                   else out["period"] - out["slack"])
    out["cache_bytes"] = _f(qor, r"CACHE_BYTES(\d+)", cast=int)

    # Top-level row of report_area: <instance> [module] cells cell_area net_area total_area
    m = re.search(r"^(Cache\S*)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)", area, re.M)
    if m:
        out["area"] = float(m.group(5))
        out["cells"] = out["cells"] or int(m.group(2))

    m = re.search(r"^\s*Subtotal\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", power, re.M)
    if m:
        try:
            out["leakage"] = float(m.group(1))
            out["total_power"] = float(m.group(4))
            out["dynamic"] = out["total_power"] - out["leakage"]
        except ValueError:
            pass
    return out


PARSERS = {"dc": parse_dc, "genus": parse_genus}


def resolve_run_dir(assoc_dir):
    """Return the directory whose reports/ should be read for this assoc.

    Runs are written to <assoc>/runs/<stamp>/ with a `latest` symlink. Older
    runs wrote straight to <assoc>/reports/, so fall back to that layout.
    """
    latest = os.path.join(assoc_dir, "runs", "latest")
    if os.path.isdir(os.path.join(latest, "reports")):
        return latest
    runs = sorted(glob.glob(os.path.join(assoc_dir, "runs", "*")))
    runs = [r for r in runs if os.path.isdir(os.path.join(r, "reports"))]
    if runs:
        return runs[-1]
    return assoc_dir


def collect(ppa_root, tool):
    rows = []
    pattern = os.path.join(ppa_root, tool, "assoc_*")
    for assoc_dir in sorted(glob.glob(pattern),
                            key=lambda p: int(p.rsplit("_", 1)[-1])):
        assoc = int(assoc_dir.rsplit("_", 1)[-1])
        run_dir = resolve_run_dir(assoc_dir)
        rec = PARSERS[tool](run_dir)
        if rec is None:
            print(f"WARNING: no qor.rpt under {run_dir}, skipping", file=sys.stderr)
            continue
        rec["assoc"] = assoc
        # Achievable period = target - slack (slack is negative when violating).
        if rec.get("period") is not None and rec.get("slack") is not None:
            achievable = rec["period"] - rec["slack"]
            rec["fmax"] = 1000.0 / achievable if achievable > 0 else None
        else:
            rec["fmax"] = None
        rows.append(rec)
    return rows


def fmt(v, spec="", dash="-"):
    if v is None:
        return dash
    return format(v, spec)


def markdown(tool, rows):
    lines = [f"### {TOOL_LABEL[tool]}", ""]
    if not rows:
        lines += ["_No runs found._", ""]
        return "\n".join(lines)

    lines += [
        "| ASSOC | Target (ns) | WNS (ns) | Achievable Fmax (MHz) | Cell area (um^2) | "
        "Cells | Sequential | Macros | Total power (W) | Violating paths |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r['assoc']} | {fmt(r.get('period'), '.3f')} | {fmt(r.get('slack'), '.3f')} | "
            f"{fmt(r.get('fmax'), '.1f')} | {fmt(r.get('area'), ',.0f')} | "
            f"{fmt(r.get('cells'), ',')} | {fmt(r.get('seq'), ',')} | {fmt(r.get('macros'), ',')} | "
            f"{fmt(r.get('total_power'), '.3f')} | {fmt(r.get('violating'), ',')} |")
    lines.append("")

    closed = [r for r in rows if (r.get("slack") or 0) >= 0]
    if not closed:
        worst = min(rows, key=lambda r: r.get("slack") if r.get("slack") is not None else 0)
        lines.append(
            f"_No configuration closes timing at its target; worst is ASSOC={worst['assoc']} "
            f"at {fmt(worst.get('slack'), '.3f')} ns._")
        lines.append("")
    return "\n".join(lines)


# Filenames the README references; both carry "Synthesis_PPA" so they are not
# confused with the FPGA chart, which measures a different thing entirely.
PNG_STEM = {"genus": "ASIC_Genus_Synthesis_PPA", "dc": "ASIC_DC_Synthesis_PPA"}


def make_png(tool, rows, path, cache_kb):
    """Render one tool's table as an image, matching the FPGA chart's styling."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    bg, fg, grid = "#0d1526", "#ffffff", "#2b3a52"
    hdr, best_bg = "#16233b", "#1b2a45"

    cols = ["Associativity\n(ways)", "Target\n(ns)", "WNS\n(ns)", "Fmax\n(MHz)",
            "Cell Area\n(um^2)", "Cells", "Sequential\nCells",
            "Total Power\n(W)", "Violating\nPaths"]
    cells = [[f"{r['assoc']}", fmt(r.get("period"), ".3f"), fmt(r.get("slack"), ".3f"),
              fmt(r.get("fmax"), ".1f"), fmt(r.get("area"), ",.0f"),
              fmt(r.get("cells"), ","), fmt(r.get("seq"), ","),
              fmt(r.get("total_power"), ".3f"), fmt(r.get("violating"), ",")]
             for r in rows]

    timed = [r for r in rows if r.get("fmax") is not None]
    best = max(timed, key=lambda r: r["fmax"]) if timed else None
    best_row = rows.index(best) + 1 if best is not None else None

    fig = plt.figure(figsize=(17.5, 7.9), dpi=200)
    fig.patch.set_facecolor(bg)
    ax = fig.add_axes([0.035, 0.02, 0.94, 0.78])
    ax.set_facecolor(bg)
    ax.axis("off")

    period = next((r.get("period") for r in rows if r.get("period") is not None), None)
    target = "" if period is None else f"  |  {period:.3f} ns target"

    fig.text(0.5, 0.965,
             f"{TOOL_LABEL[tool]} Synthesis PPA Scaling by Associativity ({cache_kb} KB)",
             ha="center", va="top", color=fg, fontsize=23, fontweight="bold")
    fig.text(0.035, 0.875, f"SKY130 HD  |  TT 1.80 V 25 C{target}",
             ha="left", va="top", color=fg, fontsize=17, fontweight="bold")
    fig.add_artist(plt.Line2D([0.035, 0.975], [0.828, 0.828], color=grid, lw=1.2))

    tbl = ax.table(cellText=cells, colLabels=cols, cellLoc="center", loc="center",
                   bbox=[0.0, 0.0, 1.0, 1.0])
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(13)
    for (row, _), cell in tbl.get_celld().items():
        cell.set_edgecolor(grid)
        cell.set_linewidth(1.0)
        if row == 0:
            cell.set_facecolor(hdr)
        elif row == best_row:
            cell.set_facecolor(best_bg)
        else:
            cell.set_facecolor(bg)
        cell.set_text_props(
            color=fg, fontweight="bold" if row == best_row else "normal")
        cell.set_height(0.16 if row == 0 else 0.14)

    fig.savefig(path, facecolor=bg, bbox_inches="tight", pad_inches=0.35)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ppa-root", default=None)
    ap.add_argument("--tool", choices=TOOLS, action="append",
                    help="restrict to one tool (repeatable)")
    ap.add_argument("--markdown", help="also write the tables to this file")
    ap.add_argument("--png", metavar="DIR",
                    help="also render each tool's table into DIR as a PNG")
    args = ap.parse_args()

    ppa_root = args.ppa_root or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "PPA")
    tools = args.tool or list(TOOLS)

    blocks = []
    charts = []
    for tool in tools:
        rows = collect(ppa_root, tool)
        blocks.append(markdown(tool, rows))
        if args.png and rows:
            sizes = {r.get("cache_bytes") for r in rows} - {None}
            if len(sizes) > 1:
                print(f"WARNING: mixed CACHE_BYTES in {tool} rows: {sizes}",
                      file=sys.stderr)
            cache_kb = (sorted(sizes)[0] // 1024) if sizes else 0
            out = os.path.join(args.png, f"{PNG_STEM[tool]}_{cache_kb}KB.png")
            make_png(tool, rows, out, cache_kb)
            charts.append(out)
    text = "\n".join(blocks)

    print(text)
    if args.markdown:
        with open(args.markdown, "w") as fh:
            fh.write(text + "\n")
        print(f"wrote {args.markdown}", file=sys.stderr)
    for c in charts:
        print(f"wrote {c}", file=sys.stderr)


if __name__ == "__main__":
    main()
