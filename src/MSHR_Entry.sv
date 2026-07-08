// ============================================================
// Single MSHR entry - reduced version
//
// Keeps victim_word_valid so dirty victim writeback only writes
// valid victim words.
//
// Removed:
//   - alloc_write / alloc_wdata storage
//   - write_r / wdata_r
//   - refill_dirty / refill_eviction refill metadata
//   - alloc_mshr_id / mshr_id register/output
//   - S_REFILL state
//
// Uses fixed ENTRY_ID parameter for req_mshr_id.
// ============================================================

module MSHR_Entry #(
    parameter int ADDR_WIDTH      = 32,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int MSHR_ID_WIDTH   = 2,
    parameter int ENTRY_ID        = 0
)(
    input  logic clk,
    input  logic rst,

    input  logic alloc,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,
    input  logic [SET_INDEX_W-1:0]     alloc_set_id,
    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [TAG_WIDTH-1:0]       alloc_tag,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,

    input  logic                       alloc_victim_dirty,
    input  logic [TAG_WIDTH-1:0]       alloc_victim_tag,
    input  logic [LINE_WIDTH-1:0]      alloc_victim_line,
    input  logic [LINE_WIDTH/DATA_WIDTH-1:0] alloc_victim_word_valid,

    input  logic                       issue_done,

    input  logic                       resp_valid,
    input  logic [DATA_WIDTH-1:0]      resp_data,

    output logic                       valid,
    output logic                       issue_pending,

    output logic                       req_valid,
    output logic                       req_write,
    output logic [ADDR_WIDTH-1:0]      req_addr,
    output logic [DATA_WIDTH-1:0]      req_wdata,
    output logic [MSHR_ID_WIDTH-1:0]   req_mshr_id,

    output logic [LINE_ADDR_WIDTH-1:0] line_addr,
    output logic [SET_INDEX_W-1:0]     set_id,
    output logic [WORD_OFFSET_W-1:0]   word_id,
    output logic [TAG_WIDTH-1:0]       tag,
    output logic [WAY_INDEX_W-1:0]     way,

    output logic                       refill_wen,
    output logic [LINE_WIDTH-1:0]      fill_line
);

    localparam int WORDS_PER_LINE = LINE_WIDTH / DATA_WIDTH;
    localparam int BEAT_COUNT_W   = (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE);

    typedef enum logic [2:0] {
        S_IDLE,
        S_ISSUE_W,
        S_ISSUE_R,
        S_WAIT_R
    } state_t;

    state_t state, state_n;

    logic [BEAT_COUNT_W-1:0] wb_count, wb_count_n;
    logic [BEAT_COUNT_W-1:0] issue_count, issue_count_n;
    logic [BEAT_COUNT_W-1:0] recv_count, recv_count_n;

    logic [WORD_OFFSET_W-1:0] miss_word_id_r, miss_word_id_n;
    logic [WORD_OFFSET_W-1:0] wb_word_id;
    logic [WORD_OFFSET_W-1:0] read_issue_word_id;
    logic [WORD_OFFSET_W-1:0] read_recv_word_id;

    logic [TAG_WIDTH-1:0] victim_tag_r, victim_tag_n;
    logic [LINE_WIDTH-1:0] victim_line_r, victim_line_n;
    logic [WORDS_PER_LINE-1:0] victim_word_valid_r, victim_word_valid_n;
    logic [LINE_ADDR_WIDTH-1:0] victim_line_addr;

    logic [LINE_ADDR_WIDTH-1:0] line_addr_n;
    logic [SET_INDEX_W-1:0]     set_id_n;
    logic [TAG_WIDTH-1:0]       tag_n;
    logic [WAY_INDEX_W-1:0]     way_n;

    logic [LINE_WIDTH-1:0] fill_line_r, fill_line_n;

    logic refill_wen_r, refill_wen_n;

    assign wb_word_id = wb_count[WORD_OFFSET_W-1:0];

    assign read_issue_word_id =
        miss_word_id_r + issue_count[WORD_OFFSET_W-1:0];

    assign read_recv_word_id =
        miss_word_id_r + recv_count[WORD_OFFSET_W-1:0];

    assign victim_line_addr = {victim_tag_r, set_id};

    assign valid = (state != S_IDLE) || refill_wen;

    assign issue_pending =
        (state == S_ISSUE_W) ||
        (state == S_ISSUE_R);

    assign req_valid =
        ((state == S_ISSUE_W) && victim_word_valid_r[wb_word_id]) ||
        (state == S_ISSUE_R);

    assign req_write   = (state == S_ISSUE_W);
    assign req_mshr_id = ENTRY_ID[MSHR_ID_WIDTH-1:0];

    assign req_addr =
        (state == S_ISSUE_W)
        ? {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
           victim_line_addr,
           wb_word_id}
        : {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
           line_addr,
           read_issue_word_id};

    assign req_wdata =
        victim_line_r[wb_word_id * DATA_WIDTH +: DATA_WIDTH];

    assign word_id         = miss_word_id_r;
    assign fill_line       = fill_line_r;
    assign refill_wen      = refill_wen_r;

    always_comb begin
        state_n        = state;

        wb_count_n     = wb_count;
        issue_count_n  = issue_count;
        recv_count_n   = recv_count;

        line_addr_n    = line_addr;
        set_id_n       = set_id;
        miss_word_id_n = miss_word_id_r;
        tag_n          = tag;
        way_n          = way;

        victim_tag_n   = victim_tag_r;
        victim_line_n  = victim_line_r;
        victim_word_valid_n = victim_word_valid_r;

        fill_line_n    = fill_line_r;

        refill_wen_n      = 1'b0;

        case (state)

            S_IDLE: begin
                if (alloc) begin
                    line_addr_n    = alloc_line_addr;
                    set_id_n       = alloc_set_id;
                    miss_word_id_n = alloc_word_id;
                    tag_n          = alloc_tag;
                    way_n          = alloc_way;

                    victim_tag_n   = alloc_victim_tag;
                    victim_line_n  = alloc_victim_line;
                    victim_word_valid_n = alloc_victim_word_valid;

                    wb_count_n     = '0;
                    issue_count_n  = '0;
                    recv_count_n   = '0;
                    fill_line_n    = '0;

                    if (alloc_victim_dirty)
                        state_n = S_ISSUE_W;
                    else
                        state_n = S_ISSUE_R;
                end
            end

            S_ISSUE_W: begin
                if (!victim_word_valid_r[wb_word_id]) begin
                    if (wb_count == WORDS_PER_LINE-1) begin
                        wb_count_n = '0;
                        state_n    = S_ISSUE_R;
                    end
                    else begin
                        wb_count_n = wb_count + 1'b1;
                    end
                end
                else if (issue_done) begin
                    if (wb_count == WORDS_PER_LINE-1) begin
                        wb_count_n = '0;
                        state_n    = S_ISSUE_R;
                    end
                    else begin
                        wb_count_n = wb_count + 1'b1;
                    end
                end
            end

            S_ISSUE_R: begin
                if (issue_done) begin
                    if (issue_count == WORDS_PER_LINE-1) begin
                        issue_count_n = '0;
                        state_n       = S_WAIT_R;
                    end
                    else begin
                        issue_count_n = issue_count + 1'b1;
                    end
                end
            end

            S_WAIT_R: begin
                // Wait for remaining memory responses.
            end

            default: begin
                state_n = S_IDLE;
            end

        endcase

        if (resp_valid) begin
            fill_line_n[read_recv_word_id * DATA_WIDTH +: DATA_WIDTH] = resp_data;

            if (recv_count == WORDS_PER_LINE-1) begin
                recv_count_n      = '0;
                refill_wen_n      = 1'b1;
                state_n           = S_IDLE;
            end
            else begin
                recv_count_n = recv_count + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= S_IDLE;
            refill_wen_r      <= 1'b0;
        end
        else begin
            state             <= state_n;
            refill_wen_r      <= refill_wen_n;
        end
    end

    always_ff @(posedge clk) begin
        wb_count       <= wb_count_n;
        issue_count    <= issue_count_n;
        recv_count     <= recv_count_n;

        line_addr      <= line_addr_n;
        set_id         <= set_id_n;
        miss_word_id_r <= miss_word_id_n;
        tag            <= tag_n;
        way            <= way_n;

        victim_tag_r   <= victim_tag_n;
        victim_line_r  <= victim_line_n;
        victim_word_valid_r <= victim_word_valid_n;

        fill_line_r    <= fill_line_n;
    end

endmodule
