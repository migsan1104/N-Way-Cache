# Entry 38 — the refill guard without a second tag read

Status: 38(a) PLAN (brainstormed 2026-09-08 evening, nothing in src/), 38(b) FOLLOW-ON.
Companion notes: `optimizations.md` "Entry 38(a) — PLAN 2026-09-08" (lab notebook,
gitignored) and E35(e) (2026-08-25). This file is the tracked design record.

Naming: E35 = the August netlist (Genus 20260828_151051). E37 = E35 + Skid_Buffer +
registered reset (0907). 38(a) is RTL on top of E37.

---

## 1. The RTL under attack

**Module:** `src/Flag_Tag_Data_Array.sv` (one instance per way).

**The cone:** the refill guard's own tag read. Every cycle, every way reads its tag
store a second time at the refill address and compares it, one cycle later, with the
tag the MSHR fetched for:

```
bank_refill_rtag_c[gb] = bank_tags[refill_waddr[BANK_ADDR_W-1:0]]     // per tag bank, 16:1
refill_rd_tag_r    <= bank_refill_rtag_c[refill_bank_sel_c];          // cycle R, free-running
refill_stage_tag_r <= refill_tag;                                     // cycle R, under refill_wen
refill_guard_ok_c   = (refill_stage_tag_r == refill_rd_tag_r);        // cycle R+1
refill_bank_pending_r <= refill_guard_ok_c ? ~refill_words_valid_c : '0;
```

That is a 256:1 x 22-bit read per way (TAG_BANK_DEPTH=16 banks x 16:1, then a 16:1
bank select), addressed by `MSHR_Mux.refill_set_id`, which fans out to all four ways.
The S0 pipeline read (`raddr -> rtag_raw_r`) is the other consumer of the same
22.5k tag flops, so today each tag flop drives two read trees.

**The measurement that names it:**

| run | class | count @ slack |
|---|---|---|
| e29all census (08-25) | refill_set_id -> refill_rd_tag_r | 62 @ -619 ps ("the refill half of the wall") |
| e36bp Genus corner-2 (08-31) | REFILL_MUX -> refill_rd_tag | 56 of the worst 120 |
| Tempus 19b v8 (09-07) | MSHR_FILE_REFILL_MUX_refill_set_id_reg/Q -> GEN_WAYS[*]...refill_rd_tag_r_reg/D | class 2 of the top two reg2reg classes, both corners |

Class 1 (the S0 read, `rindex_rep_r -> rtag_raw_r`) is the same tree fed from the
other port; it is structural and belongs to 38(b). 38(a) deletes class 2.

**Why the guard exists.** A refill must not write memory data into a line whose
{set, way} was re-allocated (renamed) to another tag while the fetch was in flight.
Sub-line valid makes dropping safe: words the refill does not write stay
`word_valid=0` and re-fetch on a later miss. E35(e) reduced the guard to the tag
compare alone and dropped two alloc-kill terms; E35(e) also documented the hole that
left: an alloc landing on the R edge is invisible to the pre-edge tag read. And the
tag compare has its own blind spot: a rename A -> B -> A into the same way keeps the
same tag, so the old guard passes and installs A's PRE-writeback fetch over a fresh
line. The directed test for this (finding 1, 08-23) was never written.

**The one-line statement of the job:** drop an array refill whose {set, way} was
renamed at any time between the miss that started the fetch and the last drained
word. Renames happen through exactly one path, `Compare_Select_Replace`'s S2
grants `alloc_wen[way]` + `alloc_waddr`. So "was I renamed" can be answered by
watching that path from the moment the miss is born, instead of re-reading the tag.

---

## 2. The change — 38(a), the alloc snoop

A `renamed` bit travels with the miss through every structure that holds it, and
is set by the snoop term

```
snoop_hit(entry) = alloc_wen[entry.way] && (alloc_waddr == entry.set_id)
```

evaluated every cycle the entry is valid. Coverage, gapless by construction:

```
RS entry (alloc+1 .. retire)  ->  MSHR entry (issue .. refill_wen_r+1)  ->  Mux edge
   ->  array cycle R term (already captured today)  ->  array cycle R+1 live term
   ->  drain kill (unchanged today)
```

Interface deltas:

