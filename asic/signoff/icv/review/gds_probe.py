import pya, sys, collections
p = sys.argv[1] if len(sys.argv) > 1 else "/ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/runs/20260902_iter16b_e35_fp16_die2900/outputs_pre_li1fix/Cache_16384B_assoc4_sram.gds"
ly = pya.Layout(); ly.read(p)
print("dbu", ly.dbu, "cells", ly.cells())
tops = [c.name for c in ly.top_cells()]; print("top cells", tops)
top = ly.top_cell()
print("top child_instances", top.child_instances())
# text count in top cell per layer
tt = collections.Counter(); ta = collections.Counter(); shp = collections.Counter(); cells_with_text = collections.Counter()
for li in ly.layer_indexes():
    info = ly.get_info(li); key = f"{info.layer}/{info.datatype}"
    n = 0
    for s in top.shapes(li).each():
        if s.is_text(): n += 1
    if n: tt[key] = n
for ci in ly.each_cell():
    for li in ly.layer_indexes():
        info = ly.get_info(li); key = f"{info.layer}/{info.datatype}"
        sh = ci.shapes(li); 
        if sh.size() == 0: continue
        shp[key] += sh.size()
        for s in sh.each(pya.Shapes.STexts):
            ta[key] += 1; cells_with_text[(key, ci.name)] += 1
print("TEXTS in top cell per layer:", dict(tt), "total", sum(tt.values()))
print("TEXTS all cells per layer:", dict(ta))
print("cells with texts (top 10):", cells_with_text.most_common(10))
for k in ["81/2","81/10","81/4","67/20","67/44","68/20","68/44","69/20","69/44","70/20","70/44","71/20","71/44","72/20","68/16","69/16","70/16","71/16","72/16","68/5","70/5","71/5"]:
    print(k, "shapes(all cells, hier sum):", shp.get(k,0))
