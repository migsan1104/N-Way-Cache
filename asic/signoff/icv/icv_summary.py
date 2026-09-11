#!/usr/bin/env python3
"""icv_summary.py -- per-rule violation counts from an IC Validator <cell>.LAYOUT_ERRORS file,
in the same shape as asic/signoff/drc/classify_lyrdb.py prints for KLayout, so the two
engines can be compared rule by rule.

    icv_summary.py <cell>.LAYOUT_ERRORS [--details] [--csv]
    icv_summary.py --klayout <drc.lyrdb>      # same table from a KLayout report, for diffing

*** Written 2026-09-05 against the LAYOUT_ERRORS format documented in icvug1.pdf ch. 3
    ("Error File", U-2022.12) and tested only on a fixture built from that example
    (tests/fixture.LAYOUT_ERRORS) -- no real ICV run has produced a file on this machine
    (see SIV.md section 6, license wall). Expect to adjust the regexes on first contact.

Format assumed (from the manual):
    LAYOUT ERRORS RESULTS: ERRORS | CLEAN            (first non-blank line)
    ...
                ERROR SUMMARY
      <violation comment>                            (rule name = text before first ':')
        <function> ......... N violation(s) found.   (one line per rule function)
                ERROR DETAILS
    ------------------
    <violation comment>
    ------------------
    <runset>:<line>:<function>
    Structure ( llx, lly ) ( urx, ury ) [extra]       (one line per error, in the cell
                                                       it was found -- hierarchical)
"""
import re, sys, collections, argparse

SUM_RE = re.compile(r'^\s+(\S.*?)\s*\.{3,}\s*(\d+)\s+violations?\s+found', re.I)
DET_RE = re.compile(r'^\s*(\S+)\s+\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)\s+\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)')

def parse_layout_errors(path):
    status = None; summary = collections.OrderedDict(); details = collections.defaultdict(list)
    section = None; rule = None; pending_rule = None
    with open(path, errors='replace') as f:
        for line in f:
            s = line.rstrip('\n')
            if status is None and 'LAYOUT ERRORS RESULTS:' in s:
                status = s.split(':', 1)[1].strip(); continue
            if 'ERROR SUMMARY' in s: section = 'summary'; continue
            if 'ERROR DETAILS' in s: section = 'details'; rule = None; continue
            if section == 'summary':
                m = SUM_RE.match(s)
                if m and pending_rule is not None:
                    summary[pending_rule] = summary.get(pending_rule, 0) + int(m.group(2))
                elif s.strip() and not m:
                    pending_rule = s.strip()
            elif section == 'details':
                if s.startswith('-----'): continue
                if rule is None or (s.strip() and s.strip() in summary and not DET_RE.match(s)):
                    if s.strip() in summary: rule = s.strip()
                    continue
                m = DET_RE.match(s)
                if m and not s.lstrip().startswith('Structure'):
                    details[rule].append((m.group(1),) + tuple(float(x) for x in m.groups()[1:]))
    return status, summary, details

def rule_id(comment):
    return comment.split(':', 1)[0].strip()

def parse_lyrdb(path):
    txt = open(path, encoding='utf-8', errors='replace').read()
    c = collections.Counter()
    for it in re.findall(r'<item>(.*?)</item>', txt, re.S):
        m = re.search(r"<category>'?([^'<]+)'?</category>", it)
        c[m.group(1) if m else '?'] += 1
    return c

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('path'); ap.add_argument('--details', action='store_true')
    ap.add_argument('--csv', action='store_true'); ap.add_argument('--klayout', action='store_true')
    a = ap.parse_args()
    if a.klayout:
        c = parse_lyrdb(a.path)
        for k, v in sorted(c.items()): print(f'{k},{v}' if a.csv else f'{k:12s} {v:9d}')
        print(f'total {sum(c.values())}'); return
    status, summary, details = parse_layout_errors(a.path)
    print(f'# {a.path}: LAYOUT ERRORS RESULTS: {status}')
    tot = 0
    for comment, n in summary.items():
        tot += n
        print(f'{rule_id(comment)},{n}' if a.csv else f'{rule_id(comment):12s} {n:9d}   {comment}')
    print(f'total {tot}   rules-with-errors {sum(1 for v in summary.values() if v)}')
    if a.details:
        for comment, lst in details.items():
            cells = collections.Counter(x[0] for x in lst)
            print(f'## {rule_id(comment)}: {len(lst)} detail lines; by structure: ' +
                  ', '.join(f'{k} {v}' for k, v in cells.most_common(8)))

if __name__ == '__main__':
    main()
