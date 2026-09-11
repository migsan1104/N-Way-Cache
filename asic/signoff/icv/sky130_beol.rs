// sky130_beol.rs -- SKY130A BEOL width / spacing / via-size DRC runset for Synopsys
// IC Validator (PXL).  Superset of sky130_beol_min.rs.
//
// *** COMPILED ONLY (icv -cache-only), NEVER EXECUTED ON A LAYOUT ***
// 2026-09-05: the installed ICV T-2022.03-SP3-4 cannot check out the only manager key
// on the license server (ICValidator-Manager-Apex 2026.03); see SIV.md section 6.
// Every function/argument name below is quoted from icvrefman.pdf (U-2022.12); every
// rule value is quoted from the PDK KLayout deck
//   /apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.tech/klayout/drc/sky130A_mr.drc
// (release 2024.2.11_01.09, BEOL section, backend_flow = AL, SEAL = false), with the
// deck line quoted next to each rule.  Translation caveats are marked CAVEAT.
//
// Usage:  icv -c <topcell> -i <layout.gds> -f GDSII -host_init <N<=4> [-D BEOL_EXTRA] sky130_beol.rs
//   BEOL_EXTRA adds enclosure / coverage / min-area rules (section 6) that were NOT asked
//   for in the first scope; they compile but their translation is unvalidated.

#include <icv.rh>

// ---------------------------------------------------------------------------
// 1. Layout database (overridden by -c / -i / -f)
// ---------------------------------------------------------------------------
library(library_name = "layout.gds", format = GDSII, cell = "TOP");

// ---------------------------------------------------------------------------
// 2. Options.  KLayout has no per-rule error limit; 100000 keeps the ASCII file
//    bounded but is above every KLayout per-rule count seen on iter16b (max li.3 79,927
//    inside the macros).  report_flat_violation_count adds a flat count (errors in a
//    cell x placements) to the ERROR SUMMARY, which is what KLayout "flat" mode counts.
// ---------------------------------------------------------------------------
error_options(
    error_limit_per_check       = 100000,
    report_error_details        = true,
    report_flat_violation_count = true,
    create_vue_output           = true
);

// ---------------------------------------------------------------------------
// 3. Layers (GDS layer/datatype verified against libs.tech/klayout/tech/sky130A.map).
//    Present in the iter16b design GDS (KLayout read, 2026-09-05): 67/20, 67/44, 68/20,
//    68/44, 69/20, 69/44, 70/20, 70/44, 71/20, 71/44, 72/20, and areaid_ce 81/2 (4 shapes,
//    i.e. inside the vendor SRAM macro cells).  areaid_mt 81/10 is ABSENT, so the
//    "outside moduleCut" via selections are the whole via layers on this design.
// ---------------------------------------------------------------------------
li1       = assign({{layer_num_range = 67, data_type_range = 20}});
mcon      = assign({{layer_num_range = 67, data_type_range = 44}});
met1      = assign({{layer_num_range = 68, data_type_range = 20}});
via1      = assign({{layer_num_range = 68, data_type_range = 44}});
met2      = assign({{layer_num_range = 69, data_type_range = 20}});
via2      = assign({{layer_num_range = 69, data_type_range = 44}});
met3      = assign({{layer_num_range = 70, data_type_range = 20}});
via3      = assign({{layer_num_range = 70, data_type_range = 44}});
met4      = assign({{layer_num_range = 71, data_type_range = 20}});
via4      = assign({{layer_num_range = 71, data_type_range = 44}});
met5      = assign({{layer_num_range = 72, data_type_range = 20}});
areaid_ce = assign({{layer_num_range = 81, data_type_range = 2}});    // core area
areaid_mt = assign({{layer_num_range = 81, data_type_range = 10}});   // moduleCut

