# Synopsys IC Validator (ICV) for sky130 physical verification

Side project: bring up ICV as a **second DRC engine** to corroborate the KLayout
`sky130A_mr.drc` signoff (later LVS). Not on the 9/13 critical path. Everything in this
directory is investigation and scaffolding; **no ICV job has been run on a design**.

Files: `SIV.md` (this), `sky130_beol_min.rs` (4-rule PXL runset, untested),
`run_icv_drc.sh` (wrapper; dry-run unless `--run`).

## 1. Tool inventory (verified 2026-09-04)

| Item | Value |
|---|---|
| ICV | `IC Validator Version T-2022.03-SP3-4 for linux64 - Nov 21, 2022 cl#8146030` (`icv -V`) |
| Install | `ICV_HOME=/apps/syn/icv`, `ICVWB_HOME=/apps/syn/icv_workbench` (from `/apps/settings`); `/apps/syn/icv/bin` is on PATH after sourcing |
| Executables | `icv`, `icv64`, `icv_batch`, `icv_vue`/`icv_vue64` (error viewer), `icv_lvsdb`, `icv_netlist`, `icv_nettran`, `icv_lvl` (layout-vs-layout), `icv_dashboard`, `icv_ecofill`, `icv_lidb*`, `icv_pydb`/`pydb_report`, `pxlcrypt`, `icvl_icvwb_client`, `icvl_virtuoso_client`, plus `dcv_*` and `generate_route_guidance` |
| Docs | `/apps/syn/icv/doc/icvug1.pdf` (User Guide U-2022.12, 34 chapters/appendices), `icvrefman.pdf` (Reference Manual, ~135k text lines), `icvlvsug.pdf` (LVS User Guide). `pdftotext` is at `/usr/bin/pdftotext`; no python PDF libs |
| License server | `SNPSLMD_LICENSE_FILE=27020@ece-itop-licsvr.ece.ufl.edu`, FlexNet v11.19.7, `snpslmd` UP (queried with `/apps/siemens/calibre/current/bin/lmstat`; no lmstat/lmutil under `/apps/syn`) |
| ICV features present in the license file | `ICValidator-Manager-Apex`, `ICValidator2-GeometryEngine`, `ICValidator2-CompareEngine`, `ICValidator-Live`, `ICValidator-Workbench`, `ICValidator-AddOn-ML`. **Not** present: `ICValidator-Manager` (Elite), `ICValidator-Manager-2020` (Base) |
| Feature counts / availability | **Partly verified.** `lmstat -f <feature>` returns `Cannot get users of ...: No socket connection to license server manager (-7,10015)` for every feature on the server (1052 of 1066 lines of `lmstat -a`), so counts are unknown. But `icv -cache-only` (compile only) logs `Pre-Checking (ICValidator2-GeometryEngine/2022.03) ... license is installed` in `run_details/licmsg`, i.e. ICV reaches the server and finds the DRC engine feature. An actual checkout (Manager-Apex + GeometryEngine) has not happened yet |
| Also in `$ICV_HOME/contrib` | `cal2pxl` (Calibre SVRF -> PXL translator, v7.7, with `cal2pxl_user_guide.pdf`), `runsetgen`, `icv_antenna_runset_gen.pl`, `icc2pxl.tcl`, `PXL/`, `pydb2ascii` |

Per `icvug1.pdf` ch. 2 "Which IC Validator Licenses Do I Need?": a run always checks out
one Manager key (Apex tier here) plus `ICValidator2-GeometryEngine` for DRC and
`ICValidator2-CompareEngine` for LVS. Apex is the highest tier, so the feature set is not a
limitation; the count is the unknown.

## 2. How ICV is run (from the manuals; not exercised)

Command line (`icvug1.pdf` "Command-Line Options"; confirmed by `icv -h`):

```
icv [options] <runset.rs>
  -c <cell>|*        override library(cell=...)   ('*' = auto-detect top cell)
  -i <library>       override library(library_name=...)
  -f <format>        GDSII | LTL | MILKYWAY | NDM | OASIS | OPENACCESS
  -vue               create VUE output (<cell>.vue)
  -D name[=val]      runset #define
  -svc/-uvc "cmt"    run only / skip violation blocks whose @ comment matches
  -svn/-uvn name     same by @= violation name
  -dp <n>            cores (multicore licensing)
  -cache-only        compile the runset and stop (no execution)
  -ece               exit code EXIT_COMPLETE_WERROR when errors exist
```

So a DRC is `icv -c <topcell> -i <layout.gds> -f GDSII -vue sky130_beol_min.rs`.
GDS/OASIS may be gzipped (auto-detected). ICV writes into the **current directory**:

