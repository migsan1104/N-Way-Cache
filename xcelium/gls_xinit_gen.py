#!/usr/bin/env python3
"""gls_xinit_gen.py - X-initialisation Tcl for a post-layout GLS (GLS.md, 2026-09-08).

The E29 reset-free arrays (word_valid/dirty/tag banks, RS fields, refill_*)
power up X in gate-level sim; the RTL hides that with if(X)=false optimism,
the UDP cell models propagate it and it sticks (X & ~X) until it reaches
cpu_req_ready and the testbench spins. Silicon powers up random, not X, and
allocated=0 masks it. Recipe that runs clean (19b io91e/io91f full PASS):
hold the DUT clock low for 60 ns, deposit 0 on every flop Q and 1 on every
Q_N at 1 ns, release the clock, then hold the refill_* pipeline flops at 0
for a further 120 ns and release them.

The list is regenerated from the run's own *_pnr_sim.v because place-and-route
renames flop output nets (FE_OFN* fanout buffers), so a list from another run
silently deposits nothing.

  gls_xinit_gen.py <pnr_sim.v> <hier scope of the netlist instance> <out.tcl>
"""
import re, sys

net, scope, out = sys.argv[1:4]
CLK = "Test_Complete.clk_dut"      # the DUT clock in both TB clock modes (GLS_IO_LATENCY or not)
FLOP = re.compile(r"^\s*(sky130_fd_sc_hd__(?:s?df\w*|dl\w*|edf\w*))\s+(\\\S+\s|\S+)\s*\((.*)$", re.S)
PIN = re.compile(r"\.(\w+)\s*\(([^()]*)\)")


def netname(raw):
    """Verilog escaped identifiers end at whitespace; xmsim (PVLEND) rejects one
    without it. Keep '\\a.b ' and '\\a.b [3]' (escaped name, then a bit select)."""
    v = raw.strip()
    if v.startswith("\\") and " " not in v:
        v += " "
    return v
REFILL = re.compile(r"refill_(?:rd_wv|stage_tag|stage_v)_r_reg")

dep, force = [], []
text = open(net).read()
body = text[text.index("\nmodule "):] if "\nmodule " in text else text
for stmt in body.split(";"):
    m = FLOP.match(stmt)
    if not m:
        continue
    inst = m.group(2)
    for pin, raw in PIN.findall(m.group(3)):
        val = netname(raw)
        if not val or val.startswith("1'b"):
            continue
        if pin == "Q":
            dep.append((val, 0))
            if REFILL.search(inst):
                force.append(val)
        elif pin == "Q_N":
            dep.append((val, 1))

def path(v):
    return "{%s.%s}" % (scope, v)

with open(out, "w") as f:
    w = f.write
    w("set nf 0; set ne 0\n")
    w('if {[catch {force %s = 0} m]} {puts "CLK FORCE ERR: $m"} else {puts "== XINIT: clk held low"}\n' % CLK)
    w("run 1ns\n")
    w("set nd 0; set de 0\n")
    for v, b in dep:
        w('if {[catch {deposit %s = %d} m]} {incr de; if {$de<4} {puts "DEPOSIT ERR: $m"}} else {incr nd}\n' % (path(v), b))
    w('puts "== XINIT: deposited $nd of %d flop outputs ($de errors)"\n' % len(dep))
    w("run 59ns\n")
    w("catch {release %s}\n" % CLK)
    w('puts "== XINIT: clk released at 60ns"\n')
    for v in force:
        w('if {[catch {force %s = 0} m]} {incr ne; if {$ne<4} {puts "FORCE ERR: $m"}} else {incr nf}\n' % path(v))
    w('puts "== XINIT: forced $nf refill flops ($ne errors) for 120ns"\n')
    w("run 120ns\n")
    for v in force:
        w("catch {release %s}\n" % path(v))
    w('puts "== XINIT: running full suite to \$finish"\n')
    w("run\n")
    w('puts "== XINIT: sim finished"\n')
    w("exit\n")
print("xinit: %d deposits (%d Q, %d Q_N), %d refill forces -> %s" %
      (len(dep), sum(1 for _, b in dep if b == 0), sum(1 for _, b in dep if b == 1), len(force), out))
