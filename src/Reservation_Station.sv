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
// Same-line READ misses can merge into cpu_ids / word_ids.
// WRITE misses do not merge.
// ============================================================

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

        logic                       victim_dirty;
        logic [TAG_WIDTH-1:0]       victim_tag;
        logic [LINE_WIDTH-1:0]      victim_line;
        logic [LINE_WIDTH/DATA_WIDTH-1:0] victim_word_valid;

        logic [WAITER_COUNT_W-1:0]  cpu_id_count;
        logic [CPU_ID_WIDTH-1:0]    cpu_ids  [MAX_WAITERS];
        logic [WORD_OFFSET_W-1:0]   word_ids [MAX_WAITERS];
    } rs_entry_t;

    rs_entry_t rs [RS_DEPTH];
    rs_entry_t rs_next [RS_DEPTH];

    logic [COUNT_W-1:0] valid_count;
    logic [COUNT_W-1:0] tail_idx_after_retire;
    logic almost_full;

    logic same_line_found;
    logic [RS_ID_WIDTH-1:0] same_line_idx;
    logic can_merge;

    logic retire_match_found;
    logic [RS_ID_WIDTH-1:0] retire_match_idx;

    logic alloc_fire;
    logic issue_fire;

    logic [RS_ID_WIDTH-1:0] issue_update_idx;
    logic [RS_ID_WIDTH-1:0] merge_update_idx;

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

    always_comb begin
        same_line_found = 1'b0;
        same_line_idx   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs[i].valid &&
                (rs[i].line_addr == alloc_line_addr) &&
                !same_line_found) begin
                same_line_found = 1'b1;
                same_line_idx   = RS_ID_WIDTH'(i);
            end
        end
    end

    always_comb begin
        retire_match_found = 1'b0;
        retire_match_idx   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs[i].valid &&
                (rs[i].mshr_id == retire_mshr_id) &&
                !retire_match_found) begin
                retire_match_found = 1'b1;
                retire_match_idx   = RS_ID_WIDTH'(i);
            end
        end
    end

    assign dispatch_valid = retire_valid;

    assign can_merge =
        same_line_found &&
        !(dispatch_valid && retire_match_found && (same_line_idx == retire_match_idx)) &&
        (rs[same_line_idx].cpu_id_count < WAITER_COUNT_W'(MAX_WAITERS));

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

    assign issue_victim_dirty = rs[issue_rs_id].victim_dirty;
    assign issue_victim_tag   = rs[issue_rs_id].victim_tag;
    assign issue_victim_line  = rs[issue_rs_id].victim_line;
    assign issue_victim_word_valid = rs[issue_rs_id].victim_word_valid;

    assign dispatch_cpu_id_count = rs[retire_match_idx].cpu_id_count;

    always_comb begin
        for (int i = 0; i < MAX_WAITERS; i++) begin
            dispatch_cpu_ids[i]  = rs[retire_match_idx].cpu_ids[i];
            dispatch_word_ids[i] = rs[retire_match_idx].word_ids[i];
        end
    end

    always_comb begin
        rs_next = rs;

        tail_idx_after_retire = valid_count;

        if (dispatch_valid) begin
            for (int i = 0; i < RS_DEPTH-1; i++) begin
                if (i >= retire_match_idx) begin
                    rs_next[i] = rs_next[i+1];
                end
            end

            rs_next[RS_DEPTH-1].valid        = 1'b0;
            rs_next[RS_DEPTH-1].in_progress  = 1'b0;
            rs_next[RS_DEPTH-1].cpu_id_count = '0;

            tail_idx_after_retire = valid_count - 1'b1;
        end

        issue_update_idx = issue_rs_id;
        if (dispatch_valid && (retire_match_idx < issue_rs_id)) begin
            issue_update_idx = issue_rs_id - 1'b1;
        end

        if (issue_fire) begin
            rs_next[issue_update_idx].in_progress = 1'b1;
            rs_next[issue_update_idx].mshr_id     = issue_mshr_id;
        end

        merge_update_idx = same_line_idx;
        if (dispatch_valid && (retire_match_idx < same_line_idx)) begin
            merge_update_idx = same_line_idx - 1'b1;
        end

        if (alloc_fire) begin
            if (can_merge) begin
                rs_next[merge_update_idx].cpu_ids [rs_next[merge_update_idx].cpu_id_count] = alloc_cpu_req_id;
                rs_next[merge_update_idx].word_ids[rs_next[merge_update_idx].cpu_id_count] = alloc_word_id;
                rs_next[merge_update_idx].cpu_id_count =
                    rs_next[merge_update_idx].cpu_id_count + 1'b1;
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

                rs_next[tail_idx_after_retire].victim_dirty = alloc_victim_dirty;
                rs_next[tail_idx_after_retire].victim_tag   = alloc_victim_tag;
                rs_next[tail_idx_after_retire].victim_line  = alloc_victim_line;
                rs_next[tail_idx_after_retire].victim_word_valid =
                    alloc_victim_word_valid;

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

endmodule