- `<cell>.LAYOUT_ERRORS` -- first line `LAYOUT ERRORS RESULTS: CLEAN` or `ERRORS`, then an
  ERROR SUMMARY (comment, function, count) and ERROR DETAILS (structure, bbox) per rule
- `<cell>.sum` (summary/log), `<cell>.err` (exit code on failure), `<cell>.rules`
  (rules actually executed) and everything else under `run_details/`
- `<cell>.vue` with `-vue` or `error_options(create_vue_output=true)`, for `icv_vue`

Minimal runset skeleton (function names and argument names quoted from `icvrefman.pdf`).
The first line is mandatory: without `#include <icv.rh>` (`$ICV_HOME/include/icv.rh`) the
compiler reports `no function 'library' exists`, `'GDSII' is not defined`, etc. -- 33 errors
on the first compile attempt of `sky130_beol_min.rs`.

```
#include <icv.rh>                                                // PXL function library
library(library_name = "x.gds", format = GDSII, cell = "TOP");   // required, first
error_options(error_limit_per_check = 1000, report_error_details = true);
met1 = assign({{layer_num_range = 68, data_type_range = 20}});   // GDS layer/datatype
m1_1 @= { @ "m1.1 : min. m1 width : 0.14um";                     // @= name, @ comment
    internal1(met1, distance < 0.14, extension = RADIAL); }      // width
m1_2 @= { @ "m1.2 : min. m1 spacing : 0.14um";
    external1(met1, distance < 0.14, extension = RADIAL); }      // spacing, 1 layer
        external2(l1, l2, distance < d, extension = ...)         // spacing, 2 layers
        enclose(l1, l2, distance < d, extension = ...)           // l1 must enclose l2
        not(l1, l2) / and(l1, l2) / or(l1, l2) / xor(l1, l2)     // booleans
        area(l, value < a)                                       // min area
```

There is **no `width()` function**; width is `internal1()` (inside-to-inside, same
polygon) and spacing is `external1()`. `extension = RADIAL` is the Euclidean corner
measurement matching the deck's `euclidian`. Results of a rule function inside a `@=`
block go to the error database under that block's `@` comment; `-svc`/`-uvc` select on it.

## 3. sky130 runset plan

### 3.1 Layer map (verified against `libs.tech/klayout/tech/sky130A.map`, `.lyt`, and the `*_wildcard` strings in `sky130A_mr.drc`)

| layer | GDS | layer | GDS | | |
|---|---|---|---|---|---|
| li1 | 67/20 | mcon | 67/44 | met1 | 68/20 |
| via (via1) | 68/44 | met2 | 69/20 | via2 | 69/44 |
| met3 | 70/20 | via3 | 70/44 | met4 | 71/20 |
| via4 | 71/44 | met5 | 72/20 | licon1 | 66/44 |

Also used by the deck: `areaid_ce` 81/2 (core area; changes li/mcon/via rules inside it),
`areaid_mt` 81/10 (moduleCut; exempts vias), `areaid_sl` 81/1 (seal ring), `capm` 89/44,
`cap2m` 97/44. The `.lyt` maps `met1='68/20+68/5-68/14-68/15'` etc. for display, but the
DRC deck itself reads plain `68/20`, so the runset does too. Pin (x/16) and label (x/5)
datatypes are not read.

### 3.2 First-scope rules (22) and their deck values

All from `sky130A_mr.drc` (release `2024.2.11_01.09`), BEOL section, `backend_flow = AL`.

