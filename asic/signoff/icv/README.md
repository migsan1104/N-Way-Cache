# ICV (Synopsys IC Validator) as a second DRC engine -- sky130A

Status 2026-09-05: **scaffolding complete, execution blocked by licensing.** The installed
ICV `T-2022.03-SP3-4` requests the `ICValidator-Manager` (Elite) or `-Manager-2020` (Base)
key; the UF server (`27020@ece-itop-licsvr.ece.ufl.edu`) carries only
`ICValidator-Manager-Apex 2026.03` (100 seats) plus the Geometry/Compare engines. Apex
support arrived after this release, so **no rule can execute until IT installs ICV
>= U-2022.12** (any release up to 2026.03 works with the keys present). Details and
evidence: `SIV.md` section 6. Everything below is ready for that day; the runsets compile
today with `icv -cache-only`.

## Run ICV on any GDS from this repo (3 commands)

```bash
cd /ecel/UFAD/miguel.sanchez1/Cache/asic/signoff/icv
mkdir -p runs/$(date +%Y%m%d)_beol && cd runs/$(date +%Y%m%d)_beol      # ICV writes into $PWD
bash -lc 'source /apps/settings && icv -c "*" -i <layout.gds> -f GDSII -host_init 4 -vue ../../sky130_beol.rs'
```

- `-c "*"` auto-detects the top cell (or give it: `-c Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1`
  for the iter16b GDS). `-i` takes GDS or gzipped GDS. `-f GDSII`.
- `-host_init N` = local CPUs. **Cap: 4** (one Apex key covers 4 CPUs; Innovus signoff
  jobs use 16 of the 128 cores and must not be starved). This ICV has no `-dp` option.
- `-D BEOL_EXTRA` adds the enclosure / coverage / min-area block of `sky130_beol.rs`.
- `-svc "m3.2*"` / `-uvc "li.*"` run / skip violation blocks by comment; `-cache-only`
  compiles only (no manager license needed -- this works today).
- Or use the wrapper: `./run_icv_drc.sh --run <gds> <topcell|*> [runset] [run_dir] [cpus<=4]`
  (prints the command without `--run`; refuses cpus > `ICV_MAX_CPUS`, default 4; flags
  "License denied" instead of retrying).
- Never run from a directory outside `icv/runs/`: ICV drops `run_details/`, `<cell>.*`,
  `.icv_cmd`, `icv.log` into the current directory. Never run two jobs in one run dir.
- `bash -lc` (login shell, needed for `/apps/settings`) runs the site profile, which drops a
  Cadence `cds.lib` template into the current directory if none exists. Run it from the
  run dir, never from a directory that matters, and delete the stray file if it appears.
- Background jobs: tmux session named `icv_<something>` only (the `iter*`, `chain*`,
  `tempus*`, `voltus*`, `kl_*`, `li1_*` names belong to the main flow).

## Outputs (per icvug1.pdf ch. 3; layout below the RESULTS line is documented, not yet seen here)

| file | content |
|---|---|
| `<cell>.LAYOUT_ERRORS` | first line `LAYOUT ERRORS RESULTS: CLEAN|ERRORS`; `ERROR SUMMARY` (rule comment, function, count, flat count with `report_flat_violation_count`); `ERROR DETAILS` (structure name + bbox per error, hierarchical: once per cell definition) |
| `<cell>.RESULTS` | run summary (written even on the license-denied run) |
| `<cell>.sum`, `<cell>.err` | log sorted in runset order; exit code on failure |
| `<cell>.vue`, `run_details/pydb` | error database for `icv_vue` (GUI) / `icv_pydb`, `pydb_report` |
| `run_details/licmsg` | license negotiation -- read this first when a run stops early |
| `run_details/<runset>.dp.log` | distributed-processing log |

## Comparing with KLayout

```bash
python3 icv_summary.py runs/<dir>/<cell>.LAYOUT_ERRORS            # per-rule counts (add --details for per-cell breakdown, --csv)
python3 icv_summary.py --klayout ../results/<stamp>/klayout_drc/drc.lyrdb   # same table from KLayout
python3 ../drc/classify_lyrdb.py <drc.lyrdb> --die 2900 --edge 40  # KLayout in/out-of-macro split
```

`icv_summary.py` parses the ASCII LAYOUT_ERRORS (it is text, not binary; the binary
PYDB is only for VUE). It was tested on `tests/fixture.LAYOUT_ERRORS`, a file typed from
the manual's example -- adjust the two regexes at the top on first contact with a real file.

