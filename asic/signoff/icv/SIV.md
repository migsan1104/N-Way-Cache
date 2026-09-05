# Synopsys IC Validator (ICV) for sky130 physical verification

Side project: bring up ICV as a **second DRC engine** to corroborate the KLayout
`sky130A_mr.drc` signoff (later LVS). Not on the 9/13 critical path. **No ICV rule has
executed on any layout: the installed T-2022.03 cannot check out the Apex-only manager
key on the server (section 6, 2026-09-05).** Runsets compile; fixtures, parser and README
are ready for a newer ICV install.

Files: see `README.md` (file table). Sections 1-4 below are the 2026-09-04 investigation,
sections 5-7 the dated log.

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
  -host_init <n>     local CPUs (there is NO -dp option in this ICV; review 2026-09-05)
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
        enclose(l1, l2, distance < d, extension = ...)           // l1 = ENCLOSED layer, l2 = ENCLOSING layer (icvrefman p.479)
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
| m1.4 / 791_m1.4 | mcon must be enclosed by m1; m1 enclosure of mcon 0.03 | not(mcon, met1); enclose(mcon, met1, < 0.03) |
| via.1a / via.1a_a / via.1a_b | via (outside moduleCut) rectangular; min width 0.15; max length 0.15 | as ct.1 family, on `not(via1, areaid_mt)` |
| via.2 | min via spacing : 0.17 | external1(via1, < 0.17) |
| via.4a / via.4a_a | m1 enclosure of 0.15 via 0.055; 0.15 via must be enclosed by m1 | enclose(via1, met1, < 0.055); not(via1, met1) |
| m2.1 / m2.2 | min m2 width / spacing : 0.14 (m2.3ab 0.28 for huge) | internal1 / external1 |
| via2.1a / via2.1a_a / via2.1a_b | via2 rectangular; min width 0.2; max length 0.2 | ct.1 family |
| via2.2 | min via2 spacing : 0.2 | external1(via2, < 0.2) |
| via2.4 / via2.4_a ; m3.4 | m2 enclosure of via2 0.04 ; m3 enclosure of via2 0.065 | enclose(via2, met2, < 0.04); enclose(via2, met3, < 0.065) |
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
   top cell `Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1` (the GDS file stem is not the cell name), and compare against `../drc/drc.md` (expected:
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

## 6. Log 2026-09-05 -- first execution attempt: LICENSE WALL (verified)

**Step 1 (synthetic validation) -- ICV could not execute a single rule.** Everything below
was observed by running commands; nothing is recalled from memory.

Test fixture built first (KLayout 0.30.12, `tests/make_test_gds.py` -> `tests/beol_test.gds`,
dbu 0.001 um like the design GDS): per layer (met1 68/20, met2 69/20) one 0.10 um wide wire
(width violation), one 0.10 um gap (spacing violation), one 0.09/0.09 diagonal corner pair
(euclidean 0.127, violation), one U-notch with a 0.10 um slot (same-polygon spacing
violation), and three MUST-NOT-FLAG structures: a 0.14 um wide wire, a 0.14 um gap, and a
0.10/0.10 diagonal corner pair (euclidean 0.1414 > 0.14; a manhattan/projection check would
flag it). A subcell `SUB` with one met1 0.10 um gap is placed twice, to learn how each tool
counts hierarchical errors. KLayout reference (`tests/beol_test.drc`, same
`width/space(0.14, euclidian)` idiom as `sky130A_mr.drc`), item counts:

| mode | m1.1 | m1.2 | m2.1 | m2.2 | note |
|---|---|---|---|---|---|
| deep | 1 (TOP) | 4 (TOP) + 1 (SUB) | 1 | 4 | the SUB violation is reported ONCE, in cell SUB |
| flat | 1 | 6 | 1 | 4 | SUB counted per placement |

Three violating *sites* per layer become **4 items** because the diagonal corner pair is
reported as two partial edge pairs (a vertical and a horizontal one); the 0.1414 pair and the
two exact-minimum structures are correctly silent. So even inside KLayout "item count" is not
"violation-site count"; expect the same when comparing with ICV.

ICV run (`runs/20260905_synth_test/`, command
`icv -c TOP -i ../../tests/beol_test.gds -f GDSII -host_init 1 -vue ../../sky130_beol_min.rs`):
runset compiled in 4 s, then **`License denied!`**, exit code 67, no `TOP.LAYOUT_ERRORS`.
`run_details/licmsg`:

```
Pre-Checking (ICValidator2-GeometryEngine/2022.03) ... license is installed
Requesting (ICValidator-Manager/2022.03)      ... license denied   (FlexNet -5,234 "No such feature exists")
Requesting (ICValidator-Manager-2020/2022.03) ... license denied   (FlexNet -5,234)
Unable to verify initial DP licenses.  License denied!
```

Root cause, verified:
- `lmstat -c 27020@ece-itop-licsvr.ece.ufl.edu -i` (the Calibre `lmstat` copy; `-i` works
  even though `-a`/`-f` usage queries fail with -7,10015): the server carries
  `ICValidator-Manager-Apex 2026.03 x100`, `ICValidator2-GeometryEngine 2026.03 x500`,
  `ICValidator2-CompareEngine 2026.03 x100`, `ICValidator-Live 2026.03 x400`,
  `ICValidator-Workbench x100`, `ICValidator-AddOn-ML x100`, all expiring 13-oct-2026.
  There is **no** `ICValidator-Manager` (Elite) and no `ICValidator-Manager-2020` (Base).
- The installed ICV **T-2022.03-SP3-4** only knows the Elite and Base schemes: `icv -h`
  lists `-lic_base` / `-lic_elite` only; `icv -lic_apex ...` is rejected as a usage error
  (exit 33, usage text printed, no license request made); the run above never requested
  `ICValidator-Manager-Apex`. The shipped manuals are U-2022.12 and *do* document
  `-lic_apex` and "Apex licensing is the default scheme" -- the docs are one release newer
  than the binary (`/apps/syn/icv/doc/*.pdf` dated Dec 2022, binary `cl#8146030` Nov 2022).
- The license cache `~/.cache/Synopsys/icv/license/` contained only two files, both written
  by this run (`ICValidator-Manager`, `ICValidator-Manager-2020`: `NOT_INSTALLED`), so a
  stale cache is not the cause.
- No other ICV version is installed (`/apps/syn/icv` is the only `icv*` tree under `/apps`;
  `/apps/syn/.installer` lists icc2/sentaurus/syn only).

Inferred (not verifiable here): Apex licensing was introduced between T-2022.03 and
U-2022.12, so **any ICV release >= U-2022.12 (up to the 2026.03 version the keys allow)
would check out `ICValidator-Manager-Apex` and run.** This is an IT install request, not a
configuration fix. Nothing on the client side (env var, `-keys`, cache) renames the feature.
Retry policy followed: one failed run + one informed retry (`-lic_apex`, rejected before
any license request); no further checkouts attempted.

Consequences for the plan in the task: steps 1 (execution part), 2 and the execution half
of 3 are blocked. Done instead: fixtures + KLayout reference (above), runset extended and
compiled (section 7), summary parser written against the documented LAYOUT_ERRORS format,
README. Per-rule ICV counts and run times: **none exist**.

## 7. Log 2026-09-05 (cont.) -- what was built despite the wall

Verified by running commands:
- `sky130_beol.rs` (32 rules: li.1 li.3, ct.1/1_a/1_b/2, m1.1/2, via.1a/1a_a/1a_b/2,
  m2.1/2, via2.1a/1a_a/1a_b/2, m3.1/2, via3.1/1_a/1_b/2, m4.1/2, via4.1/1_a/1_b/2, m5.1/2)
  compiles with `icv -cache-only` in 7 s, exit 0, no errors; with `-D BEOL_EXTRA` (+13:
  ct.4 m1.4 via.4a via2.4 m3.4 via3.4 m4.3 via4.4 m5.3 li.6 m1.6 m2.6 m4.4a) also 7 s,
  exit 0. Logs: `runs/20260905_compile/compile{,_extra}.log`. Every value is quoted from
  `sky130A_mr.drc` with the deck line number next to the rule (lines 894-1429 re-read
  today for li/ct/via*/m1..m5; the BEOL_EXTRA enclosure/area values are the 2026-09-04
  reading in 3.2, except via3.4 0.06 and m4.4a 0.240 re-read today).
- Function names/arguments used, each checked in the refman syntax block today:
  `internal1/external1(layer, distance < d, extension = RADIAL)`, `not_rectangles(layer)`,
  `rectangles(layer, sides = {length1 = <= L, length2 = <= L})` (constraint operators
  table 87: `<`, `<=`, `==`, ranges `[a,b]`), `not_inside(l1, l2)`, `outside(l1, l2)`,
  `not_interacting(l1, l2)`, `not/and(l1, l2)`, `area(layer, value < a)`,
  `enclose(l1, l2, distance < d, extension = RADIAL)`, `error_options(...,
  report_flat_violation_count = true)`. The `width` argument of external1 (candidate for
  the huge-metal split) was not readable in the text dump; left for later.
- Design GDS facts (KLayout read, 5 s, read-only): 454 cells, 3,037,386 instances under
  the top cell, dbu 0.001 um; hierarchical shape counts met1 2.01 M, met2 1.87 M, met3
  565 k, met4 345 k, met5 21.6 k, li1 7.7 k, mcon 5.2 k, via1 277, via2 202, via3 114,
  via4 13; `areaid_ce` 81/2 has 4 shapes (inside the macro cells), `areaid_mt` 81/10 is
  absent (so the via "outside moduleCut" selections equal the full via layers here).
- `run_icv_drc.sh`: 5th arg = CPUs via `-host_init`, refused above `ICV_MAX_CPUS` (4);
  prints a LICENSE DENIED line instead of retrying. `bash -n` clean; dry run OK; `cpus=8`
  correctly refused.
- `icv_summary.py`: parses ERROR SUMMARY / ERROR DETAILS of a LAYOUT_ERRORS file (ASCII;
  the binary PYDB is only for VUE) and, with `--klayout`, a .lyrdb. On
  `tests/fixture.LAYOUT_ERRORS` (typed from the manual's example) it returns 1/5/1/4
  and the per-structure split TOP 3 / SUB 1; on `tests/beol_test_1.lyrdb` it matches the
  direct count (1/5/1/4).

Inferred / open (ordered by how much they block "signoff-grade second engine"):
1. **License**: ICV >= U-2022.12 needed (IT). Until then nothing executes. Ask for the
   version matching the 2026.03 keys.
2. **Semantics unvalidated**: RADIAL == euclidean, `internal1` == width, corner-pair and
   notch counting, `rectangles(sides)` as max-length -- all from the manual only. The
   fixture + expected table in README "Validation plan" settles them in one 30-min run.
3. **Huge-metal split** (m1.3ab/m2.3ab/m3.3cd/m4.*) not translated; the small-value check
   over-reports huge-vs-narrow pairs below the small value and misses pairs between the
   small and the huge value. Needs ICV edge layers or `external1(width = ...)`.
4. **Two-adjacent-edge enclosures** (li.5, m1.5, via.5a, via2.5, via3.5), ring vias, and
   the s8-cell exemptions: not started (3.3 items 3, 4, 6).
5. **Macro waiver**: the 16 OpenRAM macros produce ~155 k KLayout items that the sheet
   waives by location; ICV needs either a cell-based exclusion (`error_options(pcell_list)`
   / a `not()` against a macro-box layer) or post-filtering of bboxes with the
   `classify_lyrdb.py` geometry. Not implemented.
6. **Run time**: unknown; KLayout needs 4.6 h / 16 threads for the full BEOL deck on this
   GDS, and ICV is capped at 4 CPUs here. Time one rule (`-svc "m3.*"`) first.
7. **Count semantics**: item vs site vs flat vs hierarchical (section 6 table) -- compare
   per rule and by location; never by grand total.

No design job was launched; nothing outside `asic/signoff/icv/` was written (the
`/tmp/x` dry-run target was never created because dry runs do not mkdir). No tmux
sessions were used. License checkouts attempted: one (denied); the `-lic_apex` retry was
rejected by the binary before contacting the server.

## 8. Review 2026-09-05 (review/REVIEW_2026-09-05.md) — corrections applied

A1 enclose() argument order (enclosed first, enclosing second) fixed in both
runsets and in sections 2/3.2; A2 run_icv_drc.sh now survives an icv failure
(set +e around the pipeline) so the exit code, the license guard and the
LAYOUT_ERRORS head actually print; A3 `-dp` does not exist, `-host_init` is
the CPU knob; A4 top cell name corrected in section 4; A5 an older ICV
L-2016.06 exists at /apps/syn/validator (does not change the license
conclusion). Open, minor: A6 m1_4/via_4a simplifications (noted in the
runset), A7 line-number and count typos in SIV_LVS.md. All 36 rule values,
all layer numbers, the width/spacing/RADIAL semantics, the synthetic-test
counts and the license facts were re-verified by the reviewer.
