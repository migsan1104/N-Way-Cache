#!/usr/bin/env python3
"""Read run_*/wave.txt (ngspice wrdata, single time scale, named columns) and
report, per read cycle: clk fall -> dout1 50 % crossing (access), 10-90 %
output transition, s_en1 / wl_en1 rise after the fall, and how long dout1 holds
its value after the NEXT rising edge (the hold-after-rising-edge question).
    python3 analyze.py run_p5p3_l7 [run_p20_l7 ...]
"""
import sys, re, numpy as np
V = 1.76; H = 0.5 * V; LO, HI = 0.1 * V, 0.9 * V

def load(path):
    with open(path) as f:
        hdr = f.readline().split()
    data = np.loadtxt(path, skiprows=1)
    return hdr, data

def crossings(t, v, level, rising=None):
    s = np.sign(v - level); idx = np.where(np.diff(s) != 0)[0]
    out = []
    for i in idx:
        if rising is True and not (v[i] < level <= v[i+1]): continue
        if rising is False and not (v[i] > level >= v[i+1]): continue
        # linear interpolation
        t0, t1, v0, v1 = t[i], t[i+1], v[i], v[i+1]
        out.append(t0 + (level - v0) * (t1 - t0) / (v1 - v0))
    return np.array(out)

def first_after(arr, t):
    a = arr[arr > t]; return a[0] if len(a) else np.nan

for run in sys.argv[1:]:
    hdr, d = load(f"{run}/wave.txt")
    col = {h: i for i, h in enumerate(hdr)}
    t = d[:, col["time"]] * 1e9
    clk = d[:, col["v(clk)"]]
    T = float(re.search(r"p(\d+p?\d*)", run).group(1).replace("p", "."))
    rises = crossings(t, clk, H, True); falls = crossings(t, clk, H, False)
    sen = d[:, col["v(xsram.s_en1)"]]; wlen = d[:, col["v(xsram.wl_en1)"]]
    print(f"\n=== {run}  (T={T} ns; {len(rises)} rising edges)")
    print(f"{'cycle':>5} {'fall@':>7} {'wl_en1':>7} {'s_en1':>7} | " + " ".join(f"{'d1[%d]'%b:>16}" for b in (0, 1, 11)) + " | hold after next rise")
    for k in (3, 4, 5):                       # read cycles
        tf = falls[k - 1]; tr_next = rises[k] if k < len(rises) else np.nan
        row = [f"{k:>5} {tf:7.2f} {first_after(crossings(t, wlen, H, True), tf) - tf:7.2f} {first_after(crossings(t, sen, H, True), tf) - tf:7.2f} |"]
        holds = []
        for b in (0, 1, 11):
            v = d[:, col[f"v(dout1_{b})"]]
            c50 = first_after(crossings(t, v, H), tf); tr = first_after(crossings(t, v, HI, True), tf); tl = first_after(crossings(t, v, LO, False), tf)
            # transition: whichever direction happened
            t10 = first_after(crossings(t, v, LO), tf); t90 = first_after(crossings(t, v, HI), tf)
            row.append(f"acc {c50 - tf:5.2f} tr {abs(t90 - t10):5.2f} |")
            if not np.isnan(tr_next):
                # value at the rising edge, and first time it leaves +-0.2 V of that value afterwards
                v_at = np.interp(tr_next, t, v)
                m = (t > tr_next) & (np.abs(v - v_at) > 0.2)
                holds.append(t[m][0] - tr_next if m.any() else np.inf)
        print(" ".join(row) + (f" {min(holds):5.2f} ns" if holds else ""))
    print("acc = clk1 fall to dout1 50 % (ns); tr = 10-90 % transition; wl_en1/s_en1 = rise after the fall; hold = dout1 stays within 0.2 V of its value this long after the next RISING edge")
