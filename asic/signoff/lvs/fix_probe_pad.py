#!/usr/bin/env python3
"""fix_probe_pad.py <layout.spice>  (in place)

sky130_fd_sc_hd__probe_p_8 (CTS useful-skew delay cell) has its output pin X
on a met5 probe pad. magic's sky130A tech extracts that pad as a
sky130_fd_pr__res_generic_m5 device between the pad label X and the buffer
output node a_361_47#, so the extracted cell has SEVEN ports and the routed
net lands on a_361_47# while X is a floating pad (LVS bb run 5, 2026-09-06:
"a_361_47# = 23 | proxya_361_47# = 1", 65 net mismatch). The Verilog stub has
six pins. Rewrite the subckt header so the buffer output IS port X and the
pad becomes X_pad (netgen pairs it with a proxy pin, fanout 1 both sides);
instance calls are positional and need no change.
"""
import re, sys
p = sys.argv[1]
lines = open(p).read().split('\n')
out = []; insub = False; n = 0
for l in lines:
    if l.startswith('.subckt sky130_fd_sc_hd__probe_p_8 '):
        toks = l.split()
        if 'a_361_47#' in toks and 'X' in toks:
            toks[toks.index('X')] = 'X_pad'; toks[toks.index('a_361_47#')] = 'X'
            l = ' '.join(toks); insub = True; n += 1
    elif insub:
        if l.startswith('.ends'): insub = False
        else: l = re.sub(r'(?<![\w/])X(?![\w/#])', 'X_pad', l); l = l.replace('a_361_47#', 'X')
    out.append(l)
open(p, 'w').write('\n'.join(out))
print('fix_probe_pad: %d subckt header(s) rewritten' % n, file=sys.stderr)