// ---------------------------------------------------------------------------
// 4. Derived layers (deck constructions, translated)
// ---------------------------------------------------------------------------
// deck: li_outside_or_touching_areaidce = li.outside(areaid_ce) | li.interacting(areaid_ce).not(li.inside(areaid_ce))
//       == li polygons that are not entirely inside areaid_ce  -> not_inside()
li_peri     = not_inside(li1, areaid_ce);
// deck: rectMCON = mcon (SEAL=false); rectMCON_peri = rectMCON.outside(areaid_ce)  (polygon selection)
mcon_peri   = outside(mcon, areaid_ce);
// deck: via_not_mt = via.not(areaid_mt)   (geometric NOT)
via1_not_mt = not(via1, areaid_mt);
via2_not_mt = not(via2, areaid_mt);
via3_not_mt = not(via3, areaid_mt);
via4_not_mt = not(via4, areaid_mt);

// ---------------------------------------------------------------------------
// 5. Rules.   width   = internal1(layer, distance < w, extension = RADIAL)
//             spacing = external1(layer, distance < s, extension = RADIAL)
//    RADIAL = euclidean corner region = the deck's "euclidian" (icvrefman external1()
//    "extension" argument).  A pair at exactly the minimum is not < w, so it passes,
//    as in KLayout.
//    CAVEAT-HUGE: the deck checks m1.2/m2.2/m3.2/m4.2 on NON-huge edges only (metal
//    < 3 um wide) and huge edges at 0.28/0.28/0.40/0.40 (m1.3ab, m2.3ab, m3.3cd, m4.3?).
//    Here the whole layer is checked at the small value: every deck m1.2 site is found,
//    plus huge-vs-anything pairs between 0 and 0.14 (the deck files those under m1.3ab);
//    huge pairs between 0.14 and 0.28 are MISSED.  Needs an edge-layer formulation.
//    CAVEAT-MAXLEN: "maximum length" (exact-square vias) has no direct ICV rule; it is
//    expressed as "via polygons that are not rectangles with both sides <= L", so a
//    non-rectangular via is flagged twice (under .1 and .1_b).  KLayout's via2/via3
//    variant uses 0.2 + 1.dbu (dbu 0.001) -> 0.201 here; ct/via/via4 use plain > L.
// ---------------------------------------------------------------------------

// ---- li (67/20) ----
// deck 894-901: li_outside_or_touching_areaidce.width(0.17, euclidian) / .space(0.17, euclidian)
li_1 @= { @ "li.1 : min. li width outside or crossing areaid:ce : 0.17um";
    internal1(li_peri, distance < 0.17, extension = RADIAL); }
li_3 @= { @ "li.3 : min. li spacing outside or crossing areaid:ce : 0.17um";
    external1(li_peri, distance < 0.17, extension = RADIAL); }

// ---- mcon (67/44) ----
// deck 945-960: rectMCON.non_rectangles ; rectMCON_peri.drc(width < 0.17) ;
//               rectMCON_peri.drc(length > 0.17) ; mcon.space(0.19, euclidian)
ct_1 @= { @ "ct.1: non-ring mcon should be rectangular";
    not_rectangles(mcon); }
ct_1_a @= { @ "ct.1_a : minimum width of mcon : 0.17um";
    internal1(mcon_peri, distance < 0.17, extension = RADIAL); }
ct_1_b @= { @ "ct.1_b : maximum length of mcon : 0.17um";
    not(mcon_peri, rectangles(mcon_peri, sides = {length1 = <= 0.17, length2 = <= 0.17})); }
ct_2 @= { @ "ct.2 : min. mcon spacing : 0.19um";
    external1(mcon, distance < 0.19, extension = RADIAL); }

// ---- met1 (68/20) ----
// deck 980: m1.width(0.14, euclidian) ; 986: non_huge_m1.space(0.14, euclidian)
m1_1 @= { @ "m1.1 : min. m1 width : 0.14um";
    internal1(met1, distance < 0.14, extension = RADIAL); }
m1_2 @= { @ "m1.2 : min. m1 spacing : 0.14um";                    // CAVEAT-HUGE
    external1(met1, distance < 0.14, extension = RADIAL); }

// ---- via (68/44) ----
// deck 1076-1092: via_not_mt.non_rectangles ; via_not_mt.width(0.15, euclidian) ;
//                 via_not_mt.drc(length > 0.15) ; via.space(0.17, euclidian)
via_1a @= { @ "via.1a : via outside of moduleCut should be rectangular";
    not_rectangles(via1_not_mt); }