What to expect when the numbers are compared (learned from the KLayout side, `SIV.md` 6):
1. **Item counts are not site counts.** KLayout reports a diagonal corner violation as two
   partial edge pairs; ICV `external1` returns error regions. Compare per rule and by
   location, not by grand total.
2. **Hierarchy.** KLayout `deep` reports a violation inside a cell once, in that cell
   (`tests/beol_test.gds`: SUB placed twice -> 1 deep item, 2 flat). ICV is hierarchical by
   default and prints both counts when `report_flat_violation_count = true`; compare the
   flat count with KLayout flat, the hierarchical one with `deep`.
3. **The huge-metal split** (m1.2 vs m1.3ab etc.) is not translated: ICV checks the whole
   layer at the small value (see CAVEAT-HUGE in `sky130_beol.rs`).
4. **Error limits**: `error_limit_per_check = 100000` in ICV, none in KLayout; the iter16b
   in-macro li.3 count (79,927) is below the limit, but check `ERROR SUMMARY` for
   "limit reached" text.
5. **Macros**: KLayout's 155k in-macro items are foundry-waived OpenRAM bitcell patterns.
   ICV has no macro waiver here yet; use `../drc/classify_lyrdb.py`'s box geometry on
   the ICV bboxes (same die 2900 / edge 40 / 16 macro boxes) or `-uvc` to skip li/ct
   rules until an `areaid`-style exclusion layer is added to the runset.

## Files

| file | what |
|---|---|
| `SIV.md` | inventory, manual digest, rule table, dated log (sections 5-7) |
| `sky130_beol_min.rs` | 4 rules (m1.1 m1.2 m2.1 m2.2), compiles |
| `sky130_beol.rs` | 32 rules: li.1 li.3 ct.1 ct.1_a ct.1_b ct.2 m1.1 m1.2 via.1a via.1a_a via.1a_b via.2 m2.1 m2.2 via2.1a via2.1a_a via2.1a_b via2.2 m3.1 m3.2 via3.1 via3.1_a via3.1_b via3.2 m4.1 m4.2 via4.1 via4.1_a via4.1_b via4.2 m5.1 m5.2; `-D BEOL_EXTRA` adds 13 (ct.4 m1.4 via.4a via2.4 m3.4 via3.4 m4.3 via4.4 m5.3 li.6 m1.6 m2.6 m4.4a); compiles both ways |
| `run_icv_drc.sh` | guarded runner (dry-run by default, CPU cap, license-denied guard) |
| `icv_summary.py` | per-rule counts from LAYOUT_ERRORS or a KLayout .lyrdb |
| `tests/make_test_gds.py`, `tests/beol_test.gds` | synthetic met1/met2 fixture with known violations (KLayout 0.30.12) |
| `tests/beol_test.drc`, `tests/beol_test_{0,1}.lyrdb` | KLayout reference on the fixture: flat / deep |
| `tests/fixture.LAYOUT_ERRORS` | hand-written LAYOUT_ERRORS in the manual's format, for the parser |
| `runs/20260905_synth_test*/` | the two license-denied attempts (`run_details/licmsg` is the evidence) |
| `runs/20260905_compile/` | `icv -cache-only` logs for `sky130_beol.rs` with and without `BEOL_EXTRA` |

## Validation plan once a license works (30 min)

1. `cd runs/<date>_synth && icv -c TOP -i ../../tests/beol_test.gds -f GDSII -host_init 1 -vue ../../sky130_beol_min.rs`
2. `python3 ../../icv_summary.py TOP.LAYOUT_ERRORS --details` must give m1.1 = 1, m2.1 = 1,
   m2.2 = 3 sites (S_VIOL, CORNER_VIOL, NOTCH; KLayout says 4 items), m1.2 = those 3 + SUB
   (1 hierarchical / 2 flat), and NOTHING for CLEAN_W (0.14 wide), CLEAN_S (0.14 gap) and
   CORNER_CLEAN (0.10/0.10 diagonal, 0.1414 euclidean). If CORNER_CLEAN flags, `RADIAL`
   is not the euclidean mode and the runset must change.
3. Then the design GDS with `-host_init 4` and `sky130_beol.rs`, from `runs/<date>_beol/`.
   No runtime estimate exists; KLayout took 4.6 h / 16 threads for the whole BEOL deck on
   the same 3.0 M-instance GDS. Start with `-svc "m3.*"` (the smallest layer, 565 k
   shapes) to time one rule before launching all 32.
