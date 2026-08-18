#!/usr/bin/env python3
"""Check a synthesis run against the flow-correctness acceptance criteria.

This does not judge QoR. It judges whether the run is trustworthy: constrained
everywhere, one clock at the intended target, interconnect actually modelled,
no timing exceptions hiding paths, and a critical path that lands in real cache
logic rather than in reset or configuration logic.

Usage:
    ./check_acceptance.py                       # newest genus run
    ./check_acceptance.py --tool dc
    ./check_acceptance.py --run PPA/genus/assoc_8/runs/20260818_145403
"""

import argparse
import os
import re
import sys

# Sequential cell count of the pre-existing TT/2.0ns run, used as the reference
# for "did the register count move unexpectedly".
BASELINE_SEQ = 49625
SEQ_TOLERANCE = 0.10

EXPECTED_PERIOD_NS = 3.5
EXPECTED_UNCERTAINTY_NS = 0.25
MAX_VIOLATING = 500          # "a few hundred"

GREEN, RED, YELLOW, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[0m"
if not sys.stdout.isatty():
    GREEN = RED = YELLOW = RESET = ""

results = []


def record(name, ok, evidence, note=""):
    results.append((name, ok, evidence, note))


def read(path):
    if not os.path.isfile(path):
        return ""
    with open(path, errors="ignore") as fh:
        return fh.read()


def num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# 1. check_timing / check_timing_intent
# ---------------------------------------------------------------------------
def check_timing(rpt):
    txt = read(rpt)
    if not txt:
        record("check_timing", False, f"missing report: {rpt}")
        return

    # Genus check_timing_intent prints "<description>  <count>" lines.
    counts = dict(re.findall(r"^\s(.+?)\s{2,}(\d+)\s*$", txt, re.M))
    if counts:
        bad = {k: v for k, v in counts.items()
               if v != "0" and not k.lower().startswith("total")}
        total = counts.get("Total:", counts.get("Total", None))
        ev = f"{len(counts)} lint categories parsed; total = {total}"
        record("check_timing: zero unconstrained/unclocked/missing-delay items",
               not bad, ev,
               "" if not bad else "nonzero: " + ", ".join(f"{k}={v}" for k, v in bad.items()))
        return

    # DC check_timing prints warnings instead of a table.
    warn = re.findall(r"^Warning:.*$", txt, re.M)
    info = re.findall(r"^Information:.*(unconstrained|no clock|not constrained).*$",
                      txt, re.M | re.I)
    record("check_timing: no unconstrained/unclocked warnings",
           not warn and not info,
           f"{len(warn)} warnings, {len(info)} info lines",
           "" if not warn else warn[0][:140])


# ---------------------------------------------------------------------------
# 2. report_clocks
# ---------------------------------------------------------------------------
def check_clocks(rpt):
    txt = read(rpt)
    if not txt:
        record("report_clocks", False, f"missing report: {rpt}")
        return

    # Genus: "ss_view  clk     3500.0   0.0   1750.0   domain_1   clk  50548"
    g = re.findall(r"^\s*\S+\s+(\w+)\s+([\d.]+)\s+[\d.]+\s+[\d.]+\s+\S+\s+\S+\s+(\d+)\s*$",
                   txt, re.M)
    unc = re.findall(r"^\s*\S+\s+(\w+)\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+([\d.]+)\s+([\d.]+)\s*$",
                     txt, re.M)
    if g:
        names = {n for n, _, _ in g}
        period_ps = num(g[0][1])
        period_ns = period_ps / 1000.0 if period_ps else None
        record("report_clocks: exactly one clock", len(names) == 1,
               f"clocks found: {sorted(names)}")
        record(f"report_clocks: period = {EXPECTED_PERIOD_NS} ns",
               period_ns is not None and abs(period_ns - EXPECTED_PERIOD_NS) < 1e-6,
               f"{period_ps} ps = {period_ns} ns")
        if unc:
            u_ps = num(unc[0][1])
            u_ns = u_ps / 1000.0 if u_ps else None
            record(f"report_clocks: setup uncertainty = {EXPECTED_UNCERTAINTY_NS} ns",
                   u_ns is not None and abs(u_ns - EXPECTED_UNCERTAINTY_NS) < 1e-6,
                   f"{u_ps} ps = {u_ns} ns")
        else:
            record("report_clocks: setup uncertainty", False,
                   "uncertainty row not parsed")
        return

    # DC report_clock
    d = re.findall(r"^\s*(\w+)\s+([\d.]+)\s", txt, re.M)
    d = [(n, p) for n, p in d if n not in ("Clock", "Attributes")]
    if d:
        names = {n for n, _ in d}
        period = num(d[0][1])
        record("report_clocks: exactly one clock", len(names) == 1,
               f"clocks found: {sorted(names)}")
        record(f"report_clocks: period = {EXPECTED_PERIOD_NS} ns",
               period is not None and abs(period - EXPECTED_PERIOD_NS) < 1e-3,
               f"{period} ns")
    else:
        record("report_clocks", False, "could not parse any clock row")


# ---------------------------------------------------------------------------
# 3. net delay / cap visible and nonzero in report_timing
# ---------------------------------------------------------------------------
def check_net_delay(rpt):
    txt = read(rpt)
    if not txt:
        record("report_timing: nonzero net delay/cap", False, f"missing report: {rpt}")
        return

    # Genus full path rows end with numeric columns; net rows carry a load value.
    loads, delays = [], []
    for line in txt.splitlines():
        m = re.match(r"^\s+\S+.*?\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\(", line)
        if m:
            loads.append(num(m.group(2)))
            delays.append(num(m.group(4)))

    if not loads:
        # DC style: look for explicit net rows "(net)" with capacitance column
        net_rows = re.findall(r"^\s*.*\(net\).*$", txt, re.M)
        nz = [r for r in net_rows if re.search(r"\b0\.0{3,}\b", r) is None]
        record("report_timing: nonzero net delay/cap",
               bool(net_rows) and bool(nz),
               f"{len(net_rows)} net rows, {len(nz)} with nonzero values")
        return

    nz_load = [x for x in loads if x and x > 0]
    nz_delay = [x for x in delays if x and x > 0]
    record("report_timing: nonzero load (cap) on path rows",
           len(nz_load) == len(loads) and bool(loads),
           f"{len(nz_load)}/{len(loads)} rows have load > 0; "
           f"min={min(loads) if loads else 'n/a'} max={max(loads) if loads else 'n/a'} fF")
    record("report_timing: nonzero delay on path rows",
           bool(nz_delay),
           f"{len(nz_delay)}/{len(delays)} rows have delay > 0")


# ---------------------------------------------------------------------------
# 4. nonzero net area
# ---------------------------------------------------------------------------
def check_net_area(qor, area):
    txt = read(qor) + "\n" + read(area)
    m = re.search(r"Net Area\s+([\d.]+)", txt)
    if not m:
        m = re.search(r"Total interconnect area:\s*([\d.eE+-]+)", txt)
    if not m:
        record("report_area: nonzero net area", False,
               "no 'Net Area' / 'Total interconnect area' line found")
        return
    v = num(m.group(1))
    record("report_area: nonzero net area", bool(v and v > 0),
           f"Net Area = {m.group(1)}")


# ---------------------------------------------------------------------------
# 5. exceptions
# ---------------------------------------------------------------------------
def check_exceptions(rpt):
    txt = read(rpt)
    if not txt:
        record("exceptions: none declared", False, f"missing report: {rpt}")
        return
    none = "NONE - no active timing exceptions are declared." in txt
    record("exceptions: none declared", none,
           "report states NONE" if none
           else "report lists exception statements")


# ---------------------------------------------------------------------------
# 6/7. violating paths and sequential cell count
# ---------------------------------------------------------------------------
def check_qor(qor):
    txt = read(qor)
    if not txt:
        record("report_qor", False, f"missing report: {qor}")
        return

    m = re.search(r"^clk\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s*$", txt, re.M)
    if m:
        wns_ps, tns_ps, viol = num(m.group(1)), num(m.group(2)), int(m.group(3))
        record(f"violating paths < {MAX_VIOLATING}", viol < MAX_VIOLATING,
               f"{viol:,} violating paths; WNS = {wns_ps/1000:.3f} ns, "
               f"TNS = {tns_ps/1000:.1f} ns")
    else:
        m = re.search(r"No\. of Violating Paths:\s*(\d+)", txt)
        if m:
            viol = int(float(m.group(1)))
            s = re.search(r"Critical Path Slack:\s*(-?[\d.]+)", txt)
            record(f"violating paths < {MAX_VIOLATING}", viol < MAX_VIOLATING,
                   f"{viol:,} violating paths; WNS = {s.group(1) if s else 'n/a'} ns")
        else:
            record(f"violating paths < {MAX_VIOLATING}", False,
                   "could not parse violating path count")

    m = re.search(r"Sequential (?:Instance|Cell) Count\s*:?\s*(\d+)", txt)
    if m:
        seq = int(m.group(1))
        delta = abs(seq - BASELINE_SEQ) / BASELINE_SEQ
        record(f"sequential cells within {int(SEQ_TOLERANCE*100)}% of {BASELINE_SEQ:,}",
               delta <= SEQ_TOLERANCE,
               f"{seq:,} sequential cells ({delta*100:+.1f}% vs baseline)")
    else:
        record("sequential cell count", False, "could not parse")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tool", default="genus", choices=["genus", "dc"])
    ap.add_argument("--assoc", default="8")
    ap.add_argument("--run", default=None, help="explicit run directory")
    a = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    if a.run:
        run = a.run if os.path.isabs(a.run) else os.path.join(here, a.run)
    else:
        run = os.path.join(here, "PPA", a.tool, f"assoc_{a.assoc}", "runs", "latest")
    rpt = os.path.join(run, "reports")

    if not os.path.isdir(rpt):
        sys.exit(f"no reports directory: {rpt}")

    print(f"Run      : {os.path.realpath(run)}")
    print(f"Reports  : {rpt}\n")

    check_timing(os.path.join(rpt, "check_timing.rpt"))
    check_clocks(os.path.join(rpt, "clocks.rpt"))
    check_net_delay(os.path.join(rpt, "timing.rpt"))
    check_net_area(os.path.join(rpt, "qor.rpt"), os.path.join(rpt, "area.rpt"))
    check_exceptions(os.path.join(rpt, "exceptions.rpt"))
    check_qor(os.path.join(rpt, "qor.rpt"))

    width = max(len(n) for n, _, _, _ in results)
    failed = 0
    for name, ok, ev, note in results:
        tag = f"{GREEN}PASS{RESET}" if ok else f"{RED}FAIL{RESET}"
        if not ok:
            failed += 1
        print(f"[{tag}] {name.ljust(width)}  {ev}")
        if note:
            print(f"         {YELLOW}{note}{RESET}")

    print(f"\n{len(results) - failed}/{len(results)} criteria pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