| Rule | Deck description | ICV translation |
|---|---|---|
| li.1 / li.3 | min li width / spacing **outside or crossing areaid:ce** : 0.17 | internal1/external1 on `not(li1, areaid_ce)`; inside core (li.7/li.8) it is 0.14 |
| ct.1 | non-ring mcon must be rectangular | `not_rectangles(mcon)` |
| ct.1_a / ct.1_b | mcon min width 0.17 / **max length 0.17** (exact square) | internal1 < 0.17 plus a max-length check (see 3.3) |
| ct.2 | min mcon spacing : 0.19 | external1(mcon, < 0.19) |
| ct.4 | mcon should be covered by li | `not(mcon_not_ce, li1)` non-empty = error |
| m1.1 / m1.2 | min m1 width / spacing : 0.14 | internal1 / external1 (m1.2 excludes >=3 um "huge" edges; those get m1.3ab 0.28) |
| m1.4 / 791_m1.4 | mcon must be enclosed by m1; m1 enclosure of mcon 0.03 | not(mcon, met1); enclose(met1, mcon, < 0.03) |
| via.1a / via.1a_a / via.1a_b | via (outside moduleCut) rectangular; min width 0.15; max length 0.15 | as ct.1 family, on `not(via1, areaid_mt)` |
| via.2 | min via spacing : 0.17 | external1(via1, < 0.17) |
| via.4a / via.4a_a | m1 enclosure of 0.15 via 0.055; 0.15 via must be enclosed by m1 | enclose(met1, via1, < 0.055); not(via1, met1) |
| m2.1 / m2.2 | min m2 width / spacing : 0.14 (m2.3ab 0.28 for huge) | internal1 / external1 |
| via2.1a / via2.1a_a / via2.1a_b | via2 rectangular; min width 0.2; max length 0.2 | ct.1 family |
| via2.2 | min via2 spacing : 0.2 | external1(via2, < 0.2) |
| via2.4 / via2.4_a ; m3.4 | m2 enclosure of via2 0.04 ; m3 enclosure of via2 0.065 | enclose(met2, via2, < 0.04); enclose(met3, via2, < 0.065) |
| m3.1 / m3.2 | min m3 width / spacing : 0.3 (m3.3cd 0.4 for huge) | internal1 / external1 |
| via3.1 / via3.1_a / via3.1_b | via3 rectangular; min width 0.2; max length 0.2 | ct.1 family |
| via3.2 | min via3 spacing : 0.2 | external1(via3, < 0.2) |
| via3.4 ; m4.3 | m3 enclosure of via3 0.06 ; m4 enclosure of via3 0.065 | enclose() |
| m4.1 / m4.2 | min m4 width / spacing : 0.3 ; m4.4a min area 0.240 | internal1 / external1 ; area() |
| via4.1 / via4.1_a / via4.1_b | via4 rectangular; min width 0.8; max length 0.8 | ct.1 family |
| via4.2 | min via4 spacing : 0.8 | external1(via4, < 0.8) |
| via4.4 ; m5.3 | m4 enclosure of via4 0.19 ; m5 enclosure of via4 0.31 | enclose() |
| m5.1 / m5.2 | min m5 width / spacing : 1.6 | internal1 / external1 |

Also in the deck and worth carrying over early: min-area m1.6 0.083, m2.6 0.0676, li.6
0.0561; hole-area m1.7 / m2.7 0.14. The two-adjacent-edge enclosure rules (li.5, m1.5,
via.5a, via2.5, via3.5 ...) come later. Our KLayout signoff currently flags exactly this
family on the iter16b GDS: m3.2, via3.2, ct.1_b, ct.2 (see `../drc/drc.md`), so these are
the rules that matter for corroboration.

### 3.3 Deck features that are hard to translate

1. **"huge" metal split** -- `m = m.sized(-1.5).sized(1.5).snap(0.005) & m`, then spacing
   is 0.14 for normal edges and 0.28 (0.4 on m3) for edges of >=3 um-wide metal. ICV needs
   `size()` + `and()` to build the huge layer, then `external1()` twice with edge
   selection, or the `width` argument of `external1()`. Not obvious; first version checks
   everything at the small value (over-reports on power straps).
2. **Exact-square vias** -- `drc(width < 0.17)` plus `drc(length > 0.17)` /
   `edges.without_length(nil, 0.2 + 1.dbu)` express "min width and max length". ICV has no
   direct max-length rule; candidates are `internal1()` with `distance > x`, or
   `not_rectangles()` plus `edge_length()`-style filtering. Needs the refman.
3. **Two-adjacent-edge enclosure** (li.5, m1.5, via.5a, via2.5, via3.5): the deck builds
   `enclosing(..., projection).second_edges`, measures `width(angle_limit(100.0), 1.dbu)`
   on the resulting edges and selects vias `interacting` those corners. ICV's `enclose()`
   has `corner_configuration`/`orthogonal` arguments that probably express this directly,
   but it is a different formulation and must be validated on a test structure.
4. **Cell-name-scoped rules** -- `layout(source.cell_obj).select("-s8cell_ee_...")` exempts
   specific SRAM cells from m1.4 (0.005 vs 0.03). ICV has cell-selection via
   `error_options(pcell_list)`/cell filters; likely irrelevant for our design (no s8 cells).
5. **Region layers** `areaid_ce`, `areaid_mt`, `areaid_sl` change rule values by region.
   Plain `not()`/`and()` handles it, but our GDS may not carry `areaid` at all -- then
   everything is "periphery" and the core-only 0.14 li rules never apply.
6. **Ring-shaped vias** (`drc(with_holes > 0)`) under `SEAL` only -- skip.
7. **Hierarchical vs flat** -- KLayout runs `deep`; ICV is hierarchical by default
   (`processing_mode = HIERARCHICAL`), so error counts will differ per cell vs per
   instance. Compare `report_flat_violation_count = true` against KLayout's counts.
