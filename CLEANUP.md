# Repo cleanup checklist (started 2026-09-11 00:10, during the iter26b signoff runs)

Goal (see memory "repo-cleanup-refactor"): a reproducible RTL-to-signoff flow the user can run
end-to-end. This file is the working checklist; delete it when done.

## Done tonight (no git changes)
- Deleted 1,874 stray Magic `.ext` files (~3 GB): repo root (473, 09-02..09-06), `asic/` (522),
  `asic/signoff/` (456, 08-28/09-01), `asic/PnR/innovus/scripts/` (423, 09-08).
  `asic/PnR/innovus/*.ext` (671) NOT deleted: pass-4 LVS was writing there (Magic cwd).
- Root cause: `asic/signoff/lvs/run_lvs_bb.sh` runs Magic in the caller's cwd, and `extract`
  writes `<cell>.ext` per cell into cwd. Every LVS launched from a different directory leaves
  ~500 files there.

## Morning, quick (user or Claude)
1. LVS scatter fix (apply only when no `run_lvs_bb.sh` instance is running — never edit a .sh
   mid-execution): wrap the Magic call in a subshell so the .ext land in the results dir:
   `( cd "$OUT" && $MAGIC_RUN -dnull -noconsole -rcfile "$SKY130_MAGICRC" "$OUT/extract.tcl" > "$OUT/magic_extract.log" 2>&1 ) || { ... }`
   extract.tcl uses absolute paths only, so the cd is safe. Then `rm asic/PnR/innovus/*.ext`.
2. Stale tmux sessions (~150; only these carry live work: pass3_26b pass4_26b pass5_26b
   gls26b_tag10 voltus10x tempus26b9_retry). Permission classifier blocked the bulk kill; run:
   `for s in $(tmux list-sessions -F '#S'); do case $s in pass3_26b|pass4_26b|pass5_26b|gls26b_tag10|voltus10x|tempus26b9_retry) ;; *) tmux kill-session -t $s;; esac; done`
   No Innovus/Genus binaries are parked anywhere (checked 00:05); the ~20 `tail -f` monitors from
   09-04..09-07 die with their sessions.
3. Untrack tool output that is committed (files stay on disk; ~450 MB out of the 1.5 GB .git):
   - `openflex/PPA/assoc_*/outputs/*.dcp` and `route_paths.rpx` (Vivado checkpoints, 400 MB)
   - `Verification/work/` (Questa work library, 60 files)
   - `asic/signoff/icv/runs/` (three ICV attempts from 09-05)
   `git rm -r --cached <paths>` + .gitignore lines. Keep `openflex/PPA/assoc_*/cache*.csv` and
   the power/ reports (those are the README numbers).
4. Commit the campaign work (8 modified + 23 untracked, all real): Verification/Cache_gls_wrap.sv,
   Test_Complete_helpers.svh, floorplans fp_iter16/fp_iter23_quad, FLOORPLAN.md, xcelium/{.gitignore,
   GLS.md, run_gls.sh, gls_xinit_gen.py, gls_lib/}, innovus/constraints/pnr_{5p3,7}ns.sdc,
   innovus/scripts/{antenna_attach*.tcl, clk_borrow_probe.tcl, clk_skew_eco.tcl, clk_skew_ant.tcl,
   clock_report.tcl, export_tmp.sh, macro_clk_probe.tcl, pg_westvia_eco.tcl, pg_eastnorth_eco.tcl,
   route_phases.py, setupopt_experiment.tcl, usk_rerun.sh, usk_waiter.sh}. Suggested split:
   (a) GLS recipe, (b) P&R ECO scripts + constraints, (c) docs.

## Morning, needs a decision (disk: 92 GB under asic/, 12 GB xcelium/, 1.8 GB openflex/)
- `asic/PnR/innovus/runs/`: 62 GB. Keep 26b (6.5 GB, signoff lineage), 26b_tagskew10x/_pgvia9x
  (temp exports), 19b (8.5 GB, the previous quote), 26bp (table). Candidates to delete once
  their numbers are in FLOORPLAN.md/DRC.md: iter14/14b/14c (6 GB), iter16/16b/16c (6.5 GB),
  e36bpscreen, g7a/g7b/g7d, v3a/v3b, iter5 (5.5 GB), the iter26c-j table runs (5 GB),
  iter17/17b/18/20/21r/22/22b/23/24a/24b/25/25b (5 GB).
- `asic/signoff/results/`: 22 GB, per-stamp KLayout/LVS/Tempus/Voltus. Keep 26b + 19b.
- `asic/PPA/genus`: 5.2 GB of Genus work dirs (RESULTS.md holds the numbers).
- `xcelium/xcelium_gls_*.d`: six 343 MB elaboration dirs from 19b GLS experiments.
- `openflex/transcript_*_debug.log` (70 MB of Questa debug transcripts), `openflex/build_vivado` 262 MB.
- Work dirs: `work/` (root, 09-07), `asic/work` (Voltus scratch, 09-10), `asic/signoff/work`,
  `asic/signoff/voltus/work` — ~850 MB, all gitignored, all regenerable; find which script
  creates each and make it use its run dir.

## After signoff (the refactor, from the memory list)
- Fold the winning recipe into defaults (env.sh vs run_v3.sh override maze, `_PRESET_*`, dead
  knobs), pin the signoff corner in the launcher, one manifest for the three RTL file lists,
  separate live RAM_ID.sv from extra_rtl/, `signoff/collect_signoff.py` for the one-page sheet.
- Every launcher must `tee -a` its DONE marker into the log a waiter greps, and `source
  /apps/settings` before any standalone Tempus/Voltus (two overnight stalls in two days).
