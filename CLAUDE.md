# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A parameterized, non-blocking, N-way set-associative cache in SystemVerilog, taken through a full
ASIC-style flow: RTL → self-checking verification → FPGA PPA characterization → logical synthesis
(and eventually RTL-to-GDSII). `README.md` holds the project roadmap and the test-suite table.

The repo root is reachable as both `/ecel/UFAD/miguel.sanchez1/Cache` and
`/home/UFAD/miguel.sanchez1/Cache` — same inode, two mount paths.

## Environment (UF ECE server)

No EDA tool is on `$PATH` in a fresh shell, and shell state does **not** persist between Bash tool
calls. Source the right environment in the *same* command as the tool:

| Flow | Source this |
|---|---|
| OpenFLEX, Questa, Vivado | `source /apps/reconfig/archive/enable_pro` (see note) |
| Xcelium, Genus, Design Compiler | `source /apps/settings` |

**2026-08-25 environment change:** IT replaced `/apps/reconfig/enable_pro` / `enable_std` with a
single `/apps/reconfig/enable` (Questa 2026.2, Vivado 2025.2) and moved the old files to
`/apps/reconfig/archive/`. Every number in this repo was measured with the old toolchain (Questa
2023.3, Vivado 2021.2), and the archived files still check out licenses, so the scripts prefer them.
`openflex/verify.sh` and `openflex/timing.sh` try, in order: `enable_pro`, `archive/enable_pro`,
`enable_std`, `archive/enable_std`, `enable` — and prepend `~/.local/bin`, where the `openflex`
executable lives — so calling those scripts works from a bare shell. If the FPGA flow is ever run
under the new Vivado, say so in the results: they will not be comparable with README §3. `xcelium/run.sh`
sources nothing and only checks that `xrun` exists, so wrap it yourself:

```bash
bash -lc 'source /apps/settings && cd <repo>/xcelium && ./run.sh 1.0 1.0'
```

## Commands

All scripts resolve their own paths, so they work from any working directory.

Three skills in `.claude/skills/` cover the OpenFLEX flows in depth — `openflex-verify`
(regression + failure triage), `openflex-ppa` (Vivado timing/PPA sweeps), and `openflex-config`
(the OpenFLEX CLI/YAML schema and the file-list sync procedure).

The regression is **always both pressure settings**, never one:

```bash
./verify.sh 0.8
./verify.sh 1.0
```

Each invocation runs two jobs (Questa + Xcelium) at one setting, so the pair is the four PASS/FAIL
checks the README describes. The argument sets `CPU_REQ_VALID_PROBABILITY` and
`CPU_RESP_READY_PROBABILITY` (second positional arg defaults to the first). `1.0` is full
throughput; `0.8` is what exercises the stall paths — request-ready deassertion, hit-FIFO fill, the
RS almost-full margin, out-of-order response interleaving. Changes pass at 1.0 and fail at 0.8
routinely, so report all four results.

Terminal output is just PASS/FAIL; full logs stay in `openflex/transcript` (+ `run.log`) and
`xcelium/logs/xrun.log`.

Individual simulator flows:

```bash
openflex/verify.sh [--quiet] [req_prob] [resp_prob]     # Questa via OpenFLEX
source /apps/settings && cd xcelium && ./run.sh [--quiet] [req_prob] [resp_prob]
```

FPGA PPA (Vivado UltraScale OOC, XCU250) and ASIC logical synthesis (SKY130 HD, TT 1.80V 25C):

```bash
cd openflex && ./timing.sh 8       # ASSOC ∈ {1,2,4,8,16}; defaults to 8; ~37 min — background it
cd openflex && ./timing_all.sh     # all five associativities, ~3 hours
bash -lc 'source /apps/settings && cd <repo>/asic && ./run_genus.sh 4'   # or ./run_dc.sh 4
```

A `timing.sh` run is a full synth + place + route, not just synthesis. Launch it with
`run_in_background: true` and poll. `build_vivado/` is shared, so never run two OpenFLEX flows in
`openflex/` at once.

`timing.sh` rewrites `.Cache_timing_assoc<N>.yml` from the `Cache_timing_all.yml` template, then
lands results in `openflex/PPA/assoc_<N>/`: `cache<N>.csv` (timing + utilization),
`outputs/` (overwritten each run), `power/` (timestamped, preserved).

### Narrowing a run

There is no per-test selector. `Test_Complete` always runs Test1–Test10 in order for each selected
associativity. What you *can* narrow:

