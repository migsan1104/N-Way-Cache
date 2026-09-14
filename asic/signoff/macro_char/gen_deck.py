#!/usr/bin/env python3
"""Generate an ngspice deck that reads the exact PDK SRAM macro in the GDS
(sram_1rw1r_32_256_8_sky130) at the signoff corner and measures the read.

    python3 gen_deck.py --period 5.3 --load 7 --out run_p5p3_l7 [--corner ss --temp -40 --vdd 1.76]

Sequence (rising edges at k*T): cycle 1 write 0x0A <- A5A5A5A5, cycle 2 write
0x0B <- 5A5A5A5A (port 0), cycle 3 read 0x0A, cycle 4 read 0x0B, cycle 5 read
0x0A (port 1), cycle 6 port 1 idle. Every dout1 bit toggles between reads.
Inputs change T/2 + 0.3 ns before each rising edge (after the previous fall).
Probes: clk, dout1[0..3], the port-1 control nets s_en1 / wl_en1 / p_en_bar1 /
clk_buf1 inside the macro. Written to <out>/deck.sp + .spiceinit.
"""
import argparse, os
ap = argparse.ArgumentParser()
ap.add_argument("--period", type=float, required=True, help="ns")
ap.add_argument("--load", type=float, required=True, help="fF on every dout1 bit")
ap.add_argument("--out", required=True)
ap.add_argument("--corner", default="ss")
ap.add_argument("--temp", type=float, default=-40)
ap.add_argument("--vdd", type=float, default=1.76)
ap.add_argument("--slew", type=float, default=0.2, help="input edge, ns")
ap.add_argument("--threads", type=int, default=8)
a = ap.parse_args()
PDK = "/apps/cds/IC618/local/opdk/share/pdk/sky130A"
MACRO = f"{PDK}/libs.ref/sky130_sram_macros/spice/sram_1rw1r_32_256_8_sky130.spice"
T, V, S = a.period, a.vdd, a.slew
os.makedirs(a.out, exist_ok=True)

def pwl(events):
    """events: list of (time_ns, level 0/1) -> PWL string with S-ns edges."""
    pts = [(0.0, events[0][1])]
    for t, lv in events[1:]:
        pts.append((t, pts[-1][1])); pts.append((t + S, lv))
    return "PWL(" + " ".join(f"{t:.4f}n {lv*V:.3f}" for t, lv in pts) + ")"

def tset(k):  # input change time for the edge at k*T
    return k * T - T / 2 + 0.3

A, B = 0x0A, 0x0B
DA, DB = 0xA5A5A5A5, 0x5A5A5A5A
bit = lambda v, i: (v >> i) & 1
lines = [f"* {os.path.basename(a.out)}: PDK macro read at {a.corner}/{a.temp}C/{V}V, T={T} ns, load {a.load} fF, slew {S} ns",
         f'.lib "{PDK}/libs.tech/ngspice/sky130.lib.spice" {a.corner}',
         f'.include "{MACRO}"', f".temp {a.temp}", ".option klu", "Vvdd vdd 0 %.3f" % V]
# clock: rising edges at k*T (k>=1), falling at (k+0.5)*T
lines.append(f"Vclk clk 0 PULSE(0 {V} {T - S:.4f}n {S}n {S}n {T/2 - S:.4f}n {T}n)")
# port 0 (write) inputs
lines.append("Vcsb0 csb0 0 " + pwl([(0, 1), (tset(1), 0), (tset(3), 1)]))
lines.append("Vweb0 web0 0 " + pwl([(0, 1), (tset(1), 0), (tset(3), 1)]))
for i in range(4):
    lines.append(f"Vwm{i} wmask0_{i} 0 {V}")
for i in range(8):
    lines.append(f"Va0_{i} addr0_{i} 0 " + pwl([(0, bit(A, i)), (tset(2), bit(B, i))]))
for i in range(32):
    lines.append(f"Vd0_{i} din0_{i} 0 " + pwl([(0, bit(DA, i)), (tset(2), bit(DB, i))]))
# port 1 (read) inputs
lines.append("Vcsb1 csb1 0 " + pwl([(0, 1), (tset(3), 0), (tset(6), 1)]))
for i in range(8):
    lines.append(f"Va1_{i} addr1_{i} 0 " + pwl([(0, bit(A, i)), (tset(4), bit(B, i)), (tset(5), bit(A, i))]))
pins = ([f"din0_{i}" for i in range(31, -1, -1)] + [f"addr0_{i}" for i in range(7, -1, -1)] +
        [f"addr1_{i}" for i in range(7, -1, -1)] + ["csb0", "csb1", "web0", "clk", "clk"] +
        [f"wmask0_{i}" for i in range(3, -1, -1)] + [f"dout0_{i}" for i in range(31, -1, -1)] +
        [f"dout1_{i}" for i in range(31, -1, -1)] + ["vdd", "gnd"])
lines.append("Xsram " + " ".join(pins) + " sram_1rw1r_32_256_8_sky130")
for i in range(32):
    lines.append(f"CL1_{i} dout1_{i} 0 {a.load}f")
tend = 7.5 * T
probes = "v(clk) v(dout1_0) v(dout1_1) v(dout1_2) v(dout1_3) v(dout1_11) v(xsram.s_en1) v(xsram.wl_en1) v(xsram.p_en_bar1) v(xsram.clk_buf1) v(xsram.s_en0) v(xsram.wl_en0)"
lines += [f".tran 0.01n {tend:.2f}n",
          ".control", "set wr_vecnames", "set wr_singlescale", "run",
          f"wrdata {a.out}/wave.txt {probes}", "quit", ".endc", ".end"]
open(f"{a.out}/deck.sp", "w").write("\n".join(lines) + "\n")
open(f"{a.out}/.spiceinit", "w").write(f"set num_threads={a.threads}\nset ngbehavior=hs\n")
print(f"wrote {a.out}/deck.sp  (T={T} ns, load {a.load} fF, end {tend:.1f} ns)")
