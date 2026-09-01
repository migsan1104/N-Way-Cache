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

    localparam int WORDS_PER_LINE = LINE_WIDTH / DATA_WIDTH,
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

    // Entry 18: the victim LINE never leaves the vbuf. At issue the MSHR
    // entry receives only the small metadata (dirty/tag/word_valid) plus
    // the vbuf SLOT the victim lives in; it reads the line back one word
    // per writeback beat through the wb_* port below.
    output logic                       issue_victim_dirty,
    output logic [TAG_WIDTH-1:0]       issue_victim_tag,
    output logic [WORDS_PER_LINE-1:0]  issue_victim_word_valid,
    output logic [RS_ID_WIDTH-1:0]     issue_victim_slot,

    // Entry 18 writeback read port (combinational, shared by all MSHR
    // entries - the request arbiter grants one writeback beat per cycle,
    // so one port suffices). wb_active is consumed only by the sim-only
    // liveness assertion at the bottom. (Entry 27b rev 2's full-line
    // form was STRUCK 2026-08-24: both pre-read revs measured as the
    // design wall - rev1 -2377, rev2 -1614 vs -729 with the plain
    // Entry 23 read. History in notebook Entries 27/27b.)
    input  logic                       wb_active,
    input  logic [RS_ID_WIDTH-1:0]     wb_slot,
    input  logic [WORD_OFFSET_W-1:0]   wb_word,
    output logic [DATA_WIDTH-1:0]      wb_victim_word,

    input  logic                       retire_valid,
    input  logic [MSHR_ID_WIDTH-1:0]   retire_mshr_id,
    // Entry 30(b): NEXT cycle's retire_valid - the D of Entry 30(a)'s
    // retire_valid_r in MSHR_File (a shallow priority resolve over the
    // entries' registered refill pulses). Lets the registered merge
    // decision pre-shift for the retire that will accompany its
    // consumption. 30(b) is only sound on top of 30(a).
    input  logic                       retire_valid_next,

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

        // Entry 19a: the victim's dirty bit lives IN the entry, not in
        // the vbuf meta RAM. The MSHR FSM branches on dirty at the issue
        // edge (S_ISSUE_W vs S_ISSUE_R), and Entry 18's measurement put
        // the meta RAM read on that state path (A4 paths #3-9, -1.53..
        // -1.58: grant -> slot mux -> RAMD32 -> state_reg/D). One bit in
        // the struct rides the same AND-OR issue mux as line_addr/way -
        // a delivery path the census shows is cheap. Same source, same
        // write condition, same lifetime as the meta bit it replaces:
        // identical value every cycle, bit-identical by construction.
        logic                       victim_dirty;

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
    //
    // Entry 18 split the buffer in two: a small META array
    // (dirty/tag/word_valid, read once at issue) and per-word DATA banks
    // (read one word per writeback beat through wb_*). The line data
    // itself never crosses to the MSHR entries any more.
    // (Entry 19a moved the dirty bit into the rs entry itself - the FSM
    // branches on it at the issue edge, so it must not wait on this RAM.)
    localparam int VBUF_META_W = TAG_WIDTH + WORDS_PER_LINE;

    logic [RS_ID_WIDTH-1:0] vbuf_head_r, vbuf_tail_r;

    logic [COUNT_W-1:0] valid_count;
    logic [COUNT_W-1:0] tail_idx_after_retire;
    logic almost_full;

    // Entry 30(b): the merge decision is a REGISTER (full story at the
    // merge decision section below; declared here because the counters
    // above it consume the copies). merge_sel_r is one-hot-or-empty;
    // the can_merge copies are E14-style kept duplicates, one per
    // steering region.
    localparam int E14_DUP = 4;
    logic [RS_DEPTH-1:0] merge_sel_r;
    (* keep = "true" *) logic [E14_DUP-1:0] can_merge_dup_r;

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
    // Entry 29(c): synchronous reset (was async). Reset VALUES and branches
    // are unchanged - this is a cell-mapping edit: an async reset pin is
    // architectural (dfrtp/sdfrtp/dfstp), a sync one Genus folds into the
    // D-side logic and maps to dfxtp.
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_count <= '0;
        end
        else begin
            valid_count <= valid_count
                           + ((alloc_fire && !can_merge_dup_r[1]) ? COUNT_W'(1) : '0)
                           - (dispatch_valid ? COUNT_W'(1) : '0);
        end
    end

    assign almost_full = (valid_count >= COUNT_W'(RS_DEPTH - MSHR_AF));
    assign alloc_ready = !almost_full;

    assign alloc_fire = alloc_valid;
    assign issue_fire = issue_valid && issue_accept;

    // ---- Merge decision, fully registered (Entry 30(b)) -----------------
    //
    // Lineage: Entry 11 registered the wide CAM (the RS_DEPTH x
    // LINE_ADDR_WIDTH compare ran against pre_line_addr - the
    // compare-stage flops, one cycle before alloc_valid - and its
    // answer crossed the edge in pre_match_r). Entry 14 decoded and
    // duplicated the patch flags. What stayed LIVE in the alloc stage
    // was everything after the CAM: the elder override, the waiter-room
    // gate, the retire shift, the can_merge OR-reduce, and the
    // !can_merge append steering into the wide rs/vbuf captures -
    // measured on the -729 baseline (2026-08-24) as the
    // elder_alloc_dup_r / pre_shifted_dup_r -> rs_reg/vbuf classes,
    // ~90 of the top-400 paths, launching off an 894 ps CLK->Q flop.
    //
    // Entry 30(b) finishes that retiming: the DECISION itself is the
    // register. During the compare stage the full merge answer for the
    // incoming request is computed from register-fed terms only and
    // captured as merge_sel_r / can_merge_dup_r; the alloc-stage
    // steering collapses to register-fed AND gates.
    //
    // TWO edges separate computing from the write it steers, and every
    // event on them is register-visible a cycle early:
    //
    //   Edge A (compare -> alloc): a retire shifts entries down
    //   (dispatch_valid - registered by Entry 30(a)); the request AHEAD
    //   of us - the elder, now in ITS alloc stage - appends or merges,
    //   and the elder's own decision is this same register pair one
    //   generation older, so the recursion closes through the flops.
    //   Edge B (alloc -> write): the alloc-cycle write lands post-
    //   retire-shift, so the decision also pre-shifts for the NEXT
    //   retire (retire_valid_next = the D of 30(a)'s retire_valid_r).
    //   This is why 30(b) REQUIRES 30(a): without the registered
    //   retire, edge B's shift is unknowable a cycle early.
    //
    // Patch order (shift, then elder, in post-edge indexing - the
    // Entry 11 discipline):
    //   1. waiter-room counts the elder's merge (+1 on its target);
    //   2. shift for edge A's retire;
    //   3. elder append: its slot (tail_idx_after_retire) takes the
    //      elder's-line-vs-ours compare (a fresh entry always has room);
    //   4. shift for edge B's retire.
    //
    // The valid gate rides inside the candidate term (register-fed):
    // retiring shifts entries down without clearing line_addr, so a
    // dead slot still holds a stale address - matching it would merge a
    // new miss into an entry that will never issue, losing the request.
    //
    // The registers run free - no enable, no reset: the D collapses to
    // 0 while the rs valid bits are in reset, and the pipeline is three
    // deep from the port, so the first real alloc arrives cycles after
    // the vector already holds a real answer.

    // E14's kept-duplicate pattern carries over: can_merge fans into
    // every steering region (rs append, counters, vbuf data, vbuf
    // meta), so it is captured as one KEPT copy per region - all
    // loading the same D on the same edge, behavior identical; `keep`
    // is load-bearing for Vivado, without it the copies merge and the
    // split never happens. Genus ignores `keep` - Entry 33 (2026-08-25)
    // pins can_merge_dup_r from run_genus.tcl's REPLICA_PATTERNS list
    // instead. merge_sel_r bits are per-entry (each drives only its
    // own entry's cone) and need no duplication.
    logic [RS_DEPTH-1:0] merge_cand_c;     // match+valid+room, this-cycle indexing
    logic [RS_DEPTH-1:0] merge_tight_c;    // same, with one-less headroom
    logic [RS_DEPTH-1:0] merge_tight_shifted_c;
    logic [RS_DEPTH-1:0] merge_shifted_c;  // after edge A's retire shift
    logic [RS_DEPTH-1:0] merge_ok_n;       // after elder patch + edge B shift
    logic                elder_append_c;

    always_comb begin
        // The elder's registered decision, one generation older.
        elder_append_c = alloc_fire && !can_merge_dup_r[0];

        for (int i = 0; i < RS_DEPTH; i++) begin
            // match+valid+room, evaluated in THIS cycle's indexing. Two
            // room thresholds: merge_tight_c is the same candidate under
            // one-less headroom, for the entry the elder merges into.
            // Both are per-entry properties, so they SHIFT WITH their
            // entry; the elder patches below are indexed post-shift and
            // must be applied post-shift (merge_sel_r is the elder's
            // decision and already carries its own edge-B shift).
            merge_cand_c[i] =
                rs[i].valid &&
                (rs[i].line_addr == pre_line_addr) &&
                (rs[i].cpu_id_count < WAITER_COUNT_W'(MAX_WAITERS));
            merge_tight_c[i] =
                rs[i].valid &&
                (rs[i].line_addr == pre_line_addr) &&
                ((rs[i].cpu_id_count + WAITER_COUNT_W'(1))
                 < WAITER_COUNT_W'(MAX_WAITERS));
        end

        // Edge A's retire shift, both views. SEPARATE loop on purpose:
        // the shift reads neighbours of the vectors the loop above
        // writes, and always_comb is NOT sensitive to variables it
        // itself writes - folding this into the same loop reads the
        // previous activation's stale values (the bug that failed the
        // first E30(b) regression, 2026-08-24).
        for (int i = 0; i < RS_DEPTH; i++) begin
            merge_shifted_c[i] =
                dispatch_valid
                    ? ((i == RS_DEPTH-1) ? 1'b0 : merge_cand_c[(i+1) % RS_DEPTH])
                    : merge_cand_c[i];
            merge_tight_shifted_c[i] =
                dispatch_valid
                    ? ((i == RS_DEPTH-1) ? 1'b0 : merge_tight_c[(i+1) % RS_DEPTH])
                    : merge_tight_c[i];
        end

        for (int i = 0; i < RS_DEPTH; i++) begin
            // Elder patches, post-edge-A indexing:
            //  - the entry the elder MERGES into has one less headroom;
            //  - the slot the elder APPENDS at takes the elder's-line-
            //    vs-ours compare (a fresh entry always has room).
            merge_ok_n[i] =
                (alloc_fire && can_merge_dup_r[0] && merge_sel_r[i])
                    ? merge_tight_shifted_c[i]
                    : merge_shifted_c[i];
            if (elder_append_c && (COUNT_W'(i) == tail_idx_after_retire)) begin
                merge_ok_n[i] = (alloc_line_addr == pre_line_addr);
            end
        end

        // Patch 4: edge B's retire shift. If the mergeable entry is
        // rs[0] and it retires under our write, the bit shifts out and
        // the request simply allocates fresh - same rule the live form
        // had.
        if (retire_valid_next) begin
            merge_ok_n = {1'b0, merge_ok_n[RS_DEPTH-1:1]};
        end
    end

    always_ff @(posedge clk) begin
        merge_sel_r <= merge_ok_n;
        for (int d = 0; d < E14_DUP; d++) begin
            can_merge_dup_r[d] <= |merge_ok_n;
        end
    end

    // At most one bit of merge_sel_r can be set: a duplicate entry is
    // only created because the newest match was already full, and a
    // full entry stays full until it retires - so among duplicates,
    // only the newest can have room. That one-hot property is what
    // lets the merge path skip the priority encoder; guarded below.
`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!rst) begin
            assert ($onehot0(merge_sel_r))
                else $error("RS E30b: merge_sel_r not one-hot (%b)",
                            merge_sel_r);
        end
    end
`endif

    assign dispatch_valid = retire_valid;

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
        issue_line_addr    = '0;
        issue_way          = '0;
        issue_write        = 1'b0;
        issue_wdata        = '0;
        issue_word_id      = '0;
        issue_victim_dirty = 1'b0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_grant_c[i]) begin
                issue_line_addr    |= rs[i].line_addr;
                issue_way          |= rs[i].way;
                issue_write        |= rs[i].write;
                issue_wdata        |= rs[i].wdata;
                issue_word_id      |= rs[i].word_id;
                issue_victim_dirty |= rs[i].victim_dirty;   // Entry 19a
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

            // Entry 29(h) (2026-08-25): only valid is cleared in the slot
            // the shift vacates. in_progress and cpu_id_count are dead
            // behind valid = 0 (every reader ANDs with valid - see the
            // reset block below) and the append that revives the slot
            // writes both. Two fewer terms in the rs_next cone.
            rs_next[RS_DEPTH-1].valid        = 1'b0;

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
            if (can_merge_dup_r[0]) begin
                // One-hot select, so each entry decides for itself - no index
                // arithmetic and no chained dynamic indexing. rs_next already
                // holds the post-retire state, so its own cpu_id_count is the
                // right slot to fill. (Entry 30(b): both gates are registers.)
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (merge_sel_r[i]) begin
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
                // Entry 29(c): the mshr_id clear is dropped. The field has NO reader in
                // this module (written at issue, never consulted; retire_mshr_id is a
                // dangling input), and in_progress=0 above already marks the entry
                // un-issued. One less term in the rs_next comb cone E30(b) shortened.

                rs_next[tail_idx_after_retire].line_addr    = alloc_line_addr;
                rs_next[tail_idx_after_retire].way          = alloc_way;

                rs_next[tail_idx_after_retire].write        = alloc_write;
                rs_next[tail_idx_after_retire].wdata        = alloc_wdata;
                rs_next[tail_idx_after_retire].word_id      = alloc_word_id;

                rs_next[tail_idx_after_retire].cpu_id_count = WAITER_COUNT_W'(1);
                rs_next[tail_idx_after_retire].cpu_ids[0]   = alloc_cpu_req_id;
                rs_next[tail_idx_after_retire].word_ids[0]  = alloc_word_id;

                // Entry 19a: same write condition as the vbuf (non-merge
                // alloc only - a merge never touches victim state).
                rs_next[tail_idx_after_retire].victim_dirty = alloc_victim_dirty;
            end
        end
    end

    // Entry 29(c): synchronous reset (was async). Reset VALUES and branches
    // are unchanged - this is a cell-mapping edit: an async reset pin is
    // architectural (dfrtp/sdfrtp/dfstp), a sync one Genus folds into the
    // D-side logic and maps to dfxtp.
    // Entry 29(h) (2026-08-25): in_progress and cpu_id_count lose their
    // reset; valid is the one root. Every reader of either field is
    // ANDed with the entry's valid, so a never-written (X / power-up
    // garbage) value is masked - 0 in silicon as in 4-state sim:
    //   issue_cand_c[i]   = valid && !in_progress
    //   merge_cand_c[i]   = valid && (line ==) && (cpu_id_count < MAX)
    //   merge_tight_c[i]  = same shape
    //   dispatch_*        = rs[0] fields, consumed under dispatch_valid,
    //                       which implies rs[0].valid (E11 note)
    //   merge write       = under merge_sel_r[i], a valid-gated decision
    // and the append that makes a slot valid writes both fields on the
    // same edge. The E29(a) map listed "RS valid/count/in_progress" as
    // KEEP; "count" there is valid_count (the credit counter - it keeps
    // its reset), and in_progress was kept without a stated reason.
    // Measured: refill_wen -> rs[*][cpu_id_count] (-332) and
    // -> rs[*][in_progress] (-265) both carried the reset term.
    // Entry 29(o) (2026-08-25): the payload leaves the else-branch. With
    // `rs[i] <= rs_next[i]` under `else`, rst was a hold-enable on ~700
    // payload flops that have no reset value at all, and Genus folded that
    // term INTO the shift/merge select cone (e29cd final db: rst ->
    // rs[line_addr] -106 x96, rs[cpu_ids] -261 x36, rs[word_ids] -262 x18,
    // eight select gates after the reset tree; the worst flop-rooted path
    // to the same endpoints is retire_valid_r at +11). Now the payload
    // loads rs_next on every edge and only valid is reset; last assignment
    // wins, so valid's behaviour is unchanged. During the reset window the
    // payload follows rs_next instead of holding, and every reader is
    // valid-qualified (E29(h) audit); the append that sets valid writes
    // every payload field on the same edge.
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            rs[i] <= rs_next[i];
        end
        if (rst) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                rs[i].valid        <= 1'b0;
            end
        end
    end

    // ---- Entry 18: the victim line stays vbuf-resident ----------------
    // History, because two entries died teaching this: the issue-time
    // read used to hand the FULL 155-bit victim record to the allocating
    // MSHR entry, which registered it into victim_line_r - four 128-bit
    // capture registers and the 155-bit RS->MSHR routes that owned WNS
    // on every measured build. Entry 15/17 tried to fix the ROUTE
    // physically (replicated read copies; then DONT_TOUCH + pinned
    // address trees to stop opt_design re-merging the provably
    // equivalent nets) - the pins won their cone and lost the placement
    // war (A4 -8.8%). Entry 18 deletes the route instead of pinning it:
    //
    //   - At issue the MSHR entry gets only the METADATA (dirty, tag,
    //     word_valid - the writeback address and beat-skip mask) plus
    //     the victim's vbuf SLOT number.
    //   - During S_ISSUE_W it reads the line back ONE WORD PER BEAT
    //     through the wb_* port - which is the granularity the memory
    //     port consumes anyway. The 128-bit capture registers and their
    //     routes cease to exist; each read is genuinely distinct
    //     (slot, word, cycle), so there is nothing for the tools to
    //     "helpfully" merge and nothing to pin.
    //
    // Correctness rests on the Entry 8 slot invariant: a live entry's
    // physical slot (vbuf_head_r + rs index) never moves - retire is
    // always rs[0], which advances head exactly as every survivor's
    // index decrements - and an entry retires only at its own refill,
    // long after its writeback drained. The slot's content is
    // write-once at alloc (merges write nothing), so a beat read at
    // grant time returns exactly what an issue-time capture would have.
    // Same values on the same cycles: bit-identical by construction.
    logic [RS_ID_WIDTH-1:0] vbuf_issue_addr_c;

    always_comb begin
        vbuf_issue_addr_c = '0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (issue_grant_c[i]) begin
                vbuf_issue_addr_c |= slot_addr_c[i];
            end
        end
    end

    assign issue_victim_slot = vbuf_issue_addr_c;

    // Metadata: one small array, read once at issue. Single copy - at
    // 1+TAG_WIDTH+WORDS_PER_LINE bits fanning to four consumers this is
    // not a route worth engineering.
    (* ram_style = "distributed" *)
    logic [VBUF_META_W-1:0] vbuf_meta [0:RS_DEPTH-1];

    always_ff @(posedge clk) begin
        if (alloc_fire && !can_merge_dup_r[3]) begin
            vbuf_meta[vbuf_tail_r] <=
                {alloc_victim_tag, alloc_victim_word_valid};
        end
    end

    assign {issue_victim_tag,
            issue_victim_word_valid} = vbuf_meta[vbuf_issue_addr_c];

    // Line data: one bank per word (the FTDA discipline), each the
    // canonical single-write-port distributed-RAM template. The wb read
    // muxes one word out by wb_word - a DATA_WIDTH-wide 4:1 after four
    // shallow reads, on the memory-port side.
    logic [DATA_WIDTH-1:0] vbuf_wb_word_c [WORDS_PER_LINE];

    generate
        for (genvar gw = 0; gw < WORDS_PER_LINE; gw++) begin : g_vbuf_data
            (* ram_style = "distributed" *)
            logic [DATA_WIDTH-1:0] vbuf_data [0:RS_DEPTH-1];

            always_ff @(posedge clk) begin
                if (alloc_fire && !can_merge_dup_r[2]) begin
                    vbuf_data[vbuf_tail_r] <=
                        alloc_victim_line[gw * DATA_WIDTH +: DATA_WIDTH];
                end
            end

            assign vbuf_wb_word_c[gw] = vbuf_data[wb_slot];
        end
    endgenerate

    assign wb_victim_word = vbuf_wb_word_c[wb_word];

    // Entry 29(c): synchronous reset (was async). Reset VALUES and branches
    // are unchanged - this is a cell-mapping edit: an async reset pin is
    // architectural (dfrtp/sdfrtp/dfstp), a sync one Genus folds into the
    // D-side logic and maps to dfxtp.
    always_ff @(posedge clk) begin
        if (rst) begin
            vbuf_head_r <= '0;
            vbuf_tail_r <= '0;
        end
        else begin
            if (dispatch_valid) begin
                vbuf_head_r <= vbuf_head_r + 1'b1;
            end
            if (alloc_fire && !can_merge_dup_r[1]) begin
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

    // Entry 18 slot liveness: a granted writeback beat must read a slot
    // inside the live window [head, head+valid_count) - the arithmetic
    // proof of the "a live entry's slot never moves" invariant, checked
    // on every real beat ("RS E18").
    always_ff @(posedge clk) begin
        if (!rst && wb_active) begin
            assert (COUNT_W'(RS_ID_WIDTH'(wb_slot - vbuf_head_r)) <
                    valid_count)
                else $error("RS E18: wb read of dead slot %0d (head %0d count %0d)",
                            wb_slot, vbuf_head_r, valid_count);
        end
    end

    // Entry 30(b) equivalence check (supersedes the Entry 11 form; sim-
    // only - every synthesis flow defines SYNTHESIS): the retired LIVE
    // merge decision - match, valid, waiter-room, and the retire shift,
    // all computed at consumption time from CURRENT state - survives as
    // the reference model, compared cycle for cycle against the
    // registered prediction. The prediction discipline (the edge A/B
    // patches) claims exact equality on EVERY cycle, bubbles included:
    // alloc_line_addr is pre_line_addr registered once and both free-
    // run, so even stale bubble values agree - any divergence therefore
    // names the exact cycle a patch went wrong instead of hiding until
    // the next allocation consumes it. Both sides gate on rs[i].valid,
    // which keeps never-written line_addr X-state out. The popcount
    // check on valid_count carries over from Entry 11 unchanged.
    logic [RS_DEPTH-1:0] ref_merge_ok_c;
    logic [RS_DEPTH-1:0] ref_merge_sel_c;
    logic [COUNT_W-1:0]  ref_valid_count_c;

    always_comb begin
        ref_valid_count_c = '0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            ref_merge_ok_c[i] =
                rs[i].valid &&
                (rs[i].line_addr == alloc_line_addr) &&
                (rs[i].cpu_id_count < WAITER_COUNT_W'(MAX_WAITERS));
            ref_valid_count_c = ref_valid_count_c + COUNT_W'(rs[i].valid);
        end
        ref_merge_sel_c = dispatch_valid ? (ref_merge_ok_c >> 1)
                                         : ref_merge_ok_c;
    end

    // Debug snapshots of the D-side terms, captured at the same edge as
    // merge_sel_r so a mismatch prints the exact inputs the prediction
    // consumed (sim-only).
    logic [RS_DEPTH-1:0] dbg_cand_r, dbg_shifted_r;
    logic dbg_dispatch_r, dbg_next_retire_r, dbg_alloc_fire_r,
          dbg_can_merge_r, dbg_elder_append_r;
    logic [COUNT_W-1:0] dbg_tail_r;
    logic [RS_DEPTH-1:0] dbg_elder_sel_r;
    always_ff @(posedge clk) begin
        dbg_cand_r         <= merge_cand_c;
        dbg_shifted_r      <= merge_shifted_c;
        dbg_dispatch_r     <= dispatch_valid;
        dbg_next_retire_r  <= retire_valid_next;
        dbg_alloc_fire_r   <= alloc_fire;
        dbg_can_merge_r    <= can_merge_dup_r[0];
        dbg_elder_append_r <= elder_append_c;
        dbg_tail_r         <= tail_idx_after_retire;
        dbg_elder_sel_r    <= merge_sel_r;
    end

    always_ff @(posedge clk) begin
        if (!rst) begin
            assert (merge_sel_r == ref_merge_sel_c)
                else $error("RS E30b: merge_sel_r %b != live ref %b | D-time: cand=%b shiftedA=%b dispA=%b retB=%b af=%b cm=%b eapp=%b tail=%0d eldsel=%b | now: dispatch=%b valids=%b",
                            merge_sel_r, ref_merge_sel_c,
                            dbg_cand_r, dbg_shifted_r, dbg_dispatch_r,
                            dbg_next_retire_r, dbg_alloc_fire_r,
                            dbg_can_merge_r, dbg_elder_append_r,
                            dbg_tail_r, dbg_elder_sel_r,
                            dispatch_valid,
                            {rs[7].valid, rs[6].valid, rs[5].valid,
                             rs[4].valid, rs[3].valid, rs[2].valid,
                             rs[1].valid, rs[0].valid});

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
            if (alloc_fire && !can_merge_dup_r[0])
                info_alloc_new <= info_alloc_new + 1;
            if (alloc_fire && can_merge_dup_r[0])
                info_merges <= info_merges + 1;
            if (elder_append_c)
                info_elder_patch_cycles <= info_elder_patch_cycles + 1;
            if (dispatch_valid || retire_valid_next)
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
