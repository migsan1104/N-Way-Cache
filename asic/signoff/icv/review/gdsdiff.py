import pya
a=pya.Layout(); a.read("beol_test.gds"); b=pya.Layout(); b.read("../tests/beol_test.gds")
d=pya.LayoutDiff(); print("identical geometry:", d.compare(a,b,pya.LayoutDiff.Verbose,0))
