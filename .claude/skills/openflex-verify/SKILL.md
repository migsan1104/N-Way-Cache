---
name: openflex-verify
description: Run the cache functional-verification regression on the UF ECE server — Questa via OpenFLEX (openflex/verify.sh), Xcelium (xcelium/run.sh), or both (./verify.sh) — and triage a failing run. Use whenever asked to verify, simulate, regress, "run the tests", check that RTL changes still pass, or debug a verification failure.
---

# Running cache verification

## Environment first, every single time

Tool environments are **not** on `$PATH` by default, and shell state does not survive between Bash
calls. Source the right env in the *same* command as the tool:

| Flow | Source this |
|---|---|
| OpenFLEX / Questa / Vivado | `source /apps/reconfig/enable_pro` |
| Xcelium, Genus, Design Compiler | `source /apps/settings` |

`openflex/verify.sh` and `openflex/timing.sh` already source `enable_pro` internally and prepend
`~/.local/bin` (where the `openflex` executable lives), so calling those scripts directly works from
a bare shell. `xcelium/run.sh` does **not** source anything — it only checks that `xrun` exists and
errors out otherwise, so you must wrap it yourself.

## The standard regression is two runs, always

Every verification pass is `0.8` **and** `1.0`. One run is never the answer:

```bash
./verify.sh 0.8
./verify.sh 1.0
```

That's the four PASS/FAIL checks the README describes — two simulators × two pressure settings —
because each `./verify.sh` invocation runs Questa and Xcelium at a single setting. Report all four
results, not a summary of one.

The argument sets both `CPU_REQ_VALID_PROBABILITY` and `CPU_RESP_READY_PROBABILITY` (the second
positional arg defaults to the first), which are CPU-side forward pressure and backpressure.
`1.0` is the full-throughput case; `0.8` is what actually exercises the stall paths — `cpu_req_ready`
deasserting, the hit FIFO filling, the RS almost-full margin, and out-of-order response interleaving.
A change can easily pass at 1.0 and fail at 0.8.

Pass the two args separately only for deliberate asymmetric-pressure experiments
(`./verify.sh 1.0 0.5` = full request rate, heavy response backpressure).

Sim runtime is short (~33 s of simulation plus compile per invocation), so both runs are quick and
neither needs backgrounding.

## Single-simulator commands

```bash
# Questa only
openflex/verify.sh [--quiet] [req_prob] [resp_prob]

# Xcelium only — needs the Cadence env
bash -lc 'source /apps/settings && cd /ecel/UFAD/miguel.sanchez1/Cache/xcelium && ./run.sh 0.8'
```

Use these while iterating on a fix; go back to the two full `./verify.sh` runs before declaring
anything verified. `openflex/run_openflex.sh` is just an alias that execs `openflex/verify.sh`.

Bare `./verify.sh` with no argument defaults to `0.8 0.8` — but prefer writing the value explicitly
so the transcript header records which pass it was.

## How PASS is actually decided

OpenFLEX's own exit code is unreliable for Questa — the tool's source notes that ModelSim's return
code does not capture assertion failures. So `openflex/verify.sh` decides PASS by inspecting the
transcript, in this order:

1. OpenFLEX exit status non-zero → FAIL
2. transcript matches `(^|[^[:alpha:]])(error|fatal|failure):` → FAIL
3. transcript does **not** contain `Congrats all associativity tests passed` → FAIL
4. otherwise → PASS

`xcelium/run.sh` greps for the same `Congrats` string. That string is emitted by
`Verification/Test_Complete_runner.svh`. **Changing that message silently breaks both flows.**

## Where output goes

| File | Contents |
|---|---|
| `openflex/transcript` | Latest Questa run, overwritten each time |
| `openflex/run.log` | Copy of the same |
| `openflex/build_questa/qrun.log` | Raw `qrun` compile + sim log |
| `xcelium/logs/xrun.log` | Raw Xcelium log |
| `xcelium/logs/xrun.stdout` | Only in `--quiet` mode |

The useful part is the tail: a per-test PASS/FAIL matrix, then `FINAL REPORT PER ASSOCIATIVITY`
with Test3 miss rate, average hit-read latency, and request counts per associativity.

```bash
tail -60 openflex/transcript
grep -nE "FAILED|ERROR|MISMATCH|data errors [1-9]" openflex/transcript | head -40
```

## Narrowing a run

`Test_Complete` always runs Test1–Test10 in order for every selected associativity; there is no
per-test selector. What you can narrow:

**Associativity** — the `ASSOC` parameter: `0` = all five (default), or `1|2|4|8|16` for one.

- Questa: add `ASSOC: [8]` under `parameters:` in `openflex/Cache_verification.yml`.
- Xcelium: add `-defparam Test_Complete.ASSOC=8` to the `XRUN_CMD` array in `xcelium/run.sh`.