8. **Units** -- KLayout deck values are microns with `1.dbu` tolerances; ICV distances
   are also microns by default, but the `+ 1.dbu` slack on max-length rules must be
   reproduced (a 0.2000 via must not fail `length > 0.2`).

Alternative route: `$ICV_HOME/contrib/cal2pxl` translates a Calibre SVRF runset to PXL
automatically. The open PDK ships **no SVRF DRC deck** (the only `*.calibre` files under
`libs.tech/openlane/` are OpenRCX extraction rules), so this only helps if a Calibre
sky130 deck is obtained elsewhere; the hand translation above is the default path.

## 4. Status / next steps

Status: inventory done, manuals read, 4-rule runset drafted and **compiled** with
`icv -cache-only` (clean after adding `#include <icv.rh>`); no layout has been loaded and no
rule has executed. `run_icv_drc.sh` dry-run mode verified (prints the command, exits 0).

1. `--run` on a tiny synthetic GDS (a few met1/met2 rectangles with known violations) to
   (a) confirm the license checks out, (b) shake out PXL syntax, (c) learn the
   `LAYOUT_ERRORS` format. Then compare against KLayout on the same file.
2. Run on the iter16b top GDS
   (`asic/PnR/innovus/runs/20260902_iter16b_e35_fp16_die2900/outputs/Cache_16384B_assoc4_sram.gds`),
   top cell `Cache_16384B_assoc4_sram`, and compare against `../drc/drc.md` (expected:
   1 m3.2, 2 via3.2 inside via masters, ct.1_b/ct.2 column at x=1460).
3. Grow the runset to the 22 rules in 3.2, then min-area, then the adjacent-edge family.
4. LVS: `icvlvsug.pdf`; needs device recognition for sky130 (FEOL layers) -- far off.

## 5. Log

**2026-09-04** (Claude, side-project investigation; ~1 h; no design jobs launched)

Verified by running commands:
- `icv -V` and `icv -h` from `/apps/syn/icv/bin` after `source /apps/settings`:
  version T-2022.03-SP3-4, option list as in section 2. Neither call produced a license
  error (they do not check one out).
- `ls /apps/syn/icv/bin`, `ls /apps/syn/icv/doc`: executables and the three PDFs.
- `lmstat` (Calibre copy) against 27020@ece-itop-licsvr: server and `snpslmd` UP; the six
  `ICValidator*` feature names above appear in the server's feature list; every usage
  query fails with `-7,10015`. Counts unknown.
- `sky130A.map` / `sky130A.lyt` / `sky130A_mr.drc` wildcards: layer numbers in 3.1.
- `sky130A_mr.drc` rule bodies: every value in 3.2 was read from the deck, not recalled.
- `pdftotext` of `icvug1.pdf` and `icvrefman.pdf` (scratch copies, not in repo): the
  command-line table, `library()`, `assign()`, `error_options()`, `run_options()`,
  `internal1()`, `external1()`, `external2()`, `enclose()`, `not()`, `and()` syntax
  blocks, the `@`/`@=` violation-block examples, and the LAYOUT_ERRORS example in ch. 3.
- A 0-byte `asic/signoff/icv.RESULTS` (stamped 20:32 today, before this investigation)
  was found and left alone; it is not from this work.

- `icv -cache-only sky130_beol_min.rs` run twice from the scratch directory (no layout,
  nothing written into the repo): first attempt 33 type-analysis errors (`no function
  'library' exists`, `'GDSII' is not defined`, `'RADIAL' is not defined`) because the
  runset lacked `#include <icv.rh>`; second attempt after adding it: `Parsing finished`,
  compile 7 s, exit 0. Both runs logged the `ICValidator2-GeometryEngine ... license is
  installed` pre-check, so the compile path does talk to the license server.
- `run_icv_drc.sh` without `--run`: prints the command and exits 0 (`bash -n` clean).

Inferred, not verified:
- That `internal1(... , distance < w, extension = RADIAL)` is the right width idiom and
  `external1` the right spacing idiom (both compile; the guide shows
  `internal1(local_var, distance < 0.2)` but never labels it "width"). Only a run on a
  GDS with known violations settles semantics.
- That `-vue` and `create_vue_output` coexist, and that `<cell>.LAYOUT_ERRORS` lands in
  `$PWD` (the guide says so for the Custom Compiler flow).
- Whether a full run actually checks out `ICValidator-Manager-Apex` (only the
  GeometryEngine pre-check was observed) and how many seats exist.
