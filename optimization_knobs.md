# Optimization knobs

Reference for the physical-optimization building blocks imported from the BNN
project (`extra_rtl/fanout_tree.sv`, `extra_rtl/fanout_tree_ALWAYS.sv`, and the
`Register` / `Register_ALWAYS` leaves they instantiate), plus how they map onto
this cache. Companion to the lab notebook `optimizations.md`; nothing here is
in any file list yet.

## What the fanout tree is

A registered binary broadcast tree. One signal goes in; `CLUSTERS` registered
copies come out, each having passed through the same number of flops:

```
din -> [root reg] -> [reg] -> [reg] -> dout[0]
                  \        \-> [reg] -> dout[1]
                   \-> [reg] -> [reg] -> dout[2]
                            \-> [reg] -> dout[3]
```

Stage 0 is a single root register; every later stage doubles the copy count
until the final stage holds `CLUSTERS` copies. Each register drives at most
two downstream register D-pins, so no single flop ever sees more than fanout-2
on the tree itself — the *leaves* carry the real loads, split `CLUSTERS` ways.

Mechanics, from the source:

- `STAGES = clog2(CLUSTERS) + 1` (1 when `CLUSTERS == 1`).
- **Latency = STAGES cycles**, identical on every output — the copies are
  mutually aligned, just late relative to `din`.
- Register cost for power-of-two `CLUSTERS`: `2*CLUSTERS - 1` instances of
  `DWIDTH` bits each (4 clusters -> 7 regs, 8 -> 15).
- The generate loops build stage `s` from stage `s-1`: node `n` writes copies
  `2n` (always) and `2n+1` (guarded against `CLUSTERS`).

## The knobs

| Knob | What it trades |
|---|---|
| `DWIDTH` | Width of the broadcast payload. Cost scales linearly (`(2*CLUSTERS-1) * DWIDTH` flops). |
| `CLUSTERS` | How many independent load domains the consumer is split into. More clusters = less load per leaf copy, more flops, one extra latency cycle per doubling. |
| Variant: `fanout_tree` vs `fanout_tree_ALWAYS` | Async-reset (`Register`) vs reset-free (`Register_ALWAYS`) leaves. The reset-free variant is the right FPGA default: no reset net to route, fewer control sets, flops pack anywhere, and a broadcast tree re-fills with live data in STAGES cycles anyway so reset state is worthless. Use the reset variant only when a consumer must not see garbage during the post-reset fill window. |

## Caveats found while reading (know these before using either file)

1. **Synthesis will delete the whole point of it.** The duplicate registers in
   each stage are functionally equivalent, and both Vivado (`synth_design`
   equivalent-register merging) and Genus will merge them back into a single
   flop — collapsing the tree into a plain `STAGES`-deep delay line with one
   high-fanout leaf. In the BNN project this presumably survived via tool
   settings; here it must be pinned in RTL: add `(* keep = "true" *)` /
   `dont_touch` to the `Register` instances (or `q` nets) before trusting any
   PPA number that involves this module. This is the first modification to
   make.
2. **Non-power-of-two `CLUSTERS` is broken.** The right-child write is guarded
   (`2n+1 < CLUSTERS`) but the left child is not, so e.g. `CLUSTERS = 5`
   writes `stage[3][6]` into an array declared `[0:4]` — out of bounds. Fix
   (guard the left child too, and prune subtrees with no surviving outputs) or
   restrict to powers of two with an elaboration assert, like the RS does for
   `RS_DEPTH`.
3. **Latency is the poison pill for this cache.** Every high-fanout net we
   have measured (write grants, flag CEs, RS entry steering, PLRU D-broadcast)
   is *consumed in the same cycle it is born* — this design's alignment is
   hand-tuned down to the `Delay_r #(5)` constant. Dropping a `STAGES`-cycle
   tree into any of those paths is a functional change requiring the full
   re-derivation the CLAUDE.md timing-couplings section warns about. The tree
   as-is fits latency-tolerant broadcast only (BNN weight/config distribution
   was exactly that; a cache pipeline has almost none of it).

## What we would actually use here: the one-stage derivative

The valuable idea for this repo is not the log-depth tree — it is **explicit
registered duplication with zero added latency**: where a pipeline register
already exists and feeds N loads, replace it with `CLUSTERS` kept copies of
that same register, each feeding one slice of the loads. Same cycle count,
same D input, fanout divided by `CLUSTERS`. That is a `fanout_tree` with the
tree flattened to its last stage:

```systemverilog
module fanout_dup #(parameter int DWIDTH = 1, CLUSTERS = 4)(
    input  logic clk,
    input  logic [DWIDTH-1:0] din,                      // the old reg's D
    output logic [CLUSTERS-1:0][DWIDTH-1:0] dout        // one copy per domain
);
    (* keep = "true" *) logic [DWIDTH-1:0] q [CLUSTERS];
    ...
```

This is the manual version of what Entry 10 currently trusts Vivado's
replication to do with the grant flops ("flops Vivado can replicate at will").
Where the tool's replication falls short — A4 still shows a 41/1000
`word_valid_mem` residual after Entry 10 — an explicit `fanout_dup` per
way/bank-group makes the split deterministic instead of hoping phys_opt finds
it. On ASIC the same module gives Genus pre-split drivers instead of relying
on buffer-tree synthesis over a 1280-pin CE net.

### Candidate attachment points (all flop-fed already, so zero-latency dup applies)

- **Entry 10 grant flops** (`cpu_write_wen` / `alloc_wen` in
  `Compare_Select_Replace.sv`): one copy per way already exists structurally;
  a per-bank-quadrant dup targets the A4 41/1000 residual.
- **PLRU write data, after an Entry-12-style update registration** (see
  notebook queue): registered `next_bits` broadcast to `NUM_SETS` D-pins is
  the textbook use — dup per set-quadrant.
- **RS entry steering** (`dispatch_valid`-derived shift/merge enables fanning
  to 16 entries x ~100 bits): source is an MSHR flop; a dup per entry-group
  would cut the enable net, though the Entry 11 CAM precompute should be
  measured first — it may shrink this cone enough on its own.
- **ASIC reset distribution** (reset-variant tree, latency harmless if reset
  is held): a maybe, only once Innovus shows reset buffering as a real cost.

### Modification checklist before first use

1. Add `keep`/`dont_touch` attributes (both variants) — without this every
   measurement is fiction.
2. Add the `fanout_dup` single-stage variant (or a `STAGES_OVERRIDE = 1`
   mode).
3. Guard the non-power-of-two case (fix or assert).
4. When (if) it enters `src/`, remember the three-file-list sync rule from
   CLAUDE.md.

## Ground rule carried over from the campaign

Duplication is a *physical* knob: it never changes logic depth, only net
fanout/routing. The campaign's measured wins so far came from *architectural*
knobs (register the decision, not the ingredients — Entries 4, 9, 10). Reach
for `fanout_dup` when a worst-path list says a flop-sourced net is
routing-dominated (like the 78%-routing flag-CE cone was), not as a first
resort against logic-depth walls like the RS CAM.
