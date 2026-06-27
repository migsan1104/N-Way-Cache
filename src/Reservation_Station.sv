// ============================================================
// Reservation_Station
//
// One RS entry per miss.
// Same-line READ misses can merge into cpu_ids / word_ids.
// WRITE misses do not merge.
//
// alloc_ready is only the almost-full indicator:
//   alloc_ready = !almost_full
//
// Refill path is fully separate through MSHR_Entry -> MSHR_Mux.
// Response path only dispatches CPU waiter IDs.
// No fill_line is carried through RS/Dispacher.
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
    parameter int RS_DEPTH        = 32,
    parameter int MSHR_AF         = 7,
    parameter int MAX_WAITERS     = 4,

    localparam int RS_ID_WIDTH    = (RS_DEPTH <= 1) ? 1 : $clog2(RS_DEPTH),
    localparam int WAITER_COUNT_W = $clog2(MAX_WAITERS + 1),
    localparam int COUNT_W        = $clog2(RS_DEPTH + 1),
    localparam logic DEBUG        = 1'b0
)(
    input  logic clk,
    input  logic rst,

    input  logic                       alloc_valid,
    output logic                       alloc_ready,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,
    input  logic [SET_INDEX_W-1:0]     alloc_set_id,
    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [TAG_WIDTH-1:0]       alloc_tag,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,
    input  logic                       alloc_write,
    input  logic [DATA_WIDTH-1:0]      alloc_wdata,
    input  logic [CPU_ID_WIDTH-1:0]    alloc_cpu_req_id,

    input  logic                       alloc_victim_valid,
    input  logic                       alloc_victim_dirty,
    input  logic [TAG_WIDTH-1:0]       alloc_victim_tag,
    input  logic [LINE_WIDTH-1:0]      alloc_victim_line,

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

    output logic                       issue_victim_valid,
    output logic                       issue_victim_dirty,
    output logic [TAG_WIDTH-1:0]       issue_victim_tag,
    output logic [LINE_WIDTH-1:0]      issue_victim_line,

    input  logic                       retire_valid,
    input  logic [LINE_ADDR_WIDTH-1:0] retire_line_addr,

    output logic                       dispatch_valid,
    output logic [WAITER_COUNT_W-1:0]  dispatch_cpu_id_count,
    output logic [CPU_ID_WIDTH-1:0]    dispatch_cpu_ids  [MAX_WAITERS],
    output logic [WORD_OFFSET_W-1:0]   dispatch_word_ids [MAX_WAITERS]
);

    typedef struct {
        logic                       valid;
        logic                       in_progress;
        logic [31:0]                age;
        logic [MSHR_ID_WIDTH-1:0]   mshr_id;

        logic [LINE_ADDR_WIDTH-1:0] line_addr;
        logic [SET_INDEX_W-1:0]     set_id;
        logic [TAG_WIDTH-1:0]       tag;
        logic [WAY_INDEX_W-1:0]     way;

        logic                       write;
        logic [DATA_WIDTH-1:0]      wdata;
        logic [WORD_OFFSET_W-1:0]   word_id;

        logic                       victim_valid;
        logic                       victim_dirty;
        logic [TAG_WIDTH-1:0]       victim_tag;
        logic [LINE_WIDTH-1:0]      victim_line;

        logic [WAITER_COUNT_W-1:0]  cpu_id_count;
        logic [CPU_ID_WIDTH-1:0]    cpu_ids  [MAX_WAITERS];
        logic [WORD_OFFSET_W-1:0]   word_ids [MAX_WAITERS];
    } rs_entry_t;

    rs_entry_t rs [RS_DEPTH];

    logic [31:0] age_counter;

    logic [COUNT_W-1:0] valid_count;
    logic almost_full;

    logic free_found;
    logic [RS_ID_WIDTH-1:0] free_idx;

    logic same_line_found;
    logic [RS_ID_WIDTH-1:0] same_line_idx;
    logic can_merge;

    logic [31:0] best_age;

    logic retire_match_found;
    logic [RS_ID_WIDTH-1:0] retire_match_idx;

    logic alloc_fire;
    logic issue_fire;

    integer dbg_alloc_count;
    integer dbg_merge_count;
    integer dbg_issue_count;
    integer dbg_retire_count;
    integer dbg_write_alloc_count;
    integer dbg_write_retire_count;

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
        free_found = 1'b0;
        free_idx   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (!rs[i].valid && !free_found) begin
                free_found = 1'b1;
                free_idx   = RS_ID_WIDTH'(i);
            end
        end
    end

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

    assign can_merge =
        same_line_found &&
        !alloc_write &&
        !rs[same_line_idx].write &&
        (rs[same_line_idx].cpu_id_count < WAITER_COUNT_W'(MAX_WAITERS));

    always_comb begin
        issue_valid = 1'b0;
        issue_rs_id = '0;
        best_age    = 32'hFFFF_FFFF;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs[i].valid &&
                !rs[i].in_progress &&
                (rs[i].age < best_age)) begin
                issue_valid = 1'b1;
                issue_rs_id = RS_ID_WIDTH'(i);
                best_age    = rs[i].age;
            end
        end
    end

    assign issue_line_addr    = rs[issue_rs_id].line_addr;
    assign issue_set_id       = rs[issue_rs_id].set_id;
    assign issue_tag          = rs[issue_rs_id].tag;
    assign issue_way          = rs[issue_rs_id].way;

    assign issue_write        = rs[issue_rs_id].write;
    assign issue_wdata        = rs[issue_rs_id].wdata;
    assign issue_word_id      = rs[issue_rs_id].word_id;

    assign issue_victim_valid = rs[issue_rs_id].victim_valid;
    assign issue_victim_dirty = rs[issue_rs_id].victim_dirty;
    assign issue_victim_tag   = rs[issue_rs_id].victim_tag;
    assign issue_victim_line  = rs[issue_rs_id].victim_line;

    always_comb begin
        retire_match_found = 1'b0;
        retire_match_idx   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs[i].valid &&
                rs[i].in_progress &&
                (rs[i].line_addr == retire_line_addr) &&
                !retire_match_found) begin
                retire_match_found = 1'b1;
                retire_match_idx   = RS_ID_WIDTH'(i);
            end
        end
    end

    assign dispatch_valid        = retire_valid && retire_match_found;
    assign dispatch_cpu_id_count = rs[retire_match_idx].cpu_id_count;

    always_comb begin
        for (int i = 0; i < MAX_WAITERS; i++) begin
            dispatch_cpu_ids[i]  = rs[retire_match_idx].cpu_ids[i];
            dispatch_word_ids[i] = rs[retire_match_idx].word_ids[i];
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            age_counter <= '0;

            dbg_alloc_count        <= 0;
            dbg_merge_count        <= 0;
            dbg_issue_count        <= 0;
            dbg_retire_count       <= 0;
            dbg_write_alloc_count  <= 0;
            dbg_write_retire_count <= 0;

            for (int i = 0; i < RS_DEPTH; i++) begin
                rs[i].valid        <= 1'b0;
                rs[i].in_progress  <= 1'b0;
                rs[i].age          <= '0;
                rs[i].mshr_id      <= '0;

                rs[i].line_addr    <= '0;
                rs[i].set_id       <= '0;
                rs[i].tag          <= '0;
                rs[i].way          <= '0;

                rs[i].write        <= 1'b0;
                rs[i].wdata        <= '0;
                rs[i].word_id      <= '0;

                rs[i].victim_valid <= 1'b0;
                rs[i].victim_dirty <= 1'b0;
                rs[i].victim_tag   <= '0;
                rs[i].victim_line  <= '0;

                rs[i].cpu_id_count <= '0;

                for (int j = 0; j < MAX_WAITERS; j++) begin
                    rs[i].cpu_ids[j]  <= '0;
                    rs[i].word_ids[j] <= '0;
                end
            end
        end
        else begin
            if (dispatch_valid) begin
                rs[retire_match_idx].valid        <= 1'b0;
                rs[retire_match_idx].in_progress  <= 1'b0;
                rs[retire_match_idx].cpu_id_count <= '0;
            end

            if (issue_fire) begin
                rs[issue_rs_id].in_progress <= 1'b1;
                rs[issue_rs_id].mshr_id     <= issue_mshr_id;
            end

            if (alloc_fire) begin
                if (can_merge) begin
                    rs[same_line_idx].cpu_ids [rs[same_line_idx].cpu_id_count] <= alloc_cpu_req_id;
                    rs[same_line_idx].word_ids[rs[same_line_idx].cpu_id_count] <= alloc_word_id;
                    rs[same_line_idx].cpu_id_count <= rs[same_line_idx].cpu_id_count + 1'b1;
                end
                else if (free_found) begin
                    rs[free_idx].valid        <= 1'b1;
                    rs[free_idx].in_progress  <= 1'b0;
                    rs[free_idx].age          <= age_counter;
                    rs[free_idx].mshr_id      <= '0;

                    rs[free_idx].line_addr    <= alloc_line_addr;
                    rs[free_idx].set_id       <= alloc_set_id;
                    rs[free_idx].tag          <= alloc_tag;
                    rs[free_idx].way          <= alloc_way;

                    rs[free_idx].write        <= alloc_write;
                    rs[free_idx].wdata        <= alloc_wdata;
                    rs[free_idx].word_id      <= alloc_word_id;

                    rs[free_idx].victim_valid <= alloc_victim_valid;
                    rs[free_idx].victim_dirty <= alloc_victim_dirty;
                    rs[free_idx].victim_tag   <= alloc_victim_tag;
                    rs[free_idx].victim_line  <= alloc_victim_line;

                    rs[free_idx].cpu_id_count <= WAITER_COUNT_W'(1);
                    rs[free_idx].cpu_ids[0]   <= alloc_cpu_req_id;
                    rs[free_idx].word_ids[0]  <= alloc_word_id;

                    for (int k = 1; k < MAX_WAITERS; k++) begin
                        rs[free_idx].cpu_ids[k]  <= '0;
                        rs[free_idx].word_ids[k] <= '0;
                    end

                    age_counter <= age_counter + 1'b1;
                end
            end

            if (DEBUG && retire_valid && !retire_match_found) begin
                $display("[%0t] RS RETIRE MISS: retire_line=%h no matching in_progress RS entry",
                         $time,
                         retire_line_addr);
            end

            if (DEBUG && dispatch_valid) begin
                dbg_retire_count <= dbg_retire_count + 1;

                if (rs[retire_match_idx].write) begin
                    dbg_write_retire_count <= dbg_write_retire_count + 1;
                end

                $display("[%0t] RS RETIRE DEBUG: retire#=%0d rs_id=%0d write=%0b cpu_count=%0d cpu_id0=%0d word0=%0d line=%h set=%0d way=%0d tag=%h mshr_id=%0d write_retire#=%0d",
                         $time,
                         dbg_retire_count + 1,
                         retire_match_idx,
                         rs[retire_match_idx].write,
                         rs[retire_match_idx].cpu_id_count,
                         rs[retire_match_idx].cpu_ids[0],
                         rs[retire_match_idx].word_ids[0],
                         rs[retire_match_idx].line_addr,
                         rs[retire_match_idx].set_id,
                         rs[retire_match_idx].way,
                         rs[retire_match_idx].tag,
                         rs[retire_match_idx].mshr_id,
                         dbg_write_retire_count + (rs[retire_match_idx].write ? 1 : 0));
            end
        end
    end

endmodule