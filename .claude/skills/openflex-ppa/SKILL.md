---
name: openflex-ppa
description: Run and interpret the Vivado out-of-context FPGA PPA flow for the cache — openflex/timing.sh for one associativity, openflex/timing_all.sh for the full sweep — including reading the headerless per-associativity CSVs and the power reports. Use whenever asked about Fmax, timing closure, LUT/FF utilization, power, "run synthesis", or comparing associativity configurations on FPGA.
---

# Cache FPGA PPA runs

## Environment

```bash
source /apps/reconfig/enable_pro
```

Shell state does not persist between Bash calls, so this must be in the same command as any direct
`openflex` or `vivado` invocation. Both `timing.sh` and `timing_all.sh` already source it internally
(falling back to `enable_std`) and prepend `~/.local/bin`, so calling those scripts needs nothing
extra.

(For contrast: Xcelium and the ASIC synthesis flows use `source /apps/settings` instead.)

## These runs are long — background them

A single associativity is a **full synth + place + route** flow on an XCU250, measured at
**~37 minutes**. The five-way sweep is roughly **3 hours**. Always launch with
`run_in_background: true` and poll, rather than blocking a foreground Bash call.

```bash
cd openflex && ./timing.sh 8        # ASSOC ∈ {1,2,4,8,16}; bare ./timing.sh defaults to 8
cd openflex && ./timing_all.sh      # all five in one OpenFLEX invocation
```

`build_vivado/` is shared and reused across every run in `openflex/`. **Never run two flows there
concurrently** — they overwrite each other's `filelist.txt`, `parameters.txt`, and `outputs/`.

## What the flow actually does

Top module is `Cache_timing` (`openflex/rtl/Cache_timing.sv`), **not** `Cache`. It is an
out-of-context wrapper that registers every DUT port, so the numbers reflect internal cache logic
rather than I/O paths.

OpenFLEX writes `build_vivado/{filelist.txt,parameters.txt,vivado.xdc}`, then runs its bundled
`vivado_flow.tcl` in batch: `synth_design -mode out_of_context` → `opt_design` → `place_design` →
`phys_opt_design` (only if post-place setup slack is negative) → `route_design`, emitting the
checkpoint and report set at each stage.

**Fmax is derived, not constrained:** `fMax = 1000 / (clock_period - WNS)`. `clock_period` comes
from OpenFLEX's `-p/--clk_period`, which defaults to **1.0 ns** and which neither `timing.sh` nor
`timing_all.sh` overrides. So every run is constrained at an intentionally unreachable 1 GHz and the
reported Fmax is the post-route achieved frequency. Passing `-p` would change the optimization
target and therefore the answer — don't add it without saying so in the results.

## Where results land

`timing.sh` writes per-associativity into `openflex/PPA/assoc_<N>/`:

| Path | Behavior |
|---|---|
| `cache<N>.csv` | Truncated then rewritten every run |
| `outputs/` | **Wiped and replaced** with `build_vivado/outputs` each run |
| `power/power_assoc<N>_<timestamp>.rpt` | Timestamped, **preserved** — history accumulates |

Transcripts go to `openflex/timing_assoc<N>_transcript` and a copy at `timing_assoc<N>.log`.
`timing_all.sh` instead writes `Cache_timing_all.csv`, `timing_all_transcript`, `timing_all.log`.

`outputs/` holds `post_synth_util.rpt`, `post_route_timing_summary.rpt`, `post_route_power.rpt`,
`post_imp_drc.rpt`, `route_vios.rpt`, `route_paths.rpt`/`.rpx`, plus `.dcp` checkpoints for each
stage. To look at a failing path interactively, open the post-route checkpoint in Vivado.

## Reading the CSVs — they have no header row

OpenFLEX writes column headers **only when the CSV file does not already exist**. `timing.sh` does
`: > "$CSV_PATH"` first, which creates an empty file — so `cache<N>.csv` is always headerless and
holds exactly one data row. `openflex/example.csv` and `openflex/cache.csv` are older files that
*do* carry the header, and are the reference for column order.

Column layout is: the YAML `parameters:` keys in order, then `fMax`, then a `(Used, Total)` pair per
resource type.

| Field | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | CACHE_BYTES | ASSOC | **fMax** | LUT U | LUT T | LUTAsLogic U | LUTAsLogic T | LUTAsMem U | LUTAsMem T | **REG U** | REG T | CARRY8 U | CARRY8 T |

Then F7MUX, F8MUX, F9MUX, BRAM, URAM, DSP, PLL, MMCM, GTYE4_*, SLL_*, followed by per-SLR
breakdowns of everything.

```bash
# Fmax + LUT + FF for every associativity
for a in 1 2 4 8 16; do
  echo "assoc $a: $(cut -d, -f3,4,10 openflex/PPA/assoc_$a/cache$a.csv)"
done

# latest power for one associativity
grep -E "Total On-Chip Power|Dynamic \(W\)|Device Static" \
  "$(ls -t openflex/PPA/assoc_8/power/*.rpt | head -1)"
```

## Current measured results (4 KB cache, XCU250-FIGD2104-2L-E)

| ASSOC | 1 | 2 | 4 | 8 | 16 |
|---|---|---|---|---|---|
| Fmax (MHz) | 178.4 | 201.8 | 184.6 | **232.0** | 203.7 |
| LUT | 83,009 | 84,801 | 89,168 | **56,082** | 87,507 |

Associativity 8 wins on both frequency and area, which is why the ASIC flow baselines on `ASSOC=8`.
Latest assoc-8 post-route power: 7.054 W total (4.032 W dynamic, 3.022 W static).
`FPGA_Cache_PPA_Scaling_4KB_Updated.png` at the repo root visualizes the sweep.

## Editing the configuration

`timing.sh` **regenerates** `.Cache_timing_assoc<N>.yml` on every run by `sed`-replacing the `ASSOC:`
line in the template `Cache_timing_all.yml`. Edits to the generated dotfiles are silently
discarded — always change the template.

`openflex/Cache_timing.yml` is a separate standalone config pinned to `ASSOC: [8]`; nothing in the
scripts uses it, it's for manual `openflex Cache_timing.yml -c out.csv` runs.

Note the timing configs list `rtl/Cache_timing.sv` **plus** the `src/*.sv` files, and unlike the
verification config they do *not* include `extra_rtl/RAM_ID.sv` (that's a testbench-only model). Any
change to the module set means updating these YAMLs along with the other file lists — see the
`openflex-config` skill.

## Interpreting a bad result

- **Fmax dropped after an RTL change**: `outputs/post_route_timing_summary.rpt` for WNS, then
  `route_paths.rpt` for the actual failing paths. The usual suspects are the combinational tag-compare
  and way-select in `Compare_Select_Replace` (S1 does compare, way select, victim capture, and array
  write enables all in one cycle) and the RS `valid_count` popcount plus priority scans in
  `Reservation_Station`, which grow with `RS_DEPTH`.
- **Utilization jumped**: compare `post_synth_util.rpt` against `post_place_util.rpt`. A large
  `LUTAsMem` swing means array structures changed inference between distributed RAM and registers.
- **DRC or route failures**: `post_imp_drc.rpt` and `post_route_status.rpt`. At these utilization
  levels on an XCU250 the part is not close to full, so routing failures point at a structural RTL
  problem rather than congestion.