- **Associativity**: the `ASSOC` parameter — `0` = all five, or `1|2|4|8|16` for just one.
  Xcelium: add `-defparam Test_Complete.ASSOC=8` to `XRUN_CMD` in `xcelium/run.sh`.
  Questa: add `ASSOC: [8]` under `parameters:` in `openflex/Cache_verification.yml`.
- **Debug output**: two gates must both be 1 to print. `TOGGLE_ASSOC_DEBUG_<N>` (module parameter,
  forced to 0 by both run scripts) AND the per-test `TEST<n>_PRINT_*` localparams in
  `Test_Complete.sv`. To see traffic for one test, set its `PRINT_*` bits and stop the script from
  zeroing the toggle for that associativity.
- **Traffic volume**: the `TEST<n>_NUM_*` localparams at the top of `Test_Complete.sv`
  (~200,500 requests per associativity at current settings, ~1M for the full sweep).

Both verify scripts decide PASS by grepping for the literal string
`Congrats all associativity tests passed` (emitted by `Test_Complete_runner.svh`). Changing that
message silently breaks both flows.

### Three file lists must stay in sync

Adding, renaming, or removing a module in `src/` means editing all three:

1. `xcelium/filelist.f`
2. `openflex/Cache_verification.yml` **and** `openflex/Cache_timing*.yml` (timing list has no `RAM_ID`)
3. `asic/synthesis/common/filelists/rtl_files.tcl` (ordered lowest-level first)

## Architecture

### Directories

- `src/` — the synthesizable RTL that actually gets built. Everything here is in the file lists.
- `extra_rtl/` — retired modules from earlier design iterations. **Except `RAM_ID.sv`**, which is
  the live downstream-memory model used by the testbench. Don't treat the whole directory as dead.
- `Verification/` — `Test_Complete.sv` is the only live testbench; it `include`s
  `_helpers.svh` / `_monitors.svh` / `_runner.svh`. `Test_Complete_pkg.sv` is a one-line wrapper
  that includes `Test_Complete.pkg`, and must compile before `Test_Complete.sv`.
  `Basic_Test.sv` and `Test1.sv` are legacy and in no file list.
- `openflex/` — Questa + Vivado flows and PPA results. `openflex/rtl/Cache_timing.sv` is an
  out-of-context wrapper that registers every DUT port so synthesis measures internal logic only.
- `asic/` — Genus + Design Compiler logical synthesis on SKY130 HD. `run_genus.sh [ASSOC] [period]`
  and `run_dc.sh [ASSOC] [period]` default to `ASSOC=8` / 2.000 ns; `sweep.sh` runs several
  configurations (`-j N` for concurrency), `collect_ppa.py` prints a PPA table per tool, and
  `clean.sh` drops regenerable output. Results go to `asic/PPA/<genus|dc>/assoc_<N>/`, and each run
  works inside its own `work/` dir so the tools cannot scatter output into the repo root or corrupt a
  concurrent run. Only `asic/PPA/RESULTS.md` is tracked; everything else under `PPA/` is ignored.
- `fv/`, `designs/`, `Diagrams/` — formal-verification map data, block diagrams.

### Interfaces

CPU addresses are **word-addressed**, not byte-addressed: `addr[1:0]` is the word offset inside the
16-byte line, then the set index, then the tag. There is no byte offset field anywhere.

CPU side: valid/ready on requests, valid/ready on responses, and a `cpu_req_id` that is echoed back
on `cpu_resp_id` so an out-of-order CPU can match responses to requests. Writes get responses too.
Memory side: `mem_resp_ready` is hardwired to 1 — this cache assumes **no downstream backpressure**,
by design (a larger coherence/memory hierarchy owns that in the target RISC-V system).

### Request pipeline

Three stages, no mid-pipeline stalls. Backpressure exists only at `cpu_req_ready`, which is
`hit_resp_ready && mshr_alloc_ready` — the hit-FIFO not-full AND the reservation-station not
almost-full. The RS almost-full margin (`MSHR_AF=3` of `RS_DEPTH=8`, paired to `MSHR_COUNT=4`) is what absorbs the requests
already in flight in the pipe when the brakes go on.

- **S0 `Address_Decode`** — splits tag/set/word combinationally, drives `array_rindex` into the
  arrays the same cycle, registers the rest.
- **S1 `Compare_Select_Replace`** — arrays and PLRU present registered data here. Tag compare,
  hit/miss, way select, and victim capture all happen combinationally, and array writes are driven
  in this same cycle (so a write lands on the same edge that `cmp_*` registers). Victim way =
  first non-allocated way, else the PLRU victim from `Replacement`.
