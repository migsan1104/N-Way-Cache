# ASIC Flow

Logical synthesis of the parameterized cache onto SKY130 standard cells, with
Cadence Genus and Synopsys Design Compiler driven from one shared configuration.

This is **logical synthesis only**. There is no floorplanning, placement, CTS,
routing, extraction, or signoff here, and no physical libraries (LEF/GDS) are
installed — only the timing/area views.

## Quick start

```bash
source /apps/settings          # puts genus, dc_shell and lc_shell on PATH

cd asic
./run_genus.sh 4               # Genus,  ASSOC=4
./run_dc.sh 4                  # DC,     ASSOC=4
./collect_ppa.py               # print the PPA table for each tool
```

Both launchers default to `ASSOC=8` when no argument is given, and resolve all
paths from their own location, so they work from any working directory.

## Configuration

`synthesis/common/scripts/project_config.tcl` holds the baseline and is shared by
both tools. Three knobs are overridable per run, so no file edit is needed to
sweep:

| Variable | Default | Set by |
|---|---|---|
| `ASIC_ASSOC` | 8 | first positional argument |
| `ASIC_CLOCK_PERIOD_NS` | 2.000 | second positional argument |
| `ASIC_CACHE_BYTES` | 4096 | environment only |

```bash
./run_dc.sh 4 2.500                  # ASSOC=4 at a 2.500 ns target
ASIC_CACHE_BYTES=8192 ./run_dc.sh 8  # 8 KB cache
```

Everything else — clock/reset port names, uncertainty (0.100 ns), and I/O delay
(0.200 ns) — lives in `project_config.tcl` and the shared SDC.

## Where results land

Each tool gets its own tree, and each associativity its own folder inside it:

```text
asic/PPA/
  RESULTS.md                     collected tables (tracked in git)
  genus/assoc_<N>/
    reports/   netlist/   work/   logs/
  dc/assoc_<N>/
    reports/   netlist/   work/   logs/
```

Netlists are named `Cache_<bytes>B_assoc<N>_mapped.v`, so artifacts from
different configurations can never be confused with one another.

**Each run works inside its own `work/` directory.** That is what keeps the tools
from scattering `command.log`, `default.svf`, `alib-*`, `genus.log`, and
`moduleparamid` into the repository root, and it is also why two configurations
can be synthesized concurrently without corrupting each other.

## Sweeping

```bash
./sweep.sh                      # both tools, ASSOC 1 2 4 8 16, sequential
./sweep.sh -t dc -a "4 8"       # DC only, two associativities
./sweep.sh -j 5                 # up to 5 configurations at once
```

Concurrency is safe by construction; the real limit is how many tool licenses
are free. A sweep finishes by printing the collected tables.

## Reading the results

```bash
./collect_ppa.py                        # both tools
./collect_ppa.py --tool dc              # one tool
./collect_ppa.py --markdown PPA/RESULTS.md
```

The collector parses each tool's `qor`, `area`, and `power` reports and reduces
them to the same columns, so the two tools can be compared directly. Achievable
Fmax is derived as `1000 / (target_period - WNS)` — the target is deliberately
aggressive, so this is the frequency the design actually reaches, not the
constraint.

Genus reports timing in picoseconds and DC in nanoseconds; the collector
normalizes both to nanoseconds.

## Cleaning up

```bash
./clean.sh          # drop work databases and logs, keep reports and netlists
./clean.sh --all    # drop the whole PPA tree
./clean.sh -n       # dry run
```

Only `PPA/RESULTS.md` is tracked in git; every other artifact under `PPA/` is
regenerable and ignored.

## Standard-cell library

The corner is TT, 1.80 V, 25 C, high-density (`sky130_fd_sc_hd`).

- **Genus** reads the installed Liberty file directly.
- **Design Compiler** needs a compiled Synopsys `.db`. `run_dc.sh` builds it with
  `lc_shell` on first use into `libraries/sky130_fd_sc_hd/db/` and reuses it
  afterwards.

Overrides: `GENUS_TIMING_LIB`, `SKY130_LIBERTY`, `DC_TARGET_LIB`.

## Adding or removing RTL

`synthesis/common/filelists/rtl_files.tcl` is ordered lowest-level first and must
stay in sync with the other four file lists in the repository — see the
`openflex-config` skill or the root `CLAUDE.md`.
