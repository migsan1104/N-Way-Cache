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

    localparam int RS_ID_WIDTH    = (RS_DEPTH <= 1) ? 1 : $clog2(RS_DEPTH),
    localparam int WAITER_COUNT_W = $clog2(MAX_WAITERS + 1),
    localparam int COUNT_W        = $clog2(RS_DEPTH + 1)
)(
    input  logic clk,
    input  logic rst,

    input  logic                       alloc_valid,
    output logic                       alloc_ready,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,
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

    output logic                       issue_victim_dirty,
    output logic [TAG_WIDTH-1:0]       issue_victim_tag,
    output logic [LINE_WIDTH-1:0]      issue_victim_line,
    output logic [LINE_WIDTH/DATA_WIDTH-1:0] issue_victim_word_valid,

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

    (* ram_style = "distributed" *)
    logic [VBUF_W-1:0] vbuf [0:RS_DEPTH-1];

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

    logic [RS_ID_WIDTH-1:0] issue_update_idx;

    always_comb begin
        valid_count = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            valid_count = valid_count + COUNT_W'(rs[i].valid);
        end
    end

    assign almost_full = (valid_count >= COUNT_W'(RS_DEPTH - MSHR_AF));
    assign alloc_ready = !almost_full;

    assign alloc_fire = alloc_valid;
    assign issue_fire = issue_valid && issue_accept;

    // Compare the incoming miss against every live entry. The valid gate
    // matters: retiring shifts entries down without clearing line_addr, so a
    // dead entry still holds a stale address. Matching it would merge a new
    // miss into an entry that will never issue, losing the request.
    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            same_line_match[i] =
                rs[i].valid && (rs[i].line_addr == alloc_line_addr);
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

    always_comb begin
        issue_valid = 1'b0;
        issue_rs_id = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs[i].valid &&
                !rs[i].in_progress &&
                !issue_valid) begin
                issue_valid = 1'b1;
                issue_rs_id = RS_ID_WIDTH'(i);
            end
        end
    end

    assign issue_line_addr = rs[issue_rs_id].line_addr;
    assign issue_set_id    = rs[issue_rs_id].line_addr[SET_INDEX_W-1:0];
    assign issue_tag       = rs[issue_rs_id].line_addr[LINE_ADDR_WIDTH-1:SET_INDEX_W];
    assign issue_way       = rs[issue_rs_id].way;

    assign issue_write        = rs[issue_rs_id].write;
    assign issue_wdata        = rs[issue_rs_id].wdata;
    assign issue_word_id      = rs[issue_rs_id].word_id;

    assign {issue_victim_dirty, issue_victim_tag,
            issue_victim_word_valid, issue_victim_line} =
        vbuf[RS_ID_WIDTH'(vbuf_head_r + issue_rs_id)];

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

        issue_update_idx = issue_rs_id;
        if (dispatch_valid) begin
            issue_update_idx = issue_rs_id - 1'b1;
        end

        if (issue_fire) begin
            rs_next[issue_update_idx].in_progress = 1'b1;
            rs_next[issue_update_idx].mshr_id     = issue_mshr_id;
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

    // One write port, no reset, no other drivers: LUTRAM-inferable.
    always_ff @(posedge clk) begin
        if (alloc_fire && !can_merge) begin
            vbuf[vbuf_tail_r] <= {alloc_victim_dirty, alloc_victim_tag,
                                  alloc_victim_word_valid, alloc_victim_line};
        end
    end

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
`endif

endmodule