via_1a_a @= { @ "via.1a_a : min. width of via outside of moduleCut : 0.15um";
    internal1(via1_not_mt, distance < 0.15, extension = RADIAL); }
via_1a_b @= { @ "via.1a_b : maximum length of via : 0.15um";
    not(via1_not_mt, rectangles(via1_not_mt, sides = {length1 = <= 0.15, length2 = <= 0.15})); }
via_2 @= { @ "via.2 : min. via spacing : 0.17um";
    external1(via1, distance < 0.17, extension = RADIAL); }

// ---- met2 (69/20) ----
// deck 1137: m2.width(0.14, euclidian) ; 1145: non_huge_m2.space(0.14, euclidian)
m2_1 @= { @ "m2.1 : min. m2 width : 0.14um";
    internal1(met2, distance < 0.14, extension = RADIAL); }
m2_2 @= { @ "m2.2 : min. m2 spacing : 0.14um";                    // CAVEAT-HUGE
    external1(met2, distance < 0.14, extension = RADIAL); }

// ---- via2 (69/44) ----
// deck 1202-1216: via2_not_mt.non_rectangles ; via2_not_mt.width(0.2, euclidian) ;
//                 via2_not_mt.edges.without_length(nil, 0.2 + 1.dbu) ; via2.space(0.2, euclidian)
via2_1a @= { @ "via2.1a : via2 outside of moduleCut should be rectangular";
    not_rectangles(via2_not_mt); }
via2_1a_a @= { @ "via2.1a_a : min. width of via2 outside of moduleCut : 0.2um";
    internal1(via2_not_mt, distance < 0.2, extension = RADIAL); }
via2_1a_b @= { @ "via2.1a_b : maximum length of via2 : 0.2um";
    not(via2_not_mt, rectangles(via2_not_mt, sides = {length1 = < 0.201, length2 = < 0.201})); }
via2_2 @= { @ "via2.2 : min. via2 spacing : 0.2um";
    external1(via2, distance < 0.2, extension = RADIAL); }

// ---- met3 (70/20) ----
// deck 1253: m3.width(0.3, euclidian) ; 1260: non_huge_m3.space(0.3, euclidian)
m3_1 @= { @ "m3.1 : min. m3 width : 0.3um";
    internal1(met3, distance < 0.3, extension = RADIAL); }
m3_2 @= { @ "m3.2 : min. m3 spacing : 0.3um";                     // CAVEAT-HUGE (0.4 for huge)
    external1(met3, distance < 0.3, extension = RADIAL); }

// ---- via3 (70/44) ----
// deck 1300-1315: via3_not_mt.non_rectangles ; via3_not_mt.width(0.2, euclidian) ;
//                 via3_not_mt.edges.without_length(nil, 0.2 + 1.dbu) ; via3.space(0.2, euclidian)
via3_1 @= { @ "via3.1 : via3 outside of moduleCut should be rectangular";
    not_rectangles(via3_not_mt); }
via3_1_a @= { @ "via3.1_a : min. width of via3 outside of moduleCut : 0.2um";
    internal1(via3_not_mt, distance < 0.2, extension = RADIAL); }
via3_1_b @= { @ "via3.1_b : maximum length of via3 : 0.2um";
    not(via3_not_mt, rectangles(via3_not_mt, sides = {length1 = < 0.201, length2 = < 0.201})); }
via3_2 @= { @ "via3.2 : min. via3 spacing : 0.2um";
    external1(via3, distance < 0.2, extension = RADIAL); }

// ---- met4 (71/20) ----
// deck 1339: m4.width(0.3, euclidian) ; 1346: non_huge_m4.space(0.3, euclidian)
m4_1 @= { @ "m4.1 : min. m4 width : 0.3um";
    internal1(met4, distance < 0.3, extension = RADIAL); }
m4_2 @= { @ "m4.2 : min. m4 spacing : 0.3um";                     // CAVEAT-HUGE
    external1(met4, distance < 0.3, extension = RADIAL); }

