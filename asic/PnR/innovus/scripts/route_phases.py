#!/usr/bin/env python3
"""Per-run stage-05 phase table: DRC / setup WNS / TNS / hold WNS at the end of
raw route, post-route setup opt, and post-route hold opt (2026-09-09, user ask:
"get to end of stage 5 for each iter and note each one's drc, wns, tns at the
end of each route phase"). Reads logs/flow.log* (newest by mtime, so a resumed
run's flow.log1 wins). Anchors are the <CMD> echoes Innovus writes:
  raw   = <CMD> routeDesign            .. <CMD> optDesign -postRoute
  setup = <CMD> optDesign -postRoute   .. <CMD> optDesign -postRoute -hold
  hold  = <CMD> optDesign -postRoute -hold .. end of log
Within each segment: the LAST "Setup mode" / "Hold mode" timeDesign table
(all / reg2reg / default WNS, all TNS), the last routeDesign/ecoRoute
"#Total number of DRC violations = N" and the last verify_drc
"Verification Complete : N Viols." (raw = the gate count, hold = the stage's
final count). A phase whose closing anchor has not appeared yet is marked
"running"; numbers shown for it are the latest so far.
Usage: route_phases.py [run_dir ...]   (default: runs/20260908_iter26*_1v76)
"""
import glob, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
RUNS = os.path.join(os.path.dirname(HERE), "runs")

def newest_log(d):
    c = [p for p in glob.glob(os.path.join(d, "logs", "flow.log*")) if re.search(r"flow\.log\d*$", p)]
    return max(c, key=os.path.getmtime) if c else None

def parse(path):
    L = open(path, errors="replace").read().splitlines()
    anchors = {"route": None, "setup": None, "hold": None}
    for i, s in enumerate(L):
        if s.startswith("<CMD> routeDesign"): anchors["route"] = i
        elif s.startswith("<CMD> optDesign -postRoute -hold") and anchors["setup"] is not None and anchors["hold"] is None: anchors["hold"] = i
        elif s.startswith("<CMD> optDesign -postRoute") and anchors["route"] is not None and anchors["setup"] is None: anchors["setup"] = i
    ended = any(s.startswith('--- Ending "Innovus"') for s in L[-200:])
    tables = []  # (line, mode, wns_all, wns_r2r, wns_def, tns_all)
    i = 0
    while i < len(L):
        m = re.match(r"\|\s+(Setup|Hold) mode\s+\|", L[i])
        if m:
            w = t = None
            for j in range(i + 1, min(i + 5, len(L))):
                mw = re.match(r"\|\s+WNS \(ns\):\|(.*)", L[j]); mt = re.match(r"\|\s+TNS \(ns\):\|(.*)", L[j])
                if mw: w = [x.strip() for x in mw.group(1).strip("|").split("|")]
                if mt: t = [x.strip() for x in mt.group(1).strip("|").split("|")]
            if w and t: tables.append((i, m.group(1), w[0], w[1] if len(w) > 1 else "", w[2] if len(w) > 2 else "", t[0]))
            i += 4
        else: i += 1
    drc, vdrc = [], []
    for i, s in enumerate(L):
        m = re.match(r"#Total number of DRC violations = (\d+)", s)
        if m: drc.append((i, int(m.group(1)))); continue
        m = re.search(r"Verification Complete : (\d+) Viols", s)
        if m: vdrc.append((i, int(m.group(1))))
    return L, anchors, ended, tables, drc, vdrc

def seg(anchors, ended, name):
    order = ["route", "setup", "hold"]
    a = anchors[name]
    if a is None: return None
    nxt = [anchors[k] for k in order[order.index(name) + 1:] if anchors[k] is not None]
    return (a, nxt[0] if nxt else None, bool(nxt) or ended)

def last_in(items, a, b, pick=lambda x: True):
    r = [x for x in items if x[0] > a and (b is None or x[0] < b) and pick(x)]
    return r[-1] if r else None

def main(dirs):
    rows = []
    for d in dirs:
        name = re.search(r"(iter26[a-z]?)_", os.path.basename(d)); name = name.group(1) if name else os.path.basename(d)[:12]
        if "_usk_" in os.path.basename(d): name += " usk"
        log = newest_log(d)
        if not log: rows.append((name, "no log", "", "", "", "", "", "")); continue
        L, anchors, ended, tables, drc, vdrc = parse(log)
        if anchors["route"] is None:
            rows.append((name, "pre-route", "", "", "", "", "", "stage<05" + (" (ended)" if ended else ""))); continue
        for ph, label in (("route", "raw route"), ("setup", "setup opt"), ("hold", "hold opt")):
            s = seg(anchors, ended, ph)
            if s is None: rows.append((name, label, "", "", "", "", "", "not reached")); continue
            a, b, done = s
            st = last_in(tables, a, b, lambda x: x[1] == "Setup"); ho = last_in(tables, a, b, lambda x: x[1] == "Hold")
            dd = last_in(drc, a, b); vd = last_in(vdrc, a, b)
            rows.append((name, label,
                         (str(dd[1]) if dd else "") + (f" / v{vd[1]}" if vd else ""),
                         st[2] if st else "", st[3] if st else "", st[4] if st else "", st[5] if st else "",
                         (ho[2] if ho else "") + ("" if done else "  (running)")))
    hdr = ("run", "phase", "DRC route/verify", "setup WNS all", "reg2reg", "default", "TNS all", "hold WNS")
    w = [max(len(str(r[i])) for r in rows + [hdr]) for i in range(len(hdr))]
    line = lambda r: "| " + " | ".join(str(r[i]).ljust(w[i]) for i in range(len(hdr))) + " |"
    print(line(hdr)); print("|" + "|".join("-" * (x + 2) for x in w) + "|")
    for r in rows: print(line(r))

if __name__ == "__main__":
    dirs = sys.argv[1:] or sorted(glob.glob(os.path.join(RUNS, "20260908_iter26*_1v76")), key=lambda p: (re.search(r"iter26([a-z]?)_", p).group(1), "_usk_" in p))
    main(dirs)
