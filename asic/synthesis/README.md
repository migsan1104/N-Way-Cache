# Synthesis sources

Tool-invariant inputs and the two tool-specific Tcl flows.

```text
common/
  scripts/project_config.tcl     shared parameters, PDK paths, per-run output dirs
  filelists/rtl_files.tcl        RTL dependency list, lowest-level first
  constraints/golden.sdc         THE constraint set - both tools read this file
cadence/scripts/run_genus.tcl    Genus flow (physically aware: LEF + floorplan + PLE)
synopsys/scripts/run_dc.tcl      Design Compiler flow (wire-load fallback)
```

`golden.sdc` is the single source of timing constraints. Neither flow defines a
clock, an I/O delay or a design rule of its own, and neither regenerates a
derived SDC. If you need to change the target, change that file. It currently
declares **no timing exceptions**, deliberately.

Both Tcl flows source `project_config.tcl` first; it defines `REPORT_DIR`,
`NETLIST_DIR`, `DB_DIR`, `WORK_DIR`, `LOG_DIR` and `RUN_TAG` for the selected
tool and associativity. Every run writes into its own stamped directory,
`asic/PPA/<tool>/assoc_<N>/runs/<stamp>/`, with a `runs/latest` symlink; nothing
writes outside `asic/PPA/<tool>/assoc_<N>/`.

The two flows use the same signoff corner (`sky130_fd_sc_hd__ss_n40C_1v28`), the
same clock, and the same excluded library cells. They differ in one respect:
Genus estimates interconnect from LEF geometry and a floorplan, while DC falls
back to Liberty wire load models because this PDK ships no Milkyway/NDM physical
libraries. Each run's `summary.rpt` records which was used.

Run them through `asic/run_genus.sh` and `asic/run_dc.sh` rather than invoking
the Tcl directly — the launchers set the environment the configuration reads.
See `../README.md`.
