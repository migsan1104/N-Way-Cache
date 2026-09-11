#!/usr/bin/env python3
# make_test_gds.py -- synthetic sky130 BEOL test layout with KNOWN met1/met2
# width/spacing violations, for validating sky130_beol_min.rs (ICV) against
# KLayout.  Run:  PATH=$HOME/.local/bin:$PATH klayout -b -r make_test_gds.py
# Writes beol_test.gds next to this script (dbu 0.001 um, same as the design GDS).
#
# Every structure is >1 um from its neighbours so only the intended pair interacts.
# Expected FLAT violation counts (rule value 0.14 um, euclidean corners):
#   met1 width 1    met1 spacing 3 (S_VIOL, CORNER_VIOL, NOTCH) + 2 (SUB x2) = 5
#   met2 width 1    met2 spacing 3
# Must NOT flag: CLEAN_W (0.14 wide), CLEAN_S (0.14 gap), CORNER_CLEAN (0.10/0.10
# diagonal = 0.1414 um euclidean; a manhattan/projection check WOULD flag it).
import pya, os
ly = pya.Layout(); ly.dbu = 0.001
L = {"met1": ly.layer(68, 20), "met2": ly.layer(69, 20)}
top = ly.create_cell("TOP"); sub = ly.create_cell("SUB")
def box(cell, lay, x1, y1, x2, y2):
    cell.shapes(lay).insert(pya.DBox(x1, y1, x2, y2))
def poly(cell, lay, pts):
    cell.shapes(lay).insert(pya.DPolygon([pya.DPoint(*p) for p in pts]))
cases = {}
for name, lay in L.items():
    dy = 0.0 if name == "met1" else 20.0
    box(top, lay, 0, dy, 0.10, dy + 1.0)                     # W_VIOL   : 0.10 wide
    box(top, lay, 2, dy, 2.14, dy + 1.0)                     # CLEAN_W  : exactly 0.14 wide
    box(top, lay, 4, dy, 4.5, dy + 1.0); box(top, lay, 4.6, dy, 5.1, dy + 1.0)     # S_VIOL 0.10 gap
    box(top, lay, 7, dy, 7.5, dy + 1.0); box(top, lay, 7.64, dy, 8.14, dy + 1.0)   # CLEAN_S exactly 0.14 gap
    box(top, lay, 10, dy, 10.5, dy + 0.5); box(top, lay, 10.6, dy + 0.6, 11.1, dy + 1.1)   # CORNER_CLEAN 0.1414 eucl
    box(top, lay, 13, dy, 13.5, dy + 0.5); box(top, lay, 13.59, dy + 0.59, 14.09, dy + 1.09) # CORNER_VIOL 0.1273 eucl
    # NOTCH: U shape, arms 0.45 wide, slot 0.10 wide -> 1 same-polygon spacing violation
    poly(top, lay, [(16, dy), (17, dy), (17, dy + 1), (16.55, dy + 1), (16.55, dy + 0.3),
                    (16.45, dy + 0.3), (16.45, dy + 1), (16, dy + 1)])
# SUB: one met1 spacing violation (0.10 gap), instanced twice -> 2 flat / 1 hierarchical
box(sub, L["met1"], 0, 0, 0.5, 1.0); box(sub, L["met1"], 0.6, 0, 1.1, 1.0)
for x in (20.0, 23.0):
    top.insert(pya.DCellInstArray(sub.cell_index(), pya.DTrans(pya.DVector(x, 0))))
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "beol_test.gds")
ly.write(out); print("wrote", out)
