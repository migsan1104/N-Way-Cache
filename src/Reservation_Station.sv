// ============================================================
// Reservation_Station
//
// Ordered RS queue:
//   rs[0] is oldest.
//   New entries insert at tail.
//   Retired entries are removed by shifting younger entries down.
//
// No age counter.
// No oldest-age comparator.
// Issue picks first valid entry that is not in_progress.
//
// Same-line READ and Write misses can merge into cpu_ids / word_ids.
//
// Victim data (dirty/tag/word_valid/line) does NOT shift: it lives in
// a static circular side-buffer (see "Victim side-buffer" below), and
// slot ownership is implied by queue position.
//


module Reservation_Station #(
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int MSHR_ID_WIDTH   = 2,
    parameter int RS_DEPTH        = 16,
    parameter int MSHR_AF         = 7,
    parameter int MAX_WAITERS     = 4,

    // Entry 15, piece 2: one victim-buffer copy per consumer (MSHR
    // entry), so each read lands beside the entry that captures it
    // instead of one 155-bit net spanning all of them.
    parameter int VBUF_RD_PORTS   = 4,

    localparam int RS_ID_WIDTH    = (RS_DEPTH <= 1) ? 1 : $clog2(RS_DEPTH),
    localparam int WAITER_COUNT_W = $clog2(MAX_WAITERS + 1),
    localparam int COUNT_W        = $clog2(RS_DEPTH + 1)
)(
    input  logic clk,
    input  logic rst,

    input  logic                       alloc_valid,
    output logic                       alloc_ready,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,

    // Line address of the request ONE STAGE BEHIND alloc_* — the one in
    // the compare stage right now (Entry 11). alloc_line_addr is this
    // value registered once upstream, so the same-line CAM can run a
    // cycle early against it and hand S4 a registered answer.
    input  logic [LINE_ADDR_WIDTH-1:0] pre_line_addr,
    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,
    input  logic                       alloc_write,
    input  logic [DATA_WIDTH-1:0]      alloc_wdata,
    input  logic [CPU_ID_WIDTH-1:0]    alloc_cpu_req_id,

    input  logic                       alloc_victim_dirty,
    input  logic [TAG_WIDTH-1:0]       alloc_victim_tag,
    input  logic [LINE_WIDTH-1:0]      alloc_victim_line,
    input  logic [LINE_WIDTH/DATA_WIDTH-1:0] alloc_victim_word_valid,

    output logic                       issue_valid,
    input  logic                       issue_accept,
    input  logic [MSHR_ID_WIDTH-1:0]   issue_mshr_id,

    output logic [RS_ID_WIDTH-1:0]     issue_rs_id,
    output logic [LINE_ADDR_WIDTH-1:0] issue_line_addr,
    output logic [SET_INDEX_W-1:0]     issue_set_id,
    output logic [TAG_WIDTH-1:0]       issue_tag,
    output logic [WAY_INDEX_W-1:0]     issue_way,

    output logic                       issue_write,
    output logic [DATA_WIDTH-1:0]      issue_wdata,
    output logic [WORD_OFFSET_W-1:0]   issue_word_id,

    output logic                       issue_victim_dirty      [VBUF_RD_PORTS],
    output logic [TAG_WIDTH-1:0]       issue_victim_tag        [VBUF_RD_PORTS],
    output logic [LINE_WIDTH-1:0]      issue_victim_line       [VBUF_RD_PORTS],
    output logic [LINE_WIDTH/DATA_WIDTH-1:0] issue_victim_word_valid [VBUF_RD_PORTS],

    input  logic                       retire_valid,
    input  logic [MSHR_ID_WIDTH-1:0]   retire_mshr_id,

    output logic                       dispatch_valid,
    output logic [WAITER_COUNT_W-1:0]  dispatch_cpu_id_count,
    output logic [CPU_ID_WIDTH-1:0]    dispatch_cpu_ids  [MAX_WAITERS],
    output logic [WORD_OFFSET_W-1:0]   dispatch_word_ids [MAX_WAITERS]
);

    typedef struct {
        logic                       valid;
        logic                       in_progress;
        logic [MSHR_ID_WIDTH-1:0]   mshr_id;

        logic [LINE_ADDR_WIDTH-1:0] line_addr;
        logic [WAY_INDEX_W-1:0]     way;

        logic                       write;
        logic [DATA_WIDTH-1:0]      wdata;
        logic [WORD_OFFSET_W-1:0]   word_id;

        logic [WAITER_COUNT_W-1:0]  cpu_id_count;
        logic [CPU_ID_WIDTH-1:0]    cpu_ids  [MAX_WAITERS];
        logic [WORD_OFFSET_W-1:0]   word_ids [MAX_WAITERS];
    } rs_entry_t;

    rs_entry_t rs [RS_DEPTH];
    rs_entry_t rs_next [RS_DEPTH];

    // ---- Victim side-buffer (Entry 8) ---------------------------------
    // Victim data is write-once at alloc, read-once at issue, so it lives
    // in a STATIC circular buffer instead of shifting with the queue. The
    // RS's hard-coded FIFO discipline (append at tail, retire always rs[0]
    // via the shift) makes slot ownership pure arithmetic: rs[i]'s slot is
    // vbuf_head_r + i. head advances on retire (that IS the free), tail on
    // new-entry alloc; merges create no entry and consume no slot. The
    // natural pointer wrap requires RS_DEPTH be a power of two (asserted).
    localparam int VBUF_W = 1 + TAG_WIDTH + (LINE_WIDTH/DATA_WIDTH) + LINE_WIDTH;

    logic [RS_ID_WIDTH-1:0] vbuf_head_r, vbuf_tail_r;

    logic [COUNT_W-1:0] valid_count;
    logic [COUNT_W-1:0] tail_idx_after_retire;
    logic almost_full;

    logic [RS_DEPTH-1:0] same_line_match;
    logic [RS_DEPTH-1:0] same_line_merge_ok;
    logic [RS_DEPTH-1:0] merge_sel;
    logic can_merge;

    logic alloc_fire;
    logic issue_fire;

    logic [RS_DEPTH-1:0] issue_update_sel;

    // Entry 11 rider: valid_count is a maintained counter, not a popcount
    // over rs[].valid. Occupancy changes through exactly two events - a
    // new entry appends (an alloc that cannot merge) and a retire shifts
    // one out (dispatch_valid implies rs[0].valid, so the decrement is
    // never spurious); merges consume no entry. The popcount tree fed
    // both the alloc-slot decode and almost_full -> alloc_ready ->
    // cpu_req_ready - the absorption credit that soaks up in-flight
    // requests; its value is cycle-identical here, just register-fed.
    // Guarded by the reference popcount assertion at the bottom.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_count <= '0;
        end
        else begin
            valid_count <= valid_count
                           + ((alloc_fire && !can_merge) ? COUNT_W'(1) : '0)
                           - (dispatch_valid ? COUNT_W'(1) : '0);
        end
    end

    assign almost_full = (valid_count >= COUNT_W'(RS_DEPTH - MSHR_AF));
    assign alloc_ready = !almost_full;

    assign alloc_fire = alloc_valid;
    assign issue_fire = issue_valid && issue_accept;

    // ---- Same-line CAM, precomputed a cycle early (Entry 11) ------------
    //
    // The wide compare (RS_DEPTH x LINE_ADDR_WIDTH) does not need to know
    // the request MISSED - it only needs the request's line address, and
    // that exists a full cycle before alloc_valid does: pre_line_addr is
    // the compare-stage flops, alloc_line_addr is the same value
    // registered once more. So the CAM runs against pre_line_addr and
    // REGISTERS its 16-bit answer; S4 starts from flops instead of
    // launching the compare after the S3->S4 edge and fanning the result
    // into every entry's write steering.
    //
    // It runs free - no enable, no handshake, computed every cycle like
    // the pipeline registers feeding it (this pipe never stalls; the RS's
    // own almost-full credit is the absorption buffer). A bubble cycle
    // just computes an answer nobody reads.
    //
    // One cycle passes between computing and using, and rs[] can change
    // at that edge in exactly three ways. Two need a patch, one doesn't:
    //
    //   1. A retire shifted every entry down one slot -> shift the
    //      registered vector the same way (pre_shifted_r, mirror of the
    //      merge_sel shift below).
    //   2. The request AHEAD of us appended a new entry at that edge. Its
    //      slot's precomputed bit compared a dead entry's stale address,
    //      so OVERRIDE that one bit (not OR) with a flop-vs-flop compare
    //      of the elder's line against ours.
    //   3. A merge only bumps a waiter count - line addresses untouched,
    //      and the count/valid gates below read the CURRENT flops anyway.
    //
    // The valid gate stays in S4 on purpose (it is register-fed, i.e.
    // free): retiring shifts entries down without clearing line_addr, so
    // a dead entry still holds a stale address. Matching it would merge a
    // new miss into an entry that will never issue, losing the request.
    logic [RS_DEPTH-1:0] pre_match_r;         // CAM answer, captured at the edge
    logic [RS_DEPTH-1:0] elder_slot_onehot_r; // elder's alloc slot, DECODED (Entry 14)
    logic                elder_same_line_r;   // elder's line == ours?

    logic [RS_DEPTH-1:0] pre_match_shifted_c;

    // Entry 14, piece 1: the two 1-bit steering flags fanned out from
    // single flops into every entry's steering cone (~1600 endpoints -
    // the measured 434+115-path routing populations). Explicit KEPT
    // copies, one per E14_GRP-entry group: the single-stage fanout_dup
    // pattern from optimization_knobs.md. Every copy loads the same D on
    // the same edge, so behavior is identical; `keep` is load-bearing -
    // without it synthesis merges the copies back into one flop and the
    // split never happens.
    localparam int E14_DUP = 4;
    localparam int E14_GRP = RS_DEPTH / E14_DUP;

    (* keep = "true" *) logic [E14_DUP-1:0] pre_shifted_dup_r;
    (* keep = "true" *) logic [E14_DUP-1:0] elder_alloc_dup_r;

    // Data regs run free (no reset), like the pipeline registers upstream.
    // Entry 14, piece 2: the elder's slot registers as a DECODED one-hot.
    // tail_idx_after_retire is register-fed (the counter + dispatch), so
    // the decode is free on the D side - and S4's override select drops
    // from a 5-bit compare per entry to one private AND per entry.
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            pre_match_r[i]         <= (rs[i].line_addr == pre_line_addr);
            elder_slot_onehot_r[i] <= (COUNT_W'(i) == tail_idx_after_retire);
        end
        elder_same_line_r <= (alloc_line_addr == pre_line_addr);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pre_shifted_dup_r <= '0;
            elder_alloc_dup_r <= '0;
        end
        else begin
            for (int d = 0; d < E14_DUP; d++) begin
                pre_shifted_dup_r[d] <= dispatch_valid;
                elder_alloc_dup_r[d] <= alloc_fire && !can_merge;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            pre_match_shifted_c[i] =
                pre_shifted_dup_r[i / E14_GRP]
                    ? ((i == RS_DEPTH-1) ? 1'b0 : pre_match_r[(i+1) % RS_DEPTH])
                    : pre_match_r[i];

            same_line_match[i] =
                rs[i].valid &&
                ((elder_alloc_dup_r[i / E14_GRP] && elder_slot_onehot_r[i])
                     ? elder_same_line_r
                     : pre_match_shifted_c[i]);
        end
    end

    // An entry can take another waiter only if it matches and its list is not
    // full. At most one bit of this can ever be set: a duplicate entry is only
    // created because the newest match was already full, and a full entry
    // stays full until it retires - so among duplicates, only the newest can
    // have room. That one-hot property is what lets the merge path skip the
    // priority encoder entirely; the assertion below guards it.
    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            same_line_merge_ok[i] =
                same_line_match[i] &&
                (rs[i].cpu_id_count < WAITER_COUNT_W'(MAX_WAITERS));
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!rst) begin
            assert ($onehot0(same_line_merge_ok))
                else $error("RS: same_line_merge_ok not one-hot (%b)",
                            same_line_merge_ok);
        end
    end
`endif


    assign dispatch_valid = retire_valid;

    // Retire shifts every entry down one slot, so the merge select shifts with
    // it. If the mergeable entry is rs[0] and it is retiring this very cycle,
    // the shift drops the bit and can_merge falls to 0 - the request simply
    // allocates a fresh entry instead of merging into one that no longer
    // exists. (The old index arithmetic wrapped 0-1 around to 15 here and
    // scribbled on an unrelated entry.)
    assign merge_sel = dispatch_valid ? (same_line_merge_ok >> 1)
                                      : same_line_merge_ok;

    assign can_merge = |merge_sel;

    // ---- Issue select, one-hot form (Entry 13) --------------------------
    // Was: a serial priority scan (each iteration's condition consumed the
    // previous iteration's issue_valid - a 16-stage ripple producing a
    // BINARY id), then rs[issue_rs_id] dynamic-index muxes and a
    // vbuf_head_r + issue_rs_id adder AFTER the ripple. That chain fed
    // the 129-bit victim capture in the MSHR - the measured worst
    // population after Entries 11+12 (rs -> victim_line_r, 451/1000 A8).
    // Now: the same prefix trick as the CSR's first-free way - "entry i
    // wins iff it is a candidate and no candidate exists below it" -
    // every bit independent (~3 levels), and the grant drives flat
    // AND-OR muxes directly. Sound because the grant is one-hot by
    // construction; armed by the assertion at the bottom. On no-grant
    // cycles the fields read as zeros instead of rs[0]'s fields - dead
    // values either way (nothing consumes them without issue_valid).
    logic [RS_DEPTH-1:0] issue_cand_c;
    logic [RS_DEPTH-1:0] issue_grant_c;

    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            issue_cand_c[i] = rs[i].valid && !rs[i].in_progress;
        end
    end

    // Entry 15, piece 1: the Entry 13 prefix was written flat but Vivado
    // re-serialized it through shared subexpressions - the measured worst
    // path walked SIX LUTs of chained ORs where the RTL meant three
    // levels. Same lesson as fanout_dup, applied to logic: what the RTL
    // implies, the optimizer undoes unless pinned. So the prefix is now
    // explicitly two-tier with a KEPT chunk layer: "any candidate in
    // chunk j" is one 4-input OR (kept, so it cannot be dissolved and
    // re-shared), and each grant bit needs only its own candidate, the
    // in-chunk bits below it (<=3), and the chunk-ORs below it (<=3) -
    // at most 7 inputs, <=2 LUTs after the kept layer. Depth is pinned
    // at ~3 levels no matter what the optimizer prefers.
    localparam int E15_CHUNK  = 4;
    localparam int E15_NCHUNK = RS_DEPTH / E15_CHUNK;

    (* keep = "true" *) logic [E15_NCHUNK-1:0] issue_chunk_any_c;

    generate
        for (genvar gc = 0; gc < E15_NCHUNK; gc++) begin : g_chunk_any
            assign issue_chunk_any_c[gc] =
                |issue_cand_c[gc*E15_CHUNK +: E15_CHUNK];
        end
    endgenerate

    generate
        for (genvar gi = 0; gi < RS_DEPTH; gi++) begin : g_issue_grant
            localparam int GC = gi / E15_CHUNK;
            localparam int GB = gi % E15_CHUNK;

            if (GC == 0 && GB == 0) begin : g_first
                assign issue_grant_c[0] = issue_cand_c[0];
            end
            else if (GC == 0) begin : g_chunk0
                assign issue_grant_c[gi] =
                    issue_cand_c[gi] && !(|issue_cand_c[GB-1:0]);
            end
            else if (GB == 0) begin : g_chunk_head
                assign issue_grant_c[gi] =
                    issue_cand_c[gi] && !(|issue_chunk_any_c[GC-1:0]);
            end
            else begin : g_rest
                assign issue_grant_c[gi] =
                    issue_cand_c[gi] &&
                    !(|issue_chunk_any_c[GC-1:0]) &&
                    !(|issue_cand_c[GC*E15_CHUNK +: GB]);
            end
        end
    endgenerate

    assign issue_valid = |issue_chunk_any_c;

    // Binary id survives only for the issue_rs_id output port - OR-encode
    // off the critical path (same onehot_to_idx form as the CSR).
    always_comb begin
        issue_rs_id = '0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_grant_c[i]) begin
                issue_rs_id |= RS_ID_WIDTH'(i);
            end
        end
    end

    always_comb begin
        issue_line_addr = '0;
        issue_way       = '0;
        issue_write     = 1'b0;
        issue_wdata     = '0;
        issue_word_id   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_grant_c[i]) begin
                issue_line_addr |= rs[i].line_addr;
                issue_way       |= rs[i].way;
                issue_write     |= rs[i].write;
                issue_wdata     |= rs[i].wdata;
                issue_word_id   |= rs[i].word_id;
            end
        end
    end

    assign issue_set_id = issue_line_addr[SET_INDEX_W-1:0];
    assign issue_tag    = issue_line_addr[LINE_ADDR_WIDTH-1:SET_INDEX_W];

    // The vbuf slot address loses its serial adder (Entry 13):
    // vbuf_head_r + i is a flop plus a CONSTANT, so all 16 candidate
    // addresses exist early and the grant just picks one - AND-OR
    // instead of encode-then-add. Entry 17 moved the picking itself
    // into each vbuf copy (see g_vbuf below); only the early per-slot
    // addresses are shared.
    logic [RS_ID_WIDTH-1:0] slot_addr_c [RS_DEPTH];

    generate
        for (genvar gs = 0; gs < RS_DEPTH; gs++) begin : g_slot_addr
            assign slot_addr_c[gs] =
                RS_ID_WIDTH'(vbuf_head_r + RS_ID_WIDTH'(gs));
        end
    endgenerate


    assign dispatch_cpu_id_count = rs[0].cpu_id_count;

    always_comb begin
        for (int i = 0; i < MAX_WAITERS; i++) begin
            dispatch_cpu_ids[i]  = rs[0].cpu_ids[i];
            dispatch_word_ids[i] = rs[0].word_ids[i];
        end
    end

    always_comb begin
        rs_next = rs;

        tail_idx_after_retire = valid_count;

        if (dispatch_valid) begin
            for (int i = 0; i < RS_DEPTH-1; i++) begin
                    rs_next[i] = rs[i+1];    
            end

            rs_next[RS_DEPTH-1].valid        = 1'b0;
            rs_next[RS_DEPTH-1].in_progress  = 1'b0;
            rs_next[RS_DEPTH-1].cpu_id_count = '0;

            tail_idx_after_retire = valid_count - 1'b1;
        end

        // Entry 13: same shift trick as merge_sel - a retire at this edge
        // moves the granted entry down one slot. (The old binary form's
        // 0-1 wrap was unreachable for the same reason it is here: a
        // retiring rs[0] is in_progress, so it is never the grant.)
        issue_update_sel = dispatch_valid ? (issue_grant_c >> 1)
                                          : issue_grant_c;

        if (issue_fire) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                if (issue_update_sel[i]) begin
                    rs_next[i].in_progress = 1'b1;
                    rs_next[i].mshr_id     = issue_mshr_id;
                end
            end
        end

        if (alloc_fire) begin
            if (can_merge) begin
                // One-hot select, so each entry decides for itself - no index
                // arithmetic and no chained dynamic indexing. rs_next already
                // holds the post-retire state, so its own cpu_id_count is the
                // right slot to fill.
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (merge_sel[i]) begin
                        rs_next[i].cpu_ids [rs_next[i].cpu_id_count] = alloc_cpu_req_id;
                        rs_next[i].word_ids[rs_next[i].cpu_id_count] = alloc_word_id;
                        rs_next[i].cpu_id_count =
                            rs_next[i].cpu_id_count + 1'b1;
                    end
                end
            end
            else  begin
                rs_next[tail_idx_after_retire].valid        = 1'b1;
                rs_next[tail_idx_after_retire].in_progress  = 1'b0;
                rs_next[tail_idx_after_retire].mshr_id      = '0;

                rs_next[tail_idx_after_retire].line_addr    = alloc_line_addr;
                rs_next[tail_idx_after_retire].way          = alloc_way;

                rs_next[tail_idx_after_retire].write        = alloc_write;
                rs_next[tail_idx_after_retire].wdata        = alloc_wdata;
                rs_next[tail_idx_after_retire].word_id      = alloc_word_id;

                rs_next[tail_idx_after_retire].cpu_id_count = WAITER_COUNT_W'(1);
                rs_next[tail_idx_after_retire].cpu_ids[0]   = alloc_cpu_req_id;
                rs_next[tail_idx_after_retire].word_ids[0]  = alloc_word_id;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                rs[i].valid        <= 1'b0;
                rs[i].in_progress  <= 1'b0;
                rs[i].cpu_id_count <= '0;
            end
        end
        else begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                rs[i] <= rs_next[i];
            end
        end
    end

    // Entry 15, piece 2 / Entry 17: VBUF_RD_PORTS identical copies of
    // the buffer, every one written by the same alloc on the same edge,
    // each read by exactly one MSHR entry. A replicated RAM written
    // identically IS the original RAM - behavior unchanged, only the
    // 155-bit read route shrinks (0.45-0.49 ns of the measured worst
    // path).
    //
    // Entry 17 post-mortem of the Entry 15 attempt, for the record: the
    // copies' read outputs are PROVABLY EQUIVALENT nets, and opt_design
    // merged them back into one driver and swept the redundant storage
    // - the measurement showed ENTRY[0] and ENTRY[1] reading the same
    // g_vbuf[2] cells and LUTAsMem unchanged to the digit. `keep` is a
    // synthesis attribute; surviving IMPLEMENTATION-stage optimization
    // takes DONT_TOUCH, on both the read data and each copy's address.
    //
    // Each copy also owns its OWN address tree (Entry 17): four real
    // copies sharing one address net would multiply that net's fanout
    // by four (156 -> ~620 pins); a private tree per copy keeps the
    // fanout at one copy's pins and places beside its RAM. The tree is
    // the pinned two-tier masked-OR (the Entry 15 piece-1 discipline):
    // kept per-4-slot partials, one final OR - the measured 3-LUT
    // serial OR chain becomes 2 pinned levels.
    // ---- ISOLATION EXPERIMENT (2026-08-21) ----------------------------
    // Entry 17's pins (per-copy DONT_TOUCH read nets + private pinned
    // address trees) are TEMPORARILY reverted to the Entry 15 shape to
    // attribute the E16+E17 measured regression (A4 -8.8% / A8 -5.5%,
    // global placement damage) between the two entries. In this shape
    // the tools re-merge the copies (the known Entry 15 outcome) - that
    // is the point: this build is "Entry 16 only" physically. Entry 17's
    // pinned form is preserved in git history and notebook Entry 17.
    logic [RS_ID_WIDTH-1:0] vbuf_issue_addr_c;

    always_comb begin
        vbuf_issue_addr_c = '0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_grant_c[i]) begin
                vbuf_issue_addr_c |= slot_addr_c[i];
            end
        end
    end

    generate
        for (genvar gv = 0; gv < VBUF_RD_PORTS; gv++) begin : g_vbuf
            // One write port, no reset, no other drivers: LUTRAM-
            // inferable.
            (* ram_style = "distributed" *)
            logic [VBUF_W-1:0] vbuf [0:RS_DEPTH-1];

            always_ff @(posedge clk) begin
                if (alloc_fire && !can_merge) begin
                    vbuf[vbuf_tail_r] <=
                        {alloc_victim_dirty, alloc_victim_tag,
                         alloc_victim_word_valid, alloc_victim_line};
                end
            end

            assign {issue_victim_dirty[gv], issue_victim_tag[gv],
                    issue_victim_word_valid[gv], issue_victim_line[gv]} =
                vbuf[vbuf_issue_addr_c];
        end
    endgenerate

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vbuf_head_r <= '0;
            vbuf_tail_r <= '0;
        end
        else begin
            if (dispatch_valid) begin
                vbuf_head_r <= vbuf_head_r + 1'b1;
            end
            if (alloc_fire && !can_merge) begin
                vbuf_tail_r <= vbuf_tail_r + 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (RS_DEPTH == (1 << RS_ID_WIDTH))
            else $fatal(1, "RS: RS_DEPTH must be a power of two (vbuf wrap)");
    end

    // Slot arithmetic sanity: pointer occupancy tracks valid_count mod
    // RS_DEPTH (full and empty both read 0 - never disambiguated here).
    always_ff @(posedge clk) begin
        if (!rst) begin
            assert (RS_ID_WIDTH'(vbuf_tail_r - vbuf_head_r) ==
                    RS_ID_WIDTH'(valid_count))
                else $error("RS: vbuf desync (head %0d tail %0d count %0d)",
                            vbuf_head_r, vbuf_tail_r, valid_count);
        end
    end

    // Entry 11 equivalence check (sim-only; every synthesis flow defines
    // SYNTHESIS): the retired combinational forms - the live CAM against
    // alloc_line_addr and the popcount over rs[].valid - survive here as
    // a reference model, compared cycle for cycle against the registered
    // precompute and the maintained counter. Unconditional on purpose:
    // the equivalence holds on bubble cycles too (the upstream pipeline
    // registers load every cycle), so any divergence names the exact
    // cycle instead of hiding until the next allocation reads it. Both
    // sides gate on rs[i].valid, which also keeps never-written
    // line_addr X-state out of the comparison.
    logic [RS_DEPTH-1:0] ref_same_line_match_c;
    logic [COUNT_W-1:0]  ref_valid_count_c;

    always_comb begin
        ref_valid_count_c = '0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            ref_same_line_match_c[i] =
                rs[i].valid && (rs[i].line_addr == alloc_line_addr);
            ref_valid_count_c = ref_valid_count_c + COUNT_W'(rs[i].valid);
        end
    end

    always_ff @(posedge clk) begin
        if (!rst) begin
            assert (same_line_match == ref_same_line_match_c)
                else $error("RS E11: same_line_match %b != S4 ref %b",
                            same_line_match, ref_same_line_match_c);

            assert (valid_count == ref_valid_count_c)
                else $error("RS E11: valid_count %0d != popcount %0d",
                            valid_count, ref_valid_count_c);
        end
    end

    // Entry 13 equivalence check: the retired serial priority scan
    // survives as the reference. The one-hot grant must agree with it on
    // validity always, and on the selected entry whenever one exists;
    // the one-hot property is what licenses the OR-encode and the
    // AND-OR muxes.
    logic                   ref_issue_valid_c;
    logic [RS_ID_WIDTH-1:0] ref_issue_rs_id_c;

    always_comb begin
        ref_issue_valid_c = 1'b0;
        ref_issue_rs_id_c = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs[i].valid &&
                !rs[i].in_progress &&
                !ref_issue_valid_c) begin
                ref_issue_valid_c = 1'b1;
                ref_issue_rs_id_c = RS_ID_WIDTH'(i);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst) begin
            assert ($onehot0(issue_grant_c))
                else $error("RS E13: issue_grant_c not one-hot (%b)",
                            issue_grant_c);

            assert (issue_valid == ref_issue_valid_c)
                else $error("RS E13: issue_valid %b != serial ref %b",
                            issue_valid, ref_issue_valid_c);

            if (issue_valid) begin
                assert (issue_rs_id == ref_issue_rs_id_c)
                    else $error("RS E13: issue_rs_id %0d != serial ref %0d",
                                issue_rs_id, ref_issue_rs_id_c);
            end
        end
    end

    // Campaign info counters (sim-only): design-sizing data, one line
    // per DUT at end of sim (%m names the instance). The headline
    // number is the occupancy high-water mark: if it sits well under
    // RS_DEPTH across the full regression, the queue - and with it the
    // CAM width, the vbuf, and the steering fanout - is oversized, and
    // shrinking RS_DEPTH becomes a measured future entry instead of a
    // guess. The patch-cycle counters profile how hot the Entry 11/14
    // patch paths run (the E12 counters taught us these are worth
    // knowing, not assuming); issue-stall counts cycles an eligible
    // miss waited for a free MSHR. 2-state types: default-zero, never
    // cleared (the TB resets between tests; clearing would keep only
    // the last window - the Entry 12 lesson).
    longint unsigned info_alloc_new;
    longint unsigned info_merges;
    longint unsigned info_elder_patch_cycles;
    longint unsigned info_shift_patch_cycles;
    longint unsigned info_issue_stall_cycles;
    int              info_occ_highwater;

    always_ff @(posedge clk) begin
        if (!rst) begin
            if (alloc_fire && !can_merge)
                info_alloc_new <= info_alloc_new + 1;
            if (alloc_fire && can_merge)
                info_merges <= info_merges + 1;
            if (elder_alloc_dup_r[0])
                info_elder_patch_cycles <= info_elder_patch_cycles + 1;
            if (pre_shifted_dup_r[0])
                info_shift_patch_cycles <= info_shift_patch_cycles + 1;
            if (issue_valid && !issue_accept)
                info_issue_stall_cycles <= info_issue_stall_cycles + 1;
            if (int'(valid_count) > info_occ_highwater)
                info_occ_highwater <= int'(valid_count);
        end
    end

    final begin
        $display("RS INFO %m: occ high-water=%0d/%0d, allocs=%0d, merges=%0d, elder-patch cycles=%0d, shift-patch cycles=%0d, issue-stall cycles=%0d",
                 info_occ_highwater, RS_DEPTH, info_alloc_new, info_merges,
                 info_elder_patch_cycles, info_shift_patch_cycles,
                 info_issue_stall_cycles);
    end
`endif

endmodule