- **S2** — `cmp_hit` → hit FIFO in `Response_Unit`; `cmp_miss` → `MSHR_File` allocation.

### Sub-line valid bits — the central idea

Each line carries `word_valid[4]` alongside `allocated`/`dirty`/`tag`. A **write** hits on tag match
alone; a **read** additionally requires `word_valid[word]`. This is what makes write-allocate work
without waiting for the fill: a write miss allocates the line, writes its word into the array
immediately, and sets that word's valid + dirty bit. The refill then writes back **only the banks
whose `word_valid` is still 0**, so an early write is never clobbered by late memory data. A read
to a word that hasn't arrived misses and becomes an MSHR waiter.

`Flag_Tag_Data_Array` (one instance per way) banks data per word — `data_bank[word][set]` — so a CPU
write touches one bank. It registers the refill one cycle internally and gates it on
`refill_tag_r == tag_mem[refill_waddr_r]`, dropping refills whose line was re-allocated to a
different tag in the meantime. Read ports carry same-cycle bypasses for alloc and CPU write.

### Miss path

`Reservation_Station` (8 entries, `rs[0]` oldest, shift-down on retire) → `MSHR_File`
(4 `MSHR_Entry` FSMs) → `MSHR_Request_Arbiter` → single memory port.

- **RS** merges misses to the same line into one entry holding up to `MAX_WAITERS=4` `(cpu_id, word_id)`
  pairs. It issues the oldest entry that isn't yet `in_progress` into any free MSHR.
- **`MSHR_Entry`** FSM: `S_IDLE` → `S_ISSUE_W` (only if the victim is dirty; one beat per victim
  word, skipping words whose `victim_word_valid` bit is 0) → `S_ISSUE_R` (4 beats starting at the
  **critical word** — `miss_word_id_r + issue_count`) → `S_WAIT_R`. Responses accumulate into
  `fill_line`; the 4th pulses `refill_wen` and returns to IDLE.
- **`MSHR_Request_Arbiter`** keeps a small FIFO of MSHR indices ordered by when each entry's
  `issue_pending` rose. That keeps each MSHR's beats contiguous on the memory port and stops a
  younger low-index MSHR from cutting ahead of an older writeback stream. Its one-hot `issued`
  output feeds straight back as each entry's `issue_done`.
- **`MSHR_Mux`** picks the lowest-index entry asserting `refill_wen` for the array write.
  `MSHR_File`'s `retire_sel_idx` deliberately mirrors that same priority so the RS retires exactly
  the entry whose line is being refilled.
- **`Dispacher`** takes the retiring RS entry's waiter list and streams one CPU response per cycle,
  releasing each waiter as soon as its word has been seen — critical-word-first, out-of-order,
  independent of the array refill.

### Timing couplings that break silently

- **`Delay_r #(.DELAY(5))` on `mem_resp_rdata` in `Cache.sv`.** This aligns memory read data with the
  cycle the `Dispacher` sees the retire. It is a hand-tuned constant: any change to the refill or
  retire pipeline depth needs this number re-derived, and getting it wrong yields wrong data with
  no structural error.
- **`MSHR_COUNT=4` is not really parameterized.** `MSHR_File` hardcodes `localparam MSHR_COUNT = 4`
  and declares ports as `logic [3:0]` / `[4]` arrays, with `MSHR_ID_WIDTH=2` fixed in `Cache.sv`.
  Scaling it takes real edits, not a parameter override.
- **Line geometry is fixed.** `WORDS_PER_LINE=4` / `LINE_WIDTH=128` / `LINE_BYTES=16` are localparams
  in `Cache.sv`; only `CACHE_BYTES` and `ASSOC` are true knobs.
- **The miss FIFO in `Response_Unit` has no full flag** (`FIFO_NF`, depth 8). It relies on the
  RS/MSHR credit limit to bound in-flight misses. Raising RS depth, MSHR count, or `MAX_WAITERS`
  without re-checking that bound can overflow it silently.

## Verification environment

`Test_Complete.sv` instantiates **all five associativity DUTs at once** (1/2/4/8/16), each with its
own `RAM_ID` memory model, then muxes one active pair at a time via `active_assoc_idx`. Inactive
DUTs are held with `cpu_resp_ready=1` so they never get artificially backpressured. The runner is
associativity-major: for each ASSOC, run Test1–Test10, then move on.

- Golden model: `golden_mem[]` in the TB, initialized from `downstream_init.hex` (resolved by
  searching several relative paths — the sim can be launched from several directories).
  `RAM_ID` reloads the same image **on every reset**, so each test starts isolated.
