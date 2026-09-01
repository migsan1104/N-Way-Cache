---
name: openflex-config
description: Reference for the OpenFLEX tool itself — its CLI flags, YAML schema, build directories, and how the Cache repo's configs are wired — plus the procedure for adding, renaming, or removing an RTL module across all five file lists. Use when editing any *.yml OpenFLEX config, writing a new one, changing the src/ module set, or debugging "file not found" / missing-CSV errors from openflex.
---

# OpenFLEX tool and config reference

OpenFLEX is a thin Python driver (Greg Stitt, Wesley Piard, University of Florida) that expands a
YAML parameter sweep into per-combination Questa simulations or Vivado/Quartus synthesis runs.

- Executable: `~/.local/bin/openflex` (shebang `/apps/anaconda/bin/python`)
- Package: `~/.local/lib/python3.9/site-packages/openflex/` — `main.py` (CLI), `config.py` (all
  flow logic), `tcl/vivado_flow.tcl`, `tcl/quartus_results.tcl`

The whole thing is under 500 lines. When behavior is unclear, read `config.py` directly rather than
guessing — it is the authority on what a YAML key does.

Requires `source /apps/reconfig/enable_pro` in the same Bash invocation for `vivado`/`qrun` to be on
`$PATH`. The repo's wrapper scripts do this for you; direct `openflex` calls do not.

## CLI

```
openflex CONFIG_FILE [options]

  -m, --mode         sim | synth            override the YAML's mode
  -t, --tool         questa | vivado | quartus   override the YAML's tool
  -c, --synth_csv    FILE                   results CSV — REQUIRED for synth, ignored for sim
  -p, --clk_period   FLOAT                  clock period in ns, default "1.0"
  -s, --sample       N                      randomly sample N parameter combinations
```

`ERROR: Missing CSV filename` means synth mode without `-c`. Only `questa` is accepted for sim.

## YAML schema

```yaml
mode: sim              # or synth
tool: questa           # or vivado / quartus
top: Test_Complete     # top module name
clock: clk             # clock port name — used to build the XDC/SDC
device: XCU250-FIGD2104-2L-E   # synth only

files:
  - ../src/Cache.sv    # see the path warning below

parameters:            # every key's values are crossed (Cartesian product)
  CACHE_BYTES: [4096]
  ASSOC: [1, 2, 4, 8, 16]

groups:                # optional; each group must be a subset of, or disjoint from, parameters
  - {ASSOC: 8, CACHE_BYTES: 8192}
```

Every parameter combination becomes its own full build. `CACHE_BYTES: [4096, 8192]` crossed with
five associativities is ten Vivado place-and-route runs — check the product before launching.

The YAML is parsed with `yaml.loader.BaseLoader`, so **every value arrives as a string**. Don't rely
on YAML type coercion.

### The path gotcha

`config.py` does `os.path.abspath(f)` on each entry in `files:`. `abspath` resolves against the
**process working directory**, not the YAML file's directory. So `../src/Cache.sv` only resolves
when `openflex` is launched from inside `openflex/`.

This is exactly why every wrapper script starts with `cd "$SCRIPT_DIR"`. Running
`openflex openflex/Cache_verification.yml` from the repo root will fail to find the RTL. Always:

```bash
cd openflex && openflex Cache_verification.yml
```

## What each mode does

**sim (questa)** — creates `build_questa/`, then per combination runs, with `cwd=build_questa`:

```
qrun -64 -sv -timescale=1ns/100ps -g PARAM=VALUE ... <abs file paths> -top <top>
```

Each run is labeled `build_<top>_<param>_<value>_<param>_<value>...` in the log — that's the string
in `openflex/transcript` headers. Note OpenFLEX forces `1ns/100ps`; `Test_Complete.sv` declares
`` `timescale 1ns/1ps `` itself, and the file directive wins.

OpenFLEX only counts a test as failed if `qrun` returns non-zero, and its own source notes this
misses ModelSim assertion failures. **Never trust OpenFLEX's pass/fail for simulation** — the repo's
`verify.sh` greps the transcript instead. See the `openflex-verify` skill.

**synth (vivado)** — creates `build_vivado/`, writes `filelist.txt`, `parameters.txt`, and a
generated `vivado.xdc` containing only:

```tcl
create_clock -period <clk_period> [get_ports <clock>] -name clk
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports <clock>]
```

then runs `vivado -mode batch -source <pkg>/tcl/vivado_flow.tcl -tclargs <top> <device>
<clk_period>`. Results are scraped from `build_vivado/vivado_report.txt` (line 1 = Fmax, line 2 =
space-separated `NAME:used:total` triples) and appended to the `-c` CSV.

**Header rows are written only if the CSV does not already exist.** A script that truncates the CSV
first (as `timing.sh` does) produces a headerless file. See the `openflex-ppa` skill for the column
decode.

**Build directories are reused and never cleaned** (there's an explicit TODO about it in
`config.py`). Two concurrent runs in the same directory will corrupt each other. `build_quartus` is
the exception — Quartus mode hard-exits if the directory already exists.

## This repo's configs

| File | Mode | Top | Purpose |
|---|---|---|---|
| `openflex/Cache_verification.yml` | sim/questa | `Test_Complete` | Functional regression. Includes `extra_rtl/RAM_ID.sv` (TB memory model). |
| `openflex/Cache_timing_all.yml` | synth/vivado | `Cache_timing` | **Template** for the PPA sweep, `ASSOC: [1,2,4,8,16]`. |
| `openflex/Cache_timing.yml` | synth/vivado | `Cache_timing` | Standalone `ASSOC: [8]`, not referenced by any script. |
| `openflex/.Cache_timing_assoc<N>.yml` | synth/vivado | `Cache_timing` | **Generated** by `timing.sh` — edits are overwritten. |

Both verify scripts inject extra parameters by `sed`-ing the template into a temporary config rather
than editing it in place — `openflex/verify.sh` appends the probability and debug-toggle knobs after
the `CACHE_BYTES:` line, `timing.sh` rewrites the `ASSOC:` line. If you add a parameter, check
whether those `sed` expressions still anchor correctly.

Timing configs list `rtl/Cache_timing.sv` plus `src/*.sv` and deliberately exclude `RAM_ID.sv`.

## Changing the RTL module set

Adding, renaming, or removing a file in `src/` requires updating **five** lists:

1. `xcelium/filelist.f`
2. `openflex/Cache_verification.yml`
3. `openflex/Cache_timing_all.yml`
4. `openflex/Cache_timing.yml`
5. `asic/synthesis/common/filelists/rtl_files.tcl` — ordered lowest-level first

Verify they agree:

```bash
cd /ecel/UFAD/miguel.sanchez1/Cache
for m in $(ls src/*.sv | xargs -n1 basename); do
  miss=""
  grep -q "$m" xcelium/filelist.f                            || miss="$miss xcelium/filelist.f"
  grep -q "$m" openflex/Cache_verification.yml               || miss="$miss Cache_verification.yml"
  grep -q "$m" openflex/Cache_timing_all.yml                 || miss="$miss Cache_timing_all.yml"
  grep -q "$m" openflex/Cache_timing.yml                     || miss="$miss Cache_timing.yml"
  grep -q "$m" asic/synthesis/common/filelists/rtl_files.tcl || miss="$miss rtl_files.tcl"
  [ -n "$miss" ] && echo "MISSING $m ->$miss"
done; echo "(scan complete)"
```

Silence means all five agree. A module missing from only one list fails in just that flow, often
much later and with a confusing elaboration error.