**Debug printing** — two gates must *both* be 1 before anything prints:

1. `TOGGLE_ASSOC_DEBUG_<N>` — a module parameter. Both run scripts force all five to `0`, so you
   must stop the script from zeroing the one you want (edit the `sed` block in `openflex/verify.sh`
   or the `-defparam` lines in `xcelium/run.sh`).
2. `TEST<n>_PRINT_CPU_REQS` / `_CPU_RESPS` / `_MEM_REQS` / `_MEM_RESPS` / `_CHECKS` / `_REPORT` —
   localparams near the top of `Verification/Test_Complete.sv`. Only `_REPORT` defaults to 1.

Turning on `_CPU_REQS`+`_CPU_RESPS` for a full run produces multi-GB transcripts (see the 25 GB
`openflex/transcript_b25_mshr_debug.log`). Narrow the associativity and shrink the
`TEST<n>_NUM_*` counts first.

**Traffic volume** — the `TEST<n>_NUM_*` localparams in `Test_Complete.sv`. Current settings give
~200,500 requests per associativity, ~1,002,500 for the full sweep.

## Triaging a failure

1. Find the first failing test and associativity — the summary lines read
   `Associativity <N> Test<n> FAILED data errors <count>`.
2. Reproduce narrowly: set `ASSOC` to just that associativity, cut the `TEST<n>_NUM_*` count for
   that test down until it still fails, then enable that test's `PRINT_*` bits.
3. Cross-check the other simulator. A failure in Questa but not Xcelium (or vice versa) usually
   means an X-propagation or race issue rather than a logic bug — the RTL has several
   `always_ff` blocks without reset that rely on the testbench's reset sequencing.
4. The scoreboard is keyed by a monotonic request sequence number, not by `cpu_req_id` (which is
   only one of 8 reusable slots). Errors distinguish wrong data from protocol violations:
   `UNEXPECTED CPU RESPONSE TO FREE SLOT` and `...SLOT OUT OF RANGE` are protocol bugs;
   data-error counts are correctness bugs.
5. `openflex/` holds a large set of historical named transcripts from past debug sessions
   (`transcript_test3_*`, `transcript_b18_*`, `transcript_b25_*`). If the failure resembles a past
   one, those show what the traffic looked like when it last broke.

## Things that bite

- **Keep the testbench in `openflex/Cache_verification.yml`.** The last two entries under `files:`
  must stay, in this order (vlog compiles in list order, so the package has to precede its user):
  ```yaml
    - ../Verification/Test_Complete_pkg.sv
    - ../Verification/Test_Complete.sv
  ```
  They were missing until 2026-08-17. Without them the Questa flow appears to work — but only
  because `openflex/build_questa/qrun.out/work` retains a `Test_Complete` from some earlier
  compile, and OpenFLEX never cleans that directory. The failure modes are nasty: `rm -rf
  openflex/build_questa` or a fresh clone dies with `(vopt-13130) Failed to find design unit
  'Test_Complete'`, and edits to `Test_Complete.sv` / the `.svh` helpers / `Test_Complete.pkg` are
  silently *not* recompiled, so Questa keeps validating the old testbench while Xcelium runs the
  new one. If Questa and Xcelium ever disagree on a testbench change, check this first.
- **Four runs cannot be parallelized in one checkout.** `openflex/verify.sh` writes its temp config
  to the fixed path `.Cache_verification_current.yml` and deletes it on exit, so two concurrent
  Questa runs overwrite each other's config — both may run the same probability while reporting
  different ones (a silent wrong result, not a crash). `xcelium/run.sh` begins with `clean.sh`,
  which `rm -rf`s `xcelium.d`/`worklib`/`logs/*` and would wipe a concurrent run mid-compile.
  To truly run all four at once, give each job its own copy of the tree — `src/`, `extra_rtl/`,
  `Verification/*.{sv,svh,pkg,hex}`, `openflex/{verify.sh,Cache_verification.yml,rtl/}`,
  `xcelium/{run.sh,clean.sh,filelist.f}` is ~470 KB and is enough. Questa and Xcelium alone do not
  collide with each other, so 2-way (one per simulator) is safe in-place.
- `verify.sh` overwrites `openflex/transcript` and `run.log` every run. Copy the transcript aside
  before starting the next pressure setting or you lose the first table.
- `build_questa/` is reused and never cleaned by OpenFLEX. `xcelium/run.sh` does call `./clean.sh`
  first.
- `downstream_init.hex` is located by trying several relative paths, so the sim works from more than
  one launch directory — but only because both the testbench and `RAM_ID` carry that search list. A
  new launch directory may need a new candidate path added.
- After editing the RTL file set, three lists must be updated together — see the `openflex-config`
  skill.