// ---- via4 (71/44) ----
// deck 1386-1401: via4_not_mt.non_rectangles ; rectVIA4.width(0.8, euclidian) ;
//                 rectVIA4.drc(length > 0.8) ; via4.space(0.8, euclidian).polygons
via4_1 @= { @ "via4.1 : via4 outside of moduleCut should be rectangular";
    not_rectangles(via4_not_mt); }
via4_1_a @= { @ "via4.1_a : min. width of via4 outside of moduleCut : 0.8um";
    internal1(via4, distance < 0.8, extension = RADIAL); }
via4_1_b @= { @ "via4.1_b : maximum length of via4 : 0.8um";
    not(via4, rectangles(via4, sides = {length1 = <= 0.8, length2 = <= 0.8})); }
via4_2 @= { @ "via4.2 : min. via4 spacing : 0.8um";
    external1(via4, distance < 0.8, extension = RADIAL); }

// ---- met5 (72/20) ----
// deck 1427: m5.width(1.6, euclidian) ; 1429: m5.space(1.6, euclidian)  (no huge split on m5)
m5_1 @= { @ "m5.1 : min. m5 width : 1.6um";
    internal1(met5, distance < 1.6, extension = RADIAL); }
m5_2 @= { @ "m5.2 : min. m5 spacing : 1.6um";
    external1(met5, distance < 1.6, extension = RADIAL); }

// ---------------------------------------------------------------------------
// 6. OPTIONAL (-D BEOL_EXTRA): enclosure / coverage / min-area.  Values were read from
//    the deck on 2026-09-04 (SIV.md 3.2). enclose(layer1, layer2, distance < d):
//    layer1 is the ENCLOSED layer (the via), layer2 the ENCLOSING one (the metal)
//    -- icvrefman p.479; argument order was reversed until the 2026-09-05 review
//    (review/REVIEW_2026-09-05.md A1). Unvalidated translation.
//    Known simplifications (review A6): m1_4 checks all mcon (deck: mcon outside
//    areaid_ce, i.e. over-reports inside the SRAM cores); via_4a checks all via1
//    (deck: only 0.15-wide via1).
// ---------------------------------------------------------------------------
#ifdef BEOL_EXTRA
ct_4 @= { @ "ct.4 : mcon should covered by li";
    not(not(mcon, areaid_ce), li1); }
m1_4 @= { @ "m1.4 : mcon must be enclosed by m1";
    not(mcon, met1); }
via_4a @= { @ "via.4a : min. m1 enclosure of 0.15 via : 0.055um";
    enclose(via1, met1, distance < 0.055, extension = RADIAL); }
via2_4 @= { @ "via2.4 : min. m2 enclosure of via2 : 0.04um";
    enclose(via2, met2, distance < 0.04, extension = RADIAL); }
m3_4 @= { @ "m3.4 : min. m3 enclosure of via2 : 0.065um";
    enclose(via2, met3, distance < 0.065, extension = RADIAL); }
via3_4 @= { @ "via3.4 : min. m3 enclosure of via3 : 0.06um";      // deck 1318 (read 2026-09-05)
    enclose(via3, met3, distance < 0.06, extension = RADIAL); }
m4_3 @= { @ "m4.3 : min. m4 enclosure of via3 : 0.065um";
    enclose(via3, met4, distance < 0.065, extension = RADIAL); }
via4_4 @= { @ "via4.4 : min. m4 enclosure of via4 : 0.19um";
    enclose(via4, met4, distance < 0.19, extension = RADIAL); }
m5_3 @= { @ "m5.3 : min. m5 enclosure of via4 : 0.31um";
    enclose(via4, met5, distance < 0.31, extension = RADIAL); }
li_6 @= { @ "li.6 : min. li area : 0.0561um2";
    area(not_interacting(li1, areaid_ce), value < 0.0561); }
m1_6 @= { @ "m1.6 : min. m1 area : 0.083um2";
    area(met1, value < 0.083); }
m2_6 @= { @ "m2.6 : min. m2 area : 0.0676um2";
    area(met2, value < 0.0676); }
m4_4a @= { @ "m4.4a : min. m4 area : 0.240um2";                    // deck 1351
    area(met4, value < 0.240); }
#endif
