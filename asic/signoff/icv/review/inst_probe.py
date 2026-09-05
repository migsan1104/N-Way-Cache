import pya, collections, time
t=time.time()
p="/ecel/UFAD/miguel.sanchez1/Cache/asic/PnR/innovus/runs/20260902_iter16b_e35_fp16_die2900/outputs_pre_li1fix/Cache_16384B_assoc4_sram.gds"
ly = pya.Layout(); ly.read(p); top = ly.top_cell()
c = collections.Counter()
for inst in top.each_inst():
    c[ly.cell(inst.cell_index).name] += inst.size()
print("read+count s", round(time.time()-t,1), "total flat placements under top", sum(c.values()))
def tot(pat): return sum(v for k,v in c.items() if pat in k)
for pat in ["decap_3","decap_6","decap_12","decap","fill_2","fill_","tapvpwrvgnd","diode_2","sram_1rw1r","M1M2_PR","L1M1_PR","inv_2"]:
    print(pat, tot(pat))
print("distinct child cells", len(c))
# top-cell pin polygons on x/16 and 69/20 texts per cell
for k in ["68/16","69/16","70/16","71/16","72/16"]:
    l,d = map(int,k.split("/")); li = ly.find_layer(l,d)
    print("top", k, "shapes", top.shapes(li).size() if li is not None else None)
li = ly.find_layer(69,20)
for ci in ly.each_cell():
    n = sum(1 for s in ci.shapes(li).each(pya.Shapes.STexts))
    if n: print("69/20 texts in", ci.name, n)
for k in ["22/21","22/22","33/42","33/43","66/83"]:
    l,d = map(int,k.split("/")); li = ly.find_layer(l,d)
    print(k, "present" if li is not None else "absent")