- Downstream read latency is 20 cycles (`RAM_READ_LATENCY`).
- Scoreboarding is keyed by a monotonic **request sequence number**, not by `cpu_req_id`. The CPU ID
  is only one of 8 reusable slots (`CPU_SLOT_COUNT`, narrower than the 4-bit interface);
  `slot_seq[]` maps a live slot back to its sequence. The monitors flag duplicate responses,
  responses to free slots, and out-of-range slots/sequences.
- `chance(p)` drives the `CPU_REQ_VALID_PROBABILITY` / `CPU_RESP_READY_PROBABILITY` knobs.

## PPA context

The project's capacity target is **16KB** (the SRAM-macro plan in `asic/MACROS.md` is sized for it);
4KB results and artifacts were deprecated and deleted 2026-08-20. Historical 4KB data survives in
git history and the gitignored lab notebook `optimizations.md`.

Current XCU250 OOC results (`openflex/PPA/assoc_*/cache*.csv`, first two fields are
`CACHE_BYTES, ASSOC`, third is Fmax in MHz), 16KB cache, Entries 1-8 RTL:

| ASSOC | 1 | 2 | 4 | 8 | 16 |
|---|---|---|---|---|---|
| Fmax (MHz) | **326.6** | 301.0 | 282.3 | 269.8 | 299.9 |

Fmax is U-shaped in ways: the wall is the flag-write decode (`out_tag -> word_valid_mem`), which
scales with per-way set depth x enable-cone width — A8 (128 sets, 8-way cone) is the worst point.
`FPGA_Cache_PPA_Scaling_16KB.png` visualizes it; the full table is `README.md` §3, regenerated by
`openflex/collect_ppa.py`. FPGA timing configs default to `CACHE_BYTES: [16384]`.

ASIC logical synthesis: physically-aware Genus + DC at ss_100C_1v60, 3.500 ns
(`ASIC_CACHE_BYTES` defaults to 16384). The 16KB five-way standard-cell sweep and the first
SRAM-macro run (16KB ASSOC=4, `ASIC_SRAM_MACRO=1`, 16 macros, x2.0 derate — corner decision in
`asic/MACROS.md`) are the current measurements; `asic/PPA/RESULTS.md` is regenerated by
`asic/collect_ppa.py`. Synthesis numbers use placement-based wire estimates (PLE) — treat them as
a floor: post-P&R slack will be worse. Verification defaults to 16KB with SRAM macros enabled
(TB parameters `CACHE_BYTES=16384`, `EN_SRAM_MACRO=1`): the ASSOC=4 DUT exercises the macro
branch through the vendor simulation model while the other four DUTs cover the behavioral banks in
the same run. The macro sim model is listed in the VERIFICATION file lists only
(`xcelium/filelist.f`, `openflex/Cache_verification.yml`) — never in the timing or ASIC lists,
which bind the real macro views.

**Signed-off ASIC package (2026-09-11):** P&R run
`asic/PnR/innovus/runs/20260908_iter26b_quad2_ch260_e35fo32_ctsA_p4000_1v76`, checkpoint
`05_tagskew10.enc` (E35 netlist, quad floorplan `fp_iter23_quad.tcl` with `ASIC_FP_WAY_CHANNEL=260`,
plus antenna, PG-via and two clock-skew ECOs). Tempus SI 5.3 ns / 188.7 MHz at ss_n40C_1v76, 0
violators; DRC/LVS/IR/EM clean; GLS PASS at 5.3 ns. The 182 MHz fallback is the pass-4 (`05_pgvia9`)
export. Per-check notes: `asic/signoff/{tempus,lvs,drc,voltus}/*.md`, `xcelium/GLS.md`; sheet
`asic/signoff/GDS11_Image/Iter26b_SO.png` (rendered by `render_gds.py` in that directory); floorplan
history figure `asic/PnR/floorplans/floorplan_history.png` (`draw_floorplan_history.py`). README §4
is the flow walkthrough. Everything under `asic/signoff/results/` is gitignored and keyed by run stamp.

## Repo hygiene

Working branch is `my-local-backup`; `main` is the PR target. A lot of tool output is tracked or
sitting untracked in the tree (`transcript`, `command.log`, `genus.log*`, `xcelium/xcelium.d/`,
`openflex/PPA/*/outputs/*.dcp`, `.pbs_*`, `alib-52/`, `default.svf`), so `git status` is noisy by
default — check that a diff is actually yours before staging. Note `.gitignore` has both `openflex/`
and `!openflex/**`, so the openflex tree is deliberately kept under version control.
