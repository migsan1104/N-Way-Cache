// sky130_beol_min.rs -- minimal SKY130A BEOL DRC runset for Synopsys IC Validator (PXL)
//
// *** UNTESTED ON A LAYOUT *** -- written 2026-09-04 from the ICV T-2022.03 manuals
// (icvug1.pdf, icvrefman.pdf). Status: compiles cleanly with `icv -cache-only`
// (2026-09-04, no layout loaded, no rule executed). Never run against a GDS.
// See SIV.md in this directory for the source of every number and function name.
//
// Scope: 4 rules only -- met1 width/space, met2 width/space -- as a smoke test of
// the runset skeleton. Values come from the PDK's KLayout deck
// (libs.tech/klayout/drc/sky130A_mr.drc): m1.1/m1.2 = 0.14 um, m2.1/m2.2 = 0.14 um.
//
// Simplifications versus the KLayout deck (intentional for a first run):
//   * m1.2 / m2.2 in the deck exclude "huge" (>=3 um wide) metal edges, which get
//     0.28 um (m1.3ab / m2.3ab). Here every edge is checked at 0.14 um, so wide
//     power straps next to a signal wire may report spacing violations that the
//     deck would classify under m1.3ab instead. Expect extra flags, not misses.
//   * extension = RADIAL is the ICV analogue of the deck's "euclidian" corner mode
//     (see external1()/internal1() "extension" argument in icvrefman.pdf).
//
// Usage (see run_icv_drc.sh):  icv -c <topcell> -i <layout.gds> sky130_beol_min.rs
// -c / -i override the cell / library_name below (icvug1.pdf, "General Command-Line Options").

// The PXL function library. Without this line every function (library, assign,
// internal1, ...) and enum (GDSII, RADIAL) is undefined -- confirmed with
// `icv -cache-only` on 2026-09-04. The file lives at $ICV_HOME/include/icv.rh.
#include <icv.rh>

// ---------------------------------------------------------------------------
// 1. Layout database (library() is required; -c/-i/-f on the command line override it)
// ---------------------------------------------------------------------------
library(
    library_name = "layout.gds",   // placeholder -- overridden by -i
    format       = GDSII,
    cell         = "TOP"           // placeholder -- overridden by -c
);

// ---------------------------------------------------------------------------
// 2. Options
// ---------------------------------------------------------------------------
error_options(
    error_limit_per_check = 1000,
    report_error_details  = true,
    create_vue_output     = true   // writes <cell>.vue for icv_vue debugging
);

// ---------------------------------------------------------------------------
// 3. Layer assignment: sky130A GDS layer/datatype (drawing purpose only)
//    Numbers verified 2026-09-04 against libs.tech/klayout/tech/sky130A.map and
//    the *_wildcard strings in sky130A_mr.drc.
// ---------------------------------------------------------------------------
li1  = assign({{layer_num_range = 67, data_type_range = 20}});
mcon = assign({{layer_num_range = 67, data_type_range = 44}});
met1 = assign({{layer_num_range = 68, data_type_range = 20}});
via1 = assign({{layer_num_range = 68, data_type_range = 44}});
met2 = assign({{layer_num_range = 69, data_type_range = 20}});
via2 = assign({{layer_num_range = 69, data_type_range = 44}});
met3 = assign({{layer_num_range = 70, data_type_range = 20}});
via3 = assign({{layer_num_range = 70, data_type_range = 44}});
met4 = assign({{layer_num_range = 71, data_type_range = 20}});
via4 = assign({{layer_num_range = 71, data_type_range = 44}});
met5 = assign({{layer_num_range = 72, data_type_range = 20}});

// ---------------------------------------------------------------------------
// 4. Rules.  Width  = internal1()  (inside-to-inside, one layer)
//            Spacing = external1() (outside-to-outside, one layer)
//    Each rule is a "@=" violation block with an "@" comment; the comment is the
//    rule name that appears in <cell>.LAYOUT_ERRORS and that -svc/-uvc select on.
// ---------------------------------------------------------------------------

m1_1 @= { @ "m1.1 : min. m1 width : 0.14um";
    internal1(met1, distance < 0.14, extension = RADIAL);
}

m1_2 @= { @ "m1.2 : min. m1 spacing : 0.14um";
    external1(met1, distance < 0.14, extension = RADIAL);
}

m2_1 @= { @ "m2.1 : min. m2 width : 0.14um";
    internal1(met2, distance < 0.14, extension = RADIAL);
}

m2_2 @= { @ "m2.2 : min. m2 spacing : 0.14um";
    external1(met2, distance < 0.14, extension = RADIAL);
}

// Next rules to add once the four above run clean on a known-good GDS
// (values from sky130A_mr.drc, see SIV.md section 4):
//   li.1/li.3 0.17   ct.2 0.19   via.2 0.17   via2.2 0.20   m3.1/m3.2 0.30
//   via3.2 0.20      m4.1/m4.2 0.30   via4.2 0.80   m5.1/m5.2 1.60
//   enclosures: via2.4 met2>via2 0.04, m3.4 met3>via2 0.065, via3.4 met3>via3 0.06,
//               m4.3 met4>via3 0.065, via4.4 met4>via4 0.19, m5.3 met5>via4 0.31
//               -> enclose(viaY, metX, distance < v, extension = RADIAL)  (enclosed first, enclosing second - icvrefman p.479)
//   coverage:   ct.4 / m1.4 / via2.4_a ... -> not(viaY, metX) must be empty