| module | add | remove |
|---|---|---|
| Reservation_Station | inputs `alloc_wen[ASSOC]`, `alloc_waddr[SET_INDEX_W]`; 1 bit `renamed` per entry (8); output `issue_renamed` | - |
| MSHR_Entry | 1 bit `renamed_r`; input `alloc_renamed`; output `renamed`; snoop inputs | - |
| MSHR_File | pass-through of `alloc_wen`/`alloc_waddr` to the four entries and `entry_renamed[4]` to the Mux | - |
| MSHR_Mux | output `refill_renamed`, registered from `entry_renamed[sel]` beside tag/set/way | - |
| Flag_Tag_Data_Array | input `refill_renamed`; `refill_stage_renamed_r` (1 flop) | `bank_refill_rtag_c`, `refill_rd_tag_r` (22 flops/way), the second read port on `bank_tags` |
| Cache | route the existing S2 grants into MSHR_File | - |

New logic: 8 + 4 + 1 x 4 ways = 16 flops, 12 compares of SET_INDEX_W (8 bits at
16 KB A4) plus a 4:1 one-hot select of `alloc_wen` per entry. Deleted: 88 flops and
four 256:1 x 22 read trees, and the `refill_set_id` broadcast to them.

**Timing of every new term.** `alloc_wen`/`alloc_waddr` are S2-registered
(Cache.sv, the same registers GEN_WAYS consume). The RS's alloc stage is S2 as
well (its CAM runs at S1 on `pre_line_addr`, "one cycle before alloc_valid"). So
the snoop compare is register-fed on both sides, which keeps it inside the Entry
30(b) discipline (decision terms from registers only). The entry's own alloc lands
in the same S2 cycle as its RS append and must not count: snooping `rs[i]` (the
registered array) rather than `rs_next` excludes the entry being appended for free,
since it is not in `rs` yet. Only one request is in S2 per cycle, so no other alloc
can hit the same {set, way} in that cycle.

**The array's new guard** (cycle R+1, from registers and one live S2 term):

```
refill_guard_ok_c = !refill_stage_renamed_r                       // carried bit
                 && !refill_alloc_hit_r                            // alloc on the R edge (captured today, unused since E35(e))
                 && !(alloc_wen && (alloc_waddr == refill_set_idx_r));  // alloc on the R+1 edge, live
```

Three flag terms and one 8-bit compare. No tag anywhere. This restores the two
E35(e)-dropped terms and closes the R-edge hole.

---

## 3. The new RTL — SKETCH ONLY, nothing written

**Reservation_Station.sv** (inside the existing rs -> rs_next construction; the bit
rides the struct, so the retire shift and the issue AND-OR mux carry it for free):

```
// SKETCH
for i: snoop_c[i] = rs[i].valid && alloc_wen[rs[i].way] && (alloc_waddr == rs[i].set_id);
       // set_id = line_addr[SET_INDEX_W-1:0], already how issue_set_id is formed
rs_next[i].renamed = rs[i].renamed | snoop_c[i];      // applied at the "this-cycle indexing"
                                                      // step, BEFORE the edge-A/edge-B shifts
append: rs_next[tail].renamed = 1'b0;
issue_renamed |= rs[i].renamed  (same AND-OR as issue_way)
```

**MSHR_Entry.sv** (E35(b) style: payload captures while free):

```
// SKETCH
if (!valid) renamed_n = alloc_renamed;                 // from issue_renamed
else        renamed_n = renamed_r | (alloc_wen[way] && (alloc_waddr == set_id));
output renamed = renamed_r;
```

**MSHR_Mux.sv**: `refill_renamed <= entry_renamed[sel];` in the reset-free payload
block, same edge as `refill_tag`.

**Flag_Tag_Data_Array.sv**: capture `refill_stage_renamed_r <= refill_renamed` under
`refill_wen` beside `refill_stage_tag_r`; the guard as in section 2; delete the
second read. `refill_stage_tag_r` and the `refill_tag` port STAY until the checker in
section 4 is retired (see the attempt-1 hypothesis there).

---

## 4. Equivalence and hazards

