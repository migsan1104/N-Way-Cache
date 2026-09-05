#!/usr/bin/env python3
"""Generate lef/sram_1rw1r_32_256_8_sky130_li1obs.lef from the vendor abstract:
identical except that the OBS block gains a blanket li1 rectangle over the
macro body. Why: the vendor OBS covers met1-met4 only, so Innovus sroute
bridged the PG rails across the SRAM bodies on li1 (asic/PnR/DRC.md "li1
under the macros", 2026-09-04). The vendor file itself must stay byte-for-byte
untouched: every saved Innovus checkpoint symlinks to it and refuses to
restore (IMPIMEX-7024) if it changes. Point new runs at the generated file
with ASIC_SRAM_MACRO_LEF=<repo>/asic/PnR/innovus/lef/sram_1rw1r_32_256_8_sky130_li1obs.lef.
"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, '..', 'lef', 'sram_1rw1r_32_256_8_sky130.lef')
dst = os.path.join(here, '..', 'lef', 'sram_1rw1r_32_256_8_sky130_li1obs.lef')
t = open(src).read()
assert 'LAYER li1' not in t, 'vendor LEF already has li1 - refusing'
i = t.index('   OBS\n')
size = t[t.index('SIZE'):].split(';')[0].split()  # SIZE W BY H
w, h = size[1], size[3]
add = ('   OBS\n'
       '      # li1 blanket obstruction (Cache repo, make_li1obs_lef.py): the vendor\n'
       '      # abstract has no li1 OBS, so sroute bridged PG rails across the body.\n'
       f'      LAYER li1 ;\n         RECT 0 0 {w} {h} ;\n')
open(dst, 'w').write(t[:i] + add + t[i + len('   OBS\n'):])
print(f'wrote {os.path.normpath(dst)}: li1 OBS RECT 0 0 {w} {h}')
