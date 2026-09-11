import pya, collections
ly = pya.Layout(); ly.read("/apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds")
for cn in ["sky130_fd_sc_hd__inv_1", "sky130_fd_sc_hd__nand2_1"]:
    c = ly.cell(cn); print("==", cn)
    for li in ly.layer_indexes():
        info = ly.get_info(li); sh = c.shapes(li)
        if sh.size() == 0: continue
        texts = [(s.text_string) for s in sh.each(pya.Shapes.STexts)]
        print(f"  {info.layer}/{info.datatype}: {sh.size()} shapes, texts={texts}")
