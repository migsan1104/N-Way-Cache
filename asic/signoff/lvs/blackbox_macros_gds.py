#!/usr/bin/env python3
"""blackbox_macros_gds.py <in.gds> <macro.lef> <out.gds> [macro_name]

KLayout batch script (run via `klayout -b -r blackbox_macros_gds.py -rd ...`):
replace the SRAM macro cell's content in a P&R GDS with a pin-only abstract
built from its LEF, so magic extracts it as an empty black box.

Why (2026-09-06, lvs.md run 3): `lef read` + `gds noduplicates true` did NOT
keep magic's LEF abstract - the extracted macro subckt had 918 ports and the
OpenRAM internals (bank_0, control_logic, dffs), whose magic extraction
shorts vdd/gnd/signal terminals ("Ports D_uq76 and vdd are electrically
shorted", 816 warnings). Through the 16 macros that merged VPWR and VGND
into ONE top-level node and pulled every net on a macro pin into it,
including the 17 top-level pins wired straight to SRAM address/data ports
(cpu_req_addr[2..6], cpu_req_valid, mem_resp_rdata[12,13,15,25,30] ...),
so netgen lost 16 of the 216 ports and failed pin matching.

What it writes for the macro cell: one rectangle per LEF PIN PORT rect on
the layer's DRAWING datatype (20) plus a text label with the pin name on
the PIN datatype (16, which magic's tech reads as a port) at the rect centre; OBS is dropped. Different pins'
rects must not touch on a layer (checked; the script exits 1 if they do).
Unused subcells of the old content are pruned. Usage from run_lvs_bb.sh.
Options via -rd: IN, LEF, OUT, MACRO (default from the LEF's MACRO line).
"""
import pya, re, sys, itertools

GDS_LAYER = {'li1': 67, 'met1': 68, 'met2': 69, 'met3': 70, 'met4': 71, 'met5': 72}
DRAW, LABEL = 20, 16   # magic sky130A cifinput: 'labels METnPIN port' (dt 16) -> subckt ports; dt 5 is plain text

def parse_lef(path):
    txt = open(path).read()
    m = re.search(r'^\s*MACRO\s+(\S+)', txt, re.M)
    name = m.group(1)
    body = txt[m.start():]
    pins = {}; cur = None; lay = None; inobs = False; nobs = 0
    for ln in body.splitlines():
        s = ln.strip()
        m = re.match(r'PIN\s+(\S+)', s)
        if m: cur = m.group(1); pins[cur] = []; continue
        if re.match(r'END\s+' + re.escape(cur or '\0'), s): cur = None; continue
        if s.startswith('OBS'): inobs = True; continue
        if inobs and s == 'END': inobs = False; continue
        m = re.match(r'LAYER\s+(\S+)', s)
        if m: lay = m.group(1); continue
        m = re.match(r'RECT\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)', s)
        if m:
            r = (lay, *map(float, m.groups()))
            if inobs: nobs += 1
            elif cur: pins[cur].append(r)
    return name, pins, nobs

def touch(a, b):
    return a[0] == b[0] and a[1] <= b[3] and b[1] <= a[3] and a[2] <= b[4] and b[2] <= a[4]

def main():
    name, pins, nobs = parse_lef(LEF)
    macro = globals().get('MACRO') or name
    nrect = sum(len(v) for v in pins.values())
    print("LEF %s: %d pins, %d pin rects, %d OBS rects dropped" % (macro, len(pins), nrect, nobs))
    bad = [(p, q) for p, q in itertools.combinations(pins, 2)
           if any(touch(r, s) for r in pins[p] for s in pins[q])]
    if bad:
        print("ERROR: pin rects of different pins touch on the same layer:", bad[:10]); sys.exit(1)
    ly = pya.Layout(); ly.read(IN)
    cell = ly.cell(macro)
    if cell is None:
        print("ERROR: no cell %s in %s" % (macro, IN)); sys.exit(1)
    top = ly.top_cell()
    ninst = sum(1 for c in ly.each_cell() for i in c.each_inst() if i.cell.name == macro)
    before = cell.bbox()
    cell.clear()
    dbu = ly.dbu
    for p, rects in pins.items():
        for (lay, x1, y1, x2, y2) in rects:
            gl = GDS_LAYER[lay]
            li = ly.layer(pya.LayerInfo(gl, DRAW)); ll = ly.layer(pya.LayerInfo(gl, LABEL))
            cell.shapes(li).insert(pya.DBox(x1, y1, x2, y2))
            cell.shapes(ll).insert(pya.DText(p, pya.DTrans(pya.DVector((x1 + x2) / 2, (y1 + y2) / 2))))
    ncells = ly.cells()
    # drop the cells no longer reachable from the top (the old macro internals)
    keep = set(top.called_cells()) | {top.cell_index()}
    ly.delete_cells([c.cell_index() for c in ly.each_cell() if c.cell_index() not in keep])
    print("macro %s: %d instances, bbox %s -> %s; cells %d -> %d" %
          (macro, ninst, before.to_s(), cell.bbox().to_s(), ncells, ly.cells()))
    ly.write(OUT)
    print("wrote", OUT)

main()
