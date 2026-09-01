// ============================================================
// MSHR request arbiter
// Drains MSHR request streams in the order they become pending.
//
// This makes requests come out as contiguous per-MSHR bundles
// while preventing a younger low-ID MSHR from passing an older
// dirty writeback stream.
//
// Entry 23b (2026-08-23) - two retimings, one entry, both paid for
// by the sanctioned +1 miss-latency budget (20-cycle memory):
//
//   (A) The mem_req_* outputs are REGISTERED. The port pays 550 ps of
//       output budget (300 out-delay + 250 uncertainty) at the ASIC
//       signoff, and the wdata cone behind it (order_head -> order_q
//       -> head_idx -> wb slot/word -> vbuf -> word mux) was the
//       32-path -1584 class of the macro16 census. mem_req has NO
//       ready signal (no downstream backpressure, by design), so this
//       is a pure pipeline stage: every request ships one cycle
//       later, nothing can refuse it. `issued` deliberately stays
//       PRE-register: an entry's beat is done when it is CAPTURED,
//       and per-MSHR beat contiguity is preserved through a depth-1
//       stage. Alignment note: shifting requests shifts mem_resp_valid
//       and mem_resp_rdata together, so Delay_r(5) in Cache.sv - which
//       only maintains their RELATIVE alignment - is unchanged. (If a
//       regression ever shows wrong-data-no-structural-error here,
//       Delay_r is the first suspect.)
//
//   (B) The ENQUEUE is retimed. order_q_n was: head-advance pop (a
//       req_pending mux through order_q[head]) feeding a 4-iteration
//       SERIAL insert loop (each iteration's tail/count feeds the
//       next), rooted in issue_pending STATE DECODES from the entry
//       FSMs - the -1617/-1606/-1596 reg-to-reg WNS holders of the
//       macro16 census. Now the rise vector is registered (rise_r)
//       and the loop runs from it one cycle later: inserts start at
//       cycle start from clean flops. An entry becomes grantable one
//       cycle later than before; queue order still reflects rise
//       order (coarsened by one cycle - same-cycle ties break by
//       index, and tied entries are always different lines). An entry
//       is enqueued at most once per pending episode: rise_r is a
//       one-shot edge capture, pending cannot fall before first grant
//       (grants require queue residency), and pending spans the whole
//       W->R lifecycle so there is no mid-life re-rise.
//
// Entry 27 (2026-08-23 night) - the queue management and the
// writeback data read, the e26 census's two tied WNS holders.
//   27a (here): the worst path was order_head_r -> order_tail_r, 797
//   ps clk->Q + ~26 levels of pop mux feeding the 4-iteration SERIAL
//   insert loop. Two facts collapse it: AT MOST ONE entry can become
//   pending per cycle (the RS issues one entry per cycle,
//   issue_pending spans the whole W->R lifecycle, and a retired entry
//   re-rises only via a fresh RS issue), so rise_r is
//   one-hot-or-empty ($onehot0 asserted) and the loop is ONE encoded
//   insert (~4 levels); and the pop can run from REGISTERED pending
//   (req_pending_d) - the head advances one cycle after its entry
//   drains, live req_pending[head]=0 blocks any grant during the
//   stale cycle, so the only cost is one bubble at each stream end,
//   inside the same latency budget as Entry 23b.
//   27b (MSHR_File): the -1321 twin, order_head -> mem_req_wdata_reg
//   (~22 levels of head/slot/word/vbuf muxes into 23b's register), is
//   removed by PRE-READING the vbuf at the NEXT cycle's coordinates -
//   head_idx_n exported below (shallow after 27a), wb word from each
//   entry's existing wb_count_n - into a register, so wdata loads
//   register-to-register.
//   27b was STRUCK FOR GOOD 2026-08-24 (both revisions measured) - see
//   the tombstone in MSHR_File. head_idx_n dies with Entry 31 below,
//   which cannot express it: there is no next-state one-hot to read.
//
// Entry 31 (2026-08-24) - the head read is FLATTENED, not moved.
//   The surviving WNS class was order_head_r -> mem_req_wdata_reg, -911
//   ps / 21 levels / 4042 ps (29 of the worst 40 paths), plus
//   -> mem_req_addr_reg at -784. Anatomy: 800 ps CLK->Q, then 1664 ps /
//   12 levels of head decode + order_q mux + entry_wb_slot/word mux,
//   then 905 ps of slot broadcast (fo16 into the 128b vbuf mux), then
//   673 ps of actual data selection.
//
//   The cone is not LATE - every input is a register. It is DEEP: three
//   SERIAL indirections, each one's output being the next one's mux
//   ADDRESS, so every encoded index must be decoded before the mux
//   below it can start. 20 levels for 4:1 -> 4:1 -> 8:1 -> 4:1.
//
//   E27b proved the other repair is unavailable, and the rev-2 run
//   measures why: its front alone (order_head_n / order_q_n, i.e. the
//   pop compare and the insert mux) costs ~3.8 ns against 2464 ps for
//   the same function in CURRENT-state coordinates. Next-cycle
//   coordinates are a ~1300 ps tax. So flatten in place instead.
//
//   (a) order_q carries a ONE-HOT ENTRY VECTOR per position, not an
//       encoded id. 27a already established rise_r is one-hot-or-empty
//       and then ENCODED it to write order_q, which downstream DECODED
//       again; storing the one-hot deletes the encoder and every
//       decode below it. Fewer gates before it buys any timing.
//   (b) The head POINTER becomes a registered one-hot over ORDER
//       POSITIONS. Its next state is a rotate - pure wiring - under the
//       existing pop condition, so the pointer decode leaves the read
//       path. order_head_r/_n are deleted rather than kept alongside:
//       one register for the state means the two encodings cannot
//       drift.
//   (c) Every consumer becomes an AND-OR reduce from registers:
//       head_oh, the pop compare, the req_* selects, selected_onehot
//       (which was literally a decode of the index back to one-hot),
//       and MSHR_File's wb slot/word selects.
//
//   Same transform as Entry 13 (issue-side one-hot flattening), Entry
//   14 (one-hot slot) and Entry 21 (one-hot tag read). No retiming, no
//   latency, no next-state reach: this is a RE-ENCODING of the same
//   state, so verification must come out DIGIT-IDENTICAL. If it does
//   not, the transform is wrong - do not go looking at the testbench.
//
//   TWO SPACES, both MSHR_COUNT wide, easy to confuse when reading:
//     head_ptr_oh_r  is one-hot over ORDER POSITIONS (which slot of the
//                    queue is the head)
//     order_q_oh[p]  and head_oh are one-hot over ENTRIES (which MSHR)
// ============================================================