**Behavioural difference, exactly one.** A same-tag rename (A -> B -> A into the same
way while A's first fetch is in flight): the old guard passes, the snoop drops. Legal
under sub-line valid, and arguably the correct side, because A's in-flight fetch
carries pre-writeback data. The regression will therefore NOT be digit-identical
(E35(e) already crossed that bar for the same reason); the checker below counts the
events so the difference is attributable.

**Hazard 1 (found in this brainstorm): merges into a renamed entry serve stale data.**
The RS merges a new miss into any valid entry with the same line address; it does not
look at `in_progress`. Walk the sequence:

1. write-miss A word 0 (data D1): RS entry E_A allocates {set s, way w}, the array
   holds A with word 0 valid = D1, E_A fetches A from memory.
2. miss B into {s, w}: A is the victim, A's dirty word 0 is written back by B's
   MSHR, {s, w} is renamed to B. E_A's fetch, older on the memory port, returns
   memory's PRE-writeback word 0 (D0).
3. read A word 0: S1 sees tag B, misses, allocates; its CAM matches E_A by line
   address and MERGES as a waiter. The Dispacher serves waiters from FETCH data, not
   the array. The reader gets D0. Stale.

`renamed` is exactly the bit that says E_A can no longer take waiters:

```
merge_cand_c[i] = rs[i].valid && !rs[i].renamed && !snoop_c[i] && (line match) && (room)
```

The live `snoop_c[i]` term is needed for the back-to-back case: B's alloc is at S2
in the same cycle as the reader's CAM at S1, so the registered bit is one cycle too
late for a reader immediately behind the renamer. Both terms are register-fed. With
the renamed entry excluded, the reader appends a fresh entry whose fetch is issued
AFTER the writeback in memory-port order, so it returns D1. This turns the "open
question logged, not changed" in the notebook into part of 38(a). **[DECIDE]**:
include the merge exclusion in 38(a), or land the array guard first and the merge
exclusion as 38(a2). Recommendation: one entry, because the directed test below
exercises both and the second is three gates.

Waiters merged BEFORE the rename are correct: each asked for a word that was not
valid at the time (else it would have hit), so no CPU write preceded it and memory's
value is its program-order value.

**Hazard 2: two valid RS entries for one line.** After the exclusion, E_A (renamed)
and the reader's fresh entry coexist with the same `line_addr`. The CAM already
returns a bitmask, and the exclusion removes E_A from it, so exactly one candidate
remains. The vbuf slot arithmetic (`vbuf_head_r + i`) is per entry and unaffected.
Assert in sim: at most one candidate bit set.

**Hazard 3: the renamed entry's memory read is not wasted.** Its waiters are still
served from its fetch data; only the array write is dropped. Bandwidth is unchanged
from today.

**Hazard 4: the RS shift machinery.** The snoop result must be OR-ed into the entry
at the pre-shift ("this-cycle indexing") step so edge A / edge B shifts move it with
the entry. The same rule the merge candidates follow (Entry 30(b)); the 08-24 bug
about always_comb reading its own writes applies, so the snoop loop is its own loop.

**Hazard 5: X on the carried bit.** `renamed` in the RS and MSHR is payload and
follows the E29 discipline (no reset), but it is CONSUMED by a guard, so it must be
defined whenever `valid` is: append writes 0, MSHR capture-when-free copies a defined
value. `refill_stage_renamed_r` is read only under `refill_stage_v_r`, which keeps its
reset. Same argument as `refill_stage_tag_r` today.

**Checker kept under `ifndef SYNTHESIS`:** the deleted tag read and compare stay as
sim-only logic.

```
assert: refill_guard_ok_c (new)  ->  (refill_stage_tag_r == live_tag)   // new never passes what old would drop
count : (old compare passes) && !(new passes)                           // the same-tag rename, expected tiny, non-zero at 0.8
```

The E22 live-tag assertion (`+define+FTDA_E22_ASSERT`) comes back ON for the entry.

**Attempt 1 (08-25) hypothesis, to be confirmed by the checker.** It fired ~500x/job
with "tag 0 vs live, way 1, sets 0..24". A held tag of exactly 0 against a live tag
that differs, on the first sequential sets of Test1, looks like the assertion reading
`refill_stage_tag_r` after the `refill_tag` port had been removed (a dangling 0),
i.e. the assertion broke, not the guard. Hence: keep `refill_tag` on the interface
until the checker is retired, then remove both in a separate, digit-identical step.

---

## 5. Verification plan

1. **Directed test, Test11** (finding 1, 08-23), on the A1 DUT (direct-mapped, so any
   second tag in a set is a rename) and on A4 (exercises the way select in the snoop):
   - write-miss A (set s); before A's 20-cycle fetch lands, miss B into set s;
     then read A and read B. Expect: B correct; A re-fetched and correct; no stale
     word; the guard-alloc-kill INFO counter moves.
   - the hazard-1 extension: after B evicts A, read A word 0 (the dirty word) with
     the original A entry still in flight. Expect D1, and the merge-exclusion
     counter to move.
   - the same-tag case: A -> B -> A into the same way. Expect the same-tag counter
     to move and data correct.
   - run at 0.8 and 1.0.
2. **Regression:** `./verify.sh 0.8 && ./verify.sh 1.0`, all four blocks, FINAL REPORT
   PER ASSOCIATIVITY printed. Not digit-identical, by the one documented difference.
3. **Checker + E22 assertion** on for the whole regression; zero fires is the bar.
4. **Post-synthesis GLS** (run_gls.sh postsynth) on the new Genus netlist: cheap and
   it catches any `ifndef SYNTHESIS` leak into the guard.

---

## 6. Expected effect and cost

Genus (control = E37 no-cap fanout-32, `20260908_e37_nocap_fo32_...`, same recipe):
- census class `refill_set_id -> refill_rd_tag_r` gone; the worst-120 loses ~56
  entries; TNS and failing endpoints down.
- WNS unchanged: the floor is class 1 (S0 read, -524 equalised) and the SRAM
  half-cycle read into `COMPARE_SELECT_REPLACE_out_rdata_reg`. 38(a) does not touch
  either. Do not expect an Fmax move; expect a TNS / area / wire move.
- net area down: each `bank_tags` flop loses one of its two read cones.
- P&R: `refill_wen` / `refill_set_id` were the top startpoint family (388 of the
  worst 1000 in the e29 census); the broadcast to four read trees disappears.

Cost: 16 flops, 12 x 8-bit compares, one 4:1 select per RS/MSHR entry, one input
per array instance. Against 88 flops and four 256:1 x 22 trees deleted.

---

## 7. Dependencies and follow-ons

- Lands on E37. Fold into the same P&R iteration as the DRV rule change only if the
  Genus A/B is clean; otherwise it gets its own iteration (one variable per lap).
- **Enables 38(b) = E24, the structural move.** With the tag store at 1W + 1R it fits
  the data macro (`sram_1rw1r_32_256_8_sky130`, 256 x 32, tag 22 bits): port 0 =
  alloc write, port 1 = S0 read at `raddr`, data in S1 exactly like the data banks.
  Deletes the 256:1 x 22 S0 read tree (class 1, the wall on every meter since
  Entry 20), 22.5k of the netlist's 31.7k flops, the replica question, and the
  deepest clock-tree sinks (the tag banks, 9.6 ns at n40C on 19b). Macro count
  16 -> 20 (five per way, the quad floorplan's channel). Flags stay flops: they have
  three writers (alloc, CPU write, refill drain) and the macro has one write port.
  Two things to settle before 38(b): (i) the macro's `dout1` is a half-cycle path
  (launched on the falling edge), so the tag compare at S1 inherits the same
  penalty the data read already pays; the notebook's `clk1 = ~clk` experiment is
  the cheap answer; (ii) with tags in the macro, the sim-only live tag read for the
  checker needs a different source (the vendor model has no back door), so 38(a)'s
  checker must be retired before 38(b), which is why 38(a) lands first with its
  own verification.

---

## 8. Decision log

- 2026-08-23 finding 1: alloc-during-refill directed test identified as the missing
  test. Never written.
- 2026-08-25 E35(e): guard reduced to the tag compare; alloc-kill terms dropped;
  E22 assertion gated OFF after attempt 1 fired ~500x/job (undiagnosed).
- 2026-09-08 (notebook): 38(a) planned as the alloc snoop; 38(b) as macro tags.
- 2026-09-08 evening (this file): hazard 1 found, merge exclusion proposed as part of
  38(a); attempt-1 failure hypothesised as a broken assertion; rule set that
  `refill_tag` stays until the checker retires. **[DECIDE]** merge exclusion in
  38(a) or 38(a2). No RTL written.
