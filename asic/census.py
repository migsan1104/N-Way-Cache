#!/usr/bin/env python3
"""Group a Genus timing report into startpoint->endpoint CLASSES.

    ./census.py <report.rpt> [--limit N] [--top K]

One worst path is an anecdote. The campaign judges a fix by whether its
POPULATION disappeared, which needs paths grouped by cone, not listed. The FPGA
flow has always done this; run_genus.tcl only started emitting a deep report
(reports/census.rpt, 1000 paths) on 2026-08-22, so older runs have just
timing.rpt with 20 paths - enough to name the worst cone and nothing more.

  --limit N   census only the worst N paths (default: all).
              Use this. Grouping all 1000 ranks by population and the bulk
              (hundreds of paths 1500 ps behind WNS) drowns out the critical
              spike. --limit 40 and --limit 120 are the useful views.
  --top K     show at most K classes.

Reads the "Startpoint:/Endpoint:/Slack:=" blocks that both -path_type summary
and -path_type full produce, so it works on timing.rpt and census.rpt alike.

Vivado reports are a different format; the FPGA censuses are produced from the
post-route checkpoints under openflex/PPA/assoc_*/outputs/ and are not parsed
here.
"""
import argparse
import collections
import re
import sys

# Collapse bus bits and per-instance generate prefixes so paths that are the
# same cone land in the same bucket.
_STRIP_PREFIXES = ("GEN_WAYS[*].", "GEN_MSHR_ENTRIES[*].", "MSHR_FILE_")


def normalise(pin):
    pin = re.sub(r"\[\d+\]", "[*]", pin)
    pin = re.sub(r"/(CLK|D|Q|CDN|E)$", "", pin)
    for prefix in _STRIP_PREFIXES:
        pin = pin.replace(prefix, "")
    return pin


def parse(path):
    text = open(path).read()
    starts = [m.start() for m in re.finditer(r"^\s*Startpoint:", text, re.M)]
    if not starts:
        sys.exit("no timing paths found in {} - is this a Genus report?".format(path))
    rows = []
    for a, b in zip(starts, starts[1:] + [len(text)]):
        block = text[a:b]
        s = re.search(r"Startpoint:\s*\(?\w?\)?\s*(\S+)", block)
        e = re.search(r"Endpoint:\s*\(?\w?\)?\s*(\S+)", block)
        slack = re.search(r"Slack:=\s*(-?\d+)", block)
        if s and e and slack:
            rows.append((int(slack.group(1)), normalise(s.group(1)), normalise(e.group(1))))
    rows.sort()
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("report")
    ap.add_argument("--limit", type=int, default=0, help="census only the worst N paths")
    ap.add_argument("--top", type=int, default=20, help="show at most K classes")
    args = ap.parse_args()

    rows = parse(args.report)
    wns = rows[0][0]

    print("{} paths, WNS {} ps".format(len(rows), wns))
    print("distribution:")
    for band in (50, 100, 200, 400, 800):
        n = sum(1 for slack, _, _ in rows if slack <= wns + band)
        print("   within {:4d} ps of WNS : {:4d} paths".format(band, n))
    print()

    subset = rows[:args.limit] if args.limit else rows
    counts = collections.Counter((a, b) for _, a, b in subset)
    slacks = collections.defaultdict(list)
    for slack, a, b in subset:
        slacks[(a, b)].append(slack)

    label = "worst {}".format(args.limit) if args.limit else "all"
    print("classes ({} paths):".format(label))
    for (a, b), n in counts.most_common(args.top):
        span = slacks[(a, b)]
        print("  {:4d}  {:6d}..{:<6d}  {} -> {}".format(n, min(span), max(span), a, b))


if __name__ == "__main__":
    main()