module MSHR_Request_Arbiter #(
    parameter int MSHR_COUNT    = 4,
    parameter int ADDR_WIDTH    = 32,
    parameter int DATA_WIDTH    = 32,
    parameter int MSHR_ID_WIDTH = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic [MSHR_COUNT-1:0]            req_valid,
    input  logic [MSHR_COUNT-1:0]            req_pending,
    input  logic [MSHR_COUNT-1:0]            req_write,
    input  logic [ADDR_WIDTH-1:0]            req_addr  [MSHR_COUNT],
    // Entry 23: one victim word, read by MSHR_File for the order-head
    // entry (see head_oh) - replaces the four identical per-entry data
    // lanes and the lane mux that selected among them.
    input  logic [DATA_WIDTH-1:0]            wb_data,
    input  logic [MSHR_ID_WIDTH-1:0]         req_id    [MSHR_COUNT],

    output logic [MSHR_COUNT-1:0]            issued,

    // Entry 23: the entry at the head of the ordering FIFO - the ONLY
    // entry a grant can ever go to - exported BEFORE the pending/valid
    // qualification so the victim-word read address is two register
    // muxes deep instead of hanging off the grant.
    // Entry 31: exported as a ONE-HOT over entries. It stays
    // unqualified by order_count_r for the reason above - qualifying it
    // would put the counter back into the read path.
    output logic [MSHR_COUNT-1:0]            head_oh,

    output logic                             mem_req_valid,
    output logic                             mem_req_write,
    output logic [ADDR_WIDTH-1:0]            mem_req_addr,
    output logic [DATA_WIDTH-1:0]            mem_req_wdata,
    output logic [MSHR_ID_WIDTH-1:0]         mem_req_id
);

    localparam int ORDER_COUNT_W = $clog2(MSHR_COUNT + 1);
    localparam int ORDER_PTR_W   = (MSHR_COUNT <= 1) ? 1 : $clog2(MSHR_COUNT);

    logic                         found_req;
    logic [MSHR_COUNT-1:0]        selected_onehot;
    logic                         selected_write;
    logic [ADDR_WIDTH-1:0]        selected_addr;
    logic [MSHR_ID_WIDTH-1:0]     selected_id;

    logic [MSHR_COUNT-1:0]        req_pending_d;
    // Entry 23b(B): registered one-shot of each entry's pending rise -
    // the insert loop's only data input, so it launches from flops.
    logic [MSHR_COUNT-1:0]        rise_r;
    // Entry 27a: rise_r is one-hot-or-empty. Entry 31 no longer encodes
    // it - it is stored as-is - so only the "any" term survives.
    logic                         rise_any_c;

    // Entry 31: the queue holds one-hot ENTRY vectors, one per position.
    logic [MSHR_COUNT-1:0]        order_q_oh   [MSHR_COUNT];
    logic [MSHR_COUNT-1:0]        order_q_oh_n [MSHR_COUNT];

    // Entry 31: head pointer as a one-hot over ORDER POSITIONS. This is
    // the only copy of the head state - there is no encoded twin to
    // drift against.
    logic [MSHR_COUNT-1:0]        head_ptr_oh_r;
    logic [MSHR_COUNT-1:0]        head_ptr_oh_n;

    // Entry 31: the head ENTRY, one-hot. Two AND-OR levels from flops.
    logic [MSHR_COUNT-1:0]        head_oh_c;
    logic                         head_qual_c;
    logic                         head_pop_c;

    logic [ORDER_PTR_W-1:0]       order_tail_r;
    logic [ORDER_COUNT_W-1:0]     order_count_r;

    logic [ORDER_PTR_W-1:0]       order_tail_n;
    logic [ORDER_COUNT_W-1:0]     order_count_n;

    function automatic logic [ORDER_PTR_W-1:0] ptr_inc(input logic [ORDER_PTR_W-1:0] ptr);
        begin
            if (ptr == ORDER_PTR_W'(MSHR_COUNT - 1))
                ptr_inc = '0;
            else
                ptr_inc = ptr + 1'b1;
        end
    endfunction

    // Entry 23b(A): the port-facing registers. Loaded from the same
    // cycle's grant; valid resets, payload doesn't need to.
    // Entry 29(o) (2026-08-25): the payload leaves the else-branch. The
    // reset VALUES were already gone (E29(n)), but sitting under `else`
    // kept rst as a hold-enable, and Genus folded it into the grant AND-OR
    // (e29cd: rst -> mem_req_addr -230 x32, -> mem_req_wdata -379 x32).
    // The port consumes the payload only under mem_req_valid, which keeps
    // its reset.
    always_ff @(posedge clk) begin
        if (rst) begin
            mem_req_valid <= 1'b0;
        end
        else begin
            mem_req_valid <= found_req;
        end
    end

    always_ff @(posedge clk) begin
        mem_req_write <= selected_write;
        mem_req_addr  <= selected_addr;
        mem_req_wdata <= wb_data;
        mem_req_id    <= selected_id;
    end

    // Entry 31: the head read. Both operands are registers and the
    // pointer arrives pre-decoded, so this is one AND plus one OR tree -
    // it replaces a 4:1 mux whose 2-bit select had to be decoded first.
    //
    // Accumulate discipline (the Entry 30(b) trap): initialise, then
    // |= in order. Every read sees only what THIS activation has
    // already written. Never read an element the loop has not reached.
    always_comb begin
        head_oh_c = '0;
        for (int p = 0; p < MSHR_COUNT; p++) begin
            head_oh_c |= order_q_oh[p] & {MSHR_COUNT{head_ptr_oh_r[p]}};
        end
    end

    assign head_oh = head_oh_c;

    // PRE-register on purpose - see header (A).
    assign issued = found_req ? selected_onehot : '0;

    // Entry 31: the grant. Every [selected_idx] mux below used to force
    // a decode of an index that had just been muxed out of order_q;
    // head_oh_c already IS that decode, so the selects collapse to
    // AND-OR reduces and selected_onehot stops being computed at all -
    // it was literally the index encoded back into the one-hot we now
    // hold. This is what moves the -784 mem_req_addr class too.
    assign head_qual_c = |(head_oh_c & req_pending & req_valid);

    // Entry 29(n) (2026-08-25): the PAYLOAD is no longer cleared when
    // there is no grant. selected_write/addr/id used to be zeroed unless
    // found_req, which put order_count_r and head_qual_c - the latter
    // reaching into every entry's FSM state decode and victim_word_valid
    // beat-skip mask - on the D of 64 port flops (mem_req_wdata -500,
    // mem_req_addr -447 in the baseline census). They are now the bare
    // AND-OR over head_oh_c, i.e. two levels from flops, and found_req
    // qualifies only what it must: mem_req_valid and issued. The port
    // is valid-qualified by contract - RAM_ID samples the payload only
    // under req_valid, and the TB monitor prints it only under
    // mem_req_valid - so an unqualified payload on idle cycles is a
    // defined don't-care, exactly like wb_data already was.
    assign found_req = (order_count_r != '0) && head_qual_c;

    always_comb begin
        selected_write = 1'b0;
        selected_addr  = '0;
        selected_id    = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            selected_write |= req_write[i] & head_oh_c[i];
            selected_addr  |= req_addr [i] & {ADDR_WIDTH{head_oh_c[i]}};
            selected_id    |= req_id   [i] & {MSHR_ID_WIDTH{head_oh_c[i]}};
        end
    end

    assign selected_onehot = head_oh_c;

    // Entry 31: the OR-encoder that turned rise_r into an index is gone.
    // The queue stores the one-hot directly, so only the "any" term is
    // still needed - to gate the insert.
    assign rise_any_c = |rise_r;

    // Entry 31: the pop compare was req_pending_d[order_q[order_head_r]]
    // - two chained muxes on the pointer. It is now one AND-OR reduce
    // against the head one-hot we already have.
    assign head_pop_c = (order_count_r != '0) && !(|(head_oh_c & req_pending_d));

    always_comb begin
        order_q_oh_n  = order_q_oh;
        head_ptr_oh_n = head_ptr_oh_r;
        order_tail_n  = order_tail_r;
        order_count_n = order_count_r;

        // Entry 27a: pop from REGISTERED pending, launched at cycle
        // start. Entry 31: advancing the head is now a ROTATE of the
        // one-hot pointer - wiring, not an incrementer. Written as an
        // indexed loop rather than a slice-and-concat so it stays legal
        // at MSHR_COUNT == 1, where [MSHR_COUNT-2:0] would not be.
        if (head_pop_c) begin
            for (int p = 0; p < MSHR_COUNT; p++) begin
                head_ptr_oh_n[(p + 1) % MSHR_COUNT] = head_ptr_oh_r[p];
            end
            order_count_n = order_count_r - 1'b1;
        end

        // Entry 27a: single insert (rise_r one-hot-or-empty). Pop moves
        // head, insert writes at tail - no slot conflict; the full-check
        // uses the post-pop count. Entry 31: rise_r is stored verbatim,
        // with no encode on the way in and no decode on the way out.
        if (rise_any_c &&
            (order_count_n != ORDER_COUNT_W'(MSHR_COUNT))) begin
            order_q_oh_n[order_tail_r] = rise_r;
            order_tail_n               = ptr_inc(order_tail_r);
            order_count_n              = order_count_n + 1'b1;
        end
    end

`ifndef SYNTHESIS
    // Entry 27a's load-bearing invariant: one pending rise per cycle.
    always_ff @(posedge clk) begin
        if (!rst) begin
            assert ($onehot0(rise_r))
                else $error("ARB E27a: rise_r %b not one-hot-or-empty", rise_r);
        end
    end

    // Entry 31's two invariants. The pointer is a rotating one-hot and
    // is NEVER empty - if it ever is, the rotate has lost a bit and the
    // head read silently returns nothing. head_oh follows from it and
    // from the queue contents, so it is one-hot-or-EMPTY: empty is the
    // legitimate post-reset / unwritten-position case, which the
    // order_count_r guard covers.
    always_ff @(posedge clk) begin
        if (!rst) begin
            assert ($onehot(head_ptr_oh_r))
                else $error("ARB E31: head_ptr_oh_r %b not one-hot", head_ptr_oh_r);
            // Entry 29(i): qualified by the same order_count_r guard the
            // hardware uses - an unoccupied head position is X in sim.
            if (order_count_r != '0) begin
                assert ($onehot0(head_oh_c))
                    else $error("ARB E31: head_oh_c %b not one-hot-or-empty", head_oh_c);
            end
        end
    end
`endif

    // Entry 29(c): synchronous reset (was async). Reset VALUES and branches
    // are unchanged - this is a cell-mapping edit: an async reset pin is
    // architectural (dfrtp/sdfrtp/dfstp), a sync one Genus folds into the
    // D-side logic and maps to dfxtp.
    always_ff @(posedge clk) begin
        if (rst) begin
            // Entry 31: position 0 is the head out of reset, the same
            // state order_head_r <= '0 used to encode.
            head_ptr_oh_r <= MSHR_COUNT'(1);
            order_tail_r  <= '0;
            order_count_r <= '0;
        end
        else begin
            head_ptr_oh_r <= head_ptr_oh_n;
            order_tail_r  <= order_tail_n;
            order_count_r <= order_count_n;
        end
    end

    // Entry 29(i) (2026-08-25): the queue CONTENTS are reset-free; the
    // three registers above (pointer, tail, count) are the roots.
    // Entry 31 noted that '0 in a position means NO ENTRY and that the
    // order_count_r guard is what keeps anyone from reading an
    // unoccupied position - so the reset value was already inert. A
    // position is read only through head_oh_c, and every consumer of
    // head_oh_c is qualified by order_count_r != 0 (found_req,
    // head_pop_c); positions [head, head+count) are always written
    // before count covers them. MSHR_File's wb_slot/word selects read
    // head_oh unqualified, but only into a don't-care (a beat leaves
    // only on a grant, and RAM_ID samples wdata only on valid && write).
    // Sim: an X position under count = 0 gives head_oh_c = X, and
    // (count != 0) && X = 0 - no X-luck, the guard is a plain AND.
    // The $onehot0(head_oh_c) assertion below is now qualified by the
    // same guard, because $onehot0 of X fails.
    always_ff @(posedge clk) begin
        for (int i = 0; i < MSHR_COUNT; i++) begin
            order_q_oh[i] <= order_q_oh_n[i];
        end
    end

    // Entry 29(e) (2026-08-25): the pending edge-detector loses its
    // reset. req_pending is each MSHR entry's issue_pending, a decode of
    // its FSM state, which keeps its reset: pending is 0 at the first
    // reset edge, so req_pending_d is 0 at the second and rise_r
    // (pending & ~pending_d) at the third - rst is held five. A random
    // rise_r during the flush cycles can only steer the insert into
    // order_q_oh / order_tail_r / order_count_r, all reset-held above,
    // where rst wins. The queue registers themselves KEEP their reset:
    // they are the arbiter's roots.
    always_ff @(posedge clk) begin
        req_pending_d <= req_pending;
        rise_r        <= req_pending & ~req_pending_d;
    end

endmodule
