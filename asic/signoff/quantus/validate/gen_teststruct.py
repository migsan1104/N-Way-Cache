#!/usr/bin/env python3
"""Validation test structure for the sky130A QRC techfile (README "Validation").

Writes teststruct.v + teststruct.def: for each metal layer one isolated
50 x 50 um plate and one 1000 um minimum-width wire, each on its own net with
its own pin, far apart, nothing else on the die. Extracted total cap per net is
then a pure capacitance-to-substrate number that can be checked against the
tech LEF's CPERSQDIST (area) and EDGECAPACITANCE (perimeter), and Quantus's R on
the wire against Rsq * L / W.

    python3 gen_teststruct.py            # writes into this directory
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LAYERS = {  # name: (min width um, LEF area cap aF/um^2, LEF edge cap aF/um, Rsq)
    "met1": (0.14, 25.7784, 40.567, 0.125),
    "met2": (0.14, 16.9423, 37.759, 0.125),
    "met3": (0.30, 12.3729, 40.989, 0.047),
    "met4": (0.30, 8.41537, 36.676, 0.047),
    "met5": (1.60, 6.32063, 38.851, 0.0285),
}
PLATE = 50.0      # um square
WIRE_LEN = 1000.0 # um
# mid-width wires: Techgen's width tables only reach ~1.4-2.4 um (work_nom/jobs
# logs), so the 50 um plate is an EXTRAPOLATION; these sit inside the modelled
# range and separate area cap from fringe honestly (added 2026-08-30).
# Net names m<10*width>_<layer> (m10_, m20_, m16_ for met5) - no dots in Verilog ids.
MID_WIDTHS = [1.0, 2.0]
DBU = 1000        # DEF units per um
DIE = 3000.0      # um square die

nets = []
for i, (lay, (w, *_)) in enumerate(LAYERS.items()):
    # plate: a single segment of width PLATE and length PLATE via a nondefault rule
    x0, y0 = 200.0 + i * 500.0, 300.0
    nets.append(("p_" + lay, lay, PLATE, [(x0, y0 + PLATE / 2), (x0 + PLATE, y0 + PLATE / 2)]))
    # wire: minimum width, WIRE_LEN long, in the upper half of the die
    x1, y1 = 200.0 + i * 500.0, 1500.0
    nets.append(("w_" + lay, lay, w, [(x1, y1), (x1, y1 + WIRE_LEN)]))
    for k, mw in enumerate(MID_WIDTHS):
        mw = max(mw, w)
        x2 = x1 + 100.0 * (k + 1)
        nets.append(("m%d_%s" % (int(round(mw * 10)), lay), lay, mw, [(x2, y1), (x2, y1 + WIRE_LEN)]))


def u(v):
    return int(round(v * DBU))


with open(os.path.join(HERE, "teststruct.v"), "w") as f:
    ports = ", ".join(n[0] for n in nets)
    f.write("module teststruct(%s);\n" % ports)
    for n in nets:
        f.write("  input %s;\n" % n[0])
    f.write("endmodule\n")

with open(os.path.join(HERE, "teststruct.def"), "w") as f:
    f.write("VERSION 5.8 ;\nDIVIDERCHAR \"/\" ;\nBUSBITCHARS \"[]\" ;\n")
    f.write("DESIGN teststruct ;\nUNITS DISTANCE MICRONS %d ;\n" % DBU)
    f.write("DIEAREA ( 0 0 ) ( %d %d ) ;\n\n" % (u(DIE), u(DIE)))
    # one nondefault rule per plate width, per layer
    ndrs = sorted({(lay, w) for _, lay, w, _ in nets if w != LAYERS[lay][0]})
    f.write("NONDEFAULTRULES %d ;\n" % len(ndrs))
    for lay, w in ndrs:
        f.write("- ndr_%s_%d + LAYER %s WIDTH %d ;\n" % (lay, u(w), lay, u(w)))
    f.write("END NONDEFAULTRULES\n\n")
    f.write("PINS %d ;\n" % len(nets))
    for name, lay, w, pts in nets:
        (x, y) = pts[0]
        # pin = a minimum-width square regardless of the net's wire width:
        # a plate-sized pin is a second 50x50 shape on top of the routed one
        # (Quantus counts both -> 2x cap, R/2; found 2026-08-30).
        hw = u(LAYERS[lay][0]) // 2
        f.write("- %s + NET %s + DIRECTION INPUT + USE SIGNAL\n" % (name, name))
        f.write("  + LAYER %s ( %d %d ) ( %d %d ) + PLACED ( %d %d ) N ;\n"
                % (lay, -hw, -hw, hw, hw, u(x), u(y)))
    f.write("END PINS\n\n")
    f.write("NETS %d ;\n" % len(nets))
    for name, lay, w, pts in nets:
        f.write("- %s ( PIN %s )" % (name, name))
        if w != LAYERS[lay][0]:
            f.write(" + NONDEFAULTRULE ndr_%s_%d" % (lay, u(w)))
        f.write("\n  + ROUTED %s ( %d %d ) ( %d %d ) ;\n"
                % (lay, u(pts[0][0]), u(pts[0][1]), u(pts[1][0]), u(pts[1][1])))
    f.write("END NETS\n\nEND DESIGN\n")

# expected values from the LEF model, for compare.py
with open(os.path.join(HERE, "expected_lef.csv"), "w") as f:
    f.write("net,layer,area_um2,perim_um,C_lef_fF,R_ohm\n")
    for name, lay, w, pts in nets:
        L = abs(pts[1][0] - pts[0][0]) + abs(pts[1][1] - pts[0][1])
        area = L * w
        perim = 2 * (L + w)
        _, ca, ce, rsq = LAYERS[lay]
        c_ff = (area * ca + perim * ce) / 1000.0
        r = rsq * L / w
        f.write("%s,%s,%.1f,%.1f,%.4f,%.3f\n" % (name, lay, area, perim, c_ff, r))
print("wrote teststruct.v, teststruct.def, expected_lef.csv in", HERE)
