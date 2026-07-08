// ============================================================
// 4-entry MSHR file with Reservation Station + Dispacher
//
// MSHR_Entry no longer tracks CPU IDs.
// Reservation_Station owns CPU waiter IDs.
// Dispacher emits CPU miss response IDs + data.
//
// Refill path is separate:
//   MSHR_Entry -> MSHR_Mux -> cache refill arrays
//
// CPU miss data is delayed outside this file, then passed into
// Dispacher so miss_valid/miss_id/miss_data stay aligned.
// ============================================================

module MSHR_File #(
    parameter int ADDR_WIDTH      = 32,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int MSHR_ID_WIDTH   = 2,
    parameter int MISSQ_DEPTH     = 64,
    parameter int MSHR_AF         = 7,
    parameter int MAX_WAITERS     = 4
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

    input  logic [3:0]                 issue_done,

    input  logic                       mem_resp_valid,
    input  logic [MSHR_ID_WIDTH-1:0]   mem_resp_id,
    input  logic [DATA_WIDTH-1:0]      mem_resp_rdata,

    input  logic [DATA_WIDTH-1:0]      delayed_miss_data,

    output logic                       miss_valid,
    output logic [DATA_WIDTH-1:0]      miss_data,
    output logic [CPU_ID_WIDTH-1:0]    miss_id,

    output logic                       refill_wen,
    output logic [SET_INDEX_W-1:0]     refill_set_id,
    output logic [TAG_WIDTH-1:0]       refill_tag,
    output logic [WAY_INDEX_W-1:0]     refill_way,
    output logic [LINE_WIDTH-1:0]      refill_line,

    output logic [3:0]                 issue_pending,

    output logic [3:0]                 req_valid,
    output logic [3:0]                 req_write,
    output logic [ADDR_WIDTH-1:0]      req_addr  [4],
    output logic [DATA_WIDTH-1:0]      req_wdata [4],
    output logic [MSHR_ID_WIDTH-1:0]   req_id    [4]
);

    localparam int MSHR_COUNT     = 4;
    localparam int RS_ID_WIDTH    = (MISSQ_DEPTH <= 1) ? 1 : $clog2(MISSQ_DEPTH);
    localparam int WAITER_COUNT_W = $clog2(MAX_WAITERS + 1);

    typedef struct packed {
        logic [LINE_ADDR_WIDTH-1:0] line_addr;
        logic [SET_INDEX_W-1:0]     set_id;
        logic [WORD_OFFSET_W-1:0]   word_id;
        logic [TAG_WIDTH-1:0]       tag;
        logic [WAY_INDEX_W-1:0]     way;

        logic                       victim_dirty;
        logic [TAG_WIDTH-1:0]       victim_tag;
        logic [LINE_WIDTH-1:0]      victim_line;
        logic [LINE_WIDTH/DATA_WIDTH-1:0] victim_word_valid;
    } rs_issue_entry_t;

    rs_issue_entry_t rs_issue_entry;

    logic rs_issue_valid;
    logic rs_issue_accept;
    logic [RS_ID_WIDTH-1:0] rs_issue_id;

    logic rs_retire_valid;
    logic [MSHR_ID_WIDTH-1:0] rs_retire_mshr_id;

    logic dispatch_valid;
    logic [WAITER_COUNT_W-1:0] dispatch_cpu_id_count;
    logic [CPU_ID_WIDTH-1:0]   dispatch_cpu_ids  [MAX_WAITERS];
    logic [WORD_OFFSET_W-1:0]  dispatch_word_ids [MAX_WAITERS];

    logic [MSHR_COUNT-1:0] entry_valid;
    logic [MSHR_COUNT-1:0] entry_issue_pending;
    logic [MSHR_COUNT-1:0] entry_refill_wen;

    logic [LINE_ADDR_WIDTH-1:0] entry_line_addr [MSHR_COUNT];
    logic [SET_INDEX_W-1:0]     entry_set_id    [MSHR_COUNT];
    logic [WORD_OFFSET_W-1:0]   entry_word_id   [MSHR_COUNT];
    logic [TAG_WIDTH-1:0]       entry_tag       [MSHR_COUNT];
    logic [WAY_INDEX_W-1:0]     entry_way       [MSHR_COUNT];

    logic [LINE_WIDTH-1:0]      entry_fill_line [MSHR_COUNT];

    logic [MSHR_COUNT-1:0]      mshr_resp_valid;
    logic [DATA_WIDTH-1:0]      mshr_resp_data;
    logic [MSHR_ID_WIDTH-1:0]   entry_alloc_idx;

    logic entry_alloc_ready;
    logic entry_alloc_fire;

    logic retire_sel_valid;
    logic [MSHR_ID_WIDTH-1:0] retire_sel_idx;

    // ============================================================
    // Reservation Station
    // ============================================================

    Reservation_Station #(
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
        .SET_INDEX_W    (SET_INDEX_W),
        .WORD_OFFSET_W  (WORD_OFFSET_W),
        .TAG_WIDTH      (TAG_WIDTH),
        .WAY_INDEX_W    (WAY_INDEX_W),
        .DATA_WIDTH     (DATA_WIDTH),
        .LINE_WIDTH     (LINE_WIDTH),
        .CPU_ID_WIDTH   (CPU_ID_WIDTH),
        .MSHR_ID_WIDTH  (MSHR_ID_WIDTH),
        .RS_DEPTH       (MISSQ_DEPTH),
        .MSHR_AF        (MSHR_AF),
        .MAX_WAITERS    (MAX_WAITERS)
    ) RES_STATION (
        .clk                (clk),
        .rst                (rst),

        .alloc_valid        (alloc_valid),
        .alloc_ready        (alloc_ready),

        .alloc_line_addr    (alloc_line_addr),
        .alloc_word_id      (alloc_word_id),
        .alloc_way          (alloc_way),
        .alloc_write        (alloc_write),
        .alloc_wdata        (alloc_wdata),
        .alloc_cpu_req_id   (alloc_cpu_req_id),

        .alloc_victim_dirty (alloc_victim_dirty),
        .alloc_victim_tag   (alloc_victim_tag),
        .alloc_victim_line  (alloc_victim_line),
        .alloc_victim_word_valid (alloc_victim_word_valid),

        .issue_valid        (rs_issue_valid),
        .issue_accept       (rs_issue_accept),
        .issue_mshr_id      (entry_alloc_idx),

        .issue_rs_id        (rs_issue_id),
        .issue_line_addr    (rs_issue_entry.line_addr),
        .issue_set_id       (rs_issue_entry.set_id),
        .issue_tag          (rs_issue_entry.tag),
        .issue_way          (rs_issue_entry.way),

   
        .issue_word_id      (rs_issue_entry.word_id),

        .issue_victim_dirty (rs_issue_entry.victim_dirty),
        .issue_victim_tag   (rs_issue_entry.victim_tag),
        .issue_victim_line  (rs_issue_entry.victim_line),
        .issue_victim_word_valid (rs_issue_entry.victim_word_valid),

        .retire_valid       (rs_retire_valid),
        .retire_mshr_id     (rs_retire_mshr_id),

        .dispatch_valid        (dispatch_valid),
        .dispatch_cpu_id_count (dispatch_cpu_id_count),
        .dispatch_cpu_ids      (dispatch_cpu_ids),
        .dispatch_word_ids     (dispatch_word_ids)
    );

    // ============================================================
    // Dispacher
    // ============================================================

    Dispacher #(
        .DATA_WIDTH   (DATA_WIDTH),
        .CPU_ID_WIDTH (CPU_ID_WIDTH),
        .WORD_OFFSET_W(WORD_OFFSET_W),
        .MAX_WAITERS  (MAX_WAITERS)
    ) MISS_DISPACHER (
        .clk                  (clk),
        .rst                  (rst),

        .delayed_miss_data    (delayed_miss_data),

        .dispatch_valid       (dispatch_valid),
        .dispatch_critical_word(entry_word_id[retire_sel_idx]),
        .dispatch_cpu_id_count(dispatch_cpu_id_count),
        .dispatch_cpu_ids     (dispatch_cpu_ids),
        .dispatch_word_ids    (dispatch_word_ids),

        .miss_valid           (miss_valid),
        .miss_data            (miss_data),
        .miss_id              (miss_id)
    );

    // ============================================================
    // Free MSHR select
    // ============================================================

    always_comb begin
        entry_alloc_ready = 1'b0;
        entry_alloc_idx   = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (!entry_valid[i] && !entry_alloc_ready) begin
                entry_alloc_ready = 1'b1;
                entry_alloc_idx   = i[MSHR_ID_WIDTH-1:0];
            end
        end
    end

    assign entry_alloc_fire = rs_issue_valid && entry_alloc_ready;
    assign rs_issue_accept  = entry_alloc_fire;


    // ============================================================
    // Completed MSHR select for response dispatch.
    // Match MSHR_Mux priority so refill and CPU response retire
    // consume the same completed entry if completions overlap.
    // ============================================================

    always_comb begin
        retire_sel_valid = 1'b0;
        retire_sel_idx   = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (entry_refill_wen[i] && !retire_sel_valid) begin
                retire_sel_valid = 1'b1;
                retire_sel_idx   = i[MSHR_ID_WIDTH-1:0];
            end
        end
    end

    assign rs_retire_valid   = retire_sel_valid;
    assign rs_retire_mshr_id = retire_sel_idx;

    // ============================================================
    // Memory response demux
    // ============================================================

    MSHR_Response_DeMux #(
        .MSHR_COUNT   (MSHR_COUNT),
        .DATA_WIDTH   (DATA_WIDTH),
        .MSHR_ID_WIDTH(MSHR_ID_WIDTH)
    ) RESP_DEMUX (
        .clk            (clk),
        .rst            (rst),
        .mem_resp_valid (mem_resp_valid),
        .mem_resp_id    (mem_resp_id),
        .mem_resp_rdata (mem_resp_rdata),
        .mshr_resp_valid(mshr_resp_valid),
        .mshr_resp_data (mshr_resp_data)
    );

    // ============================================================
    // Refill mux
    // Refill path is independent from RS/Dispacher response path.
    // ============================================================

    MSHR_Mux #(
        .MSHR_COUNT (MSHR_COUNT),
        .SET_INDEX_W(SET_INDEX_W),
        .TAG_WIDTH  (TAG_WIDTH),
        .WAY_INDEX_W(WAY_INDEX_W),
        .LINE_WIDTH (LINE_WIDTH)
    ) REFILL_MUX (
        .clk                   (clk),
        .rst                   (rst),
        .entry_refill_wen      (entry_refill_wen),
        .entry_set_id          (entry_set_id),
        .entry_tag             (entry_tag),
        .entry_way             (entry_way),
        .entry_fill_line       (entry_fill_line),
        .refill_wen            (refill_wen),
        .refill_set_id         (refill_set_id),
        .refill_tag            (refill_tag),
        .refill_way            (refill_way),
        .refill_line           (refill_line)
    );

    // ============================================================
    // Status outputs
    // ============================================================

    assign issue_pending = entry_issue_pending;

    // ============================================================
    // MSHR entries
    // ============================================================

    genvar i;

    generate
        for (i = 0; i < MSHR_COUNT; i++) begin : GEN_MSHR_ENTRIES

            MSHR_Entry #(
                .ADDR_WIDTH      (ADDR_WIDTH),
                .LINE_ADDR_WIDTH (LINE_ADDR_WIDTH),
                .SET_INDEX_W     (SET_INDEX_W),
                .WORD_OFFSET_W   (WORD_OFFSET_W),
                .TAG_WIDTH       (TAG_WIDTH),
                .WAY_INDEX_W     (WAY_INDEX_W),
                .DATA_WIDTH      (DATA_WIDTH),
                .LINE_WIDTH      (LINE_WIDTH),
                .MSHR_ID_WIDTH   (MSHR_ID_WIDTH),
                .ENTRY_ID        (i)
            ) ENTRY (
                .clk                (clk),
                .rst                (rst),

                .alloc              (entry_alloc_fire && (entry_alloc_idx == i[MSHR_ID_WIDTH-1:0])),

                .alloc_line_addr    (rs_issue_entry.line_addr),
                .alloc_set_id       (rs_issue_entry.set_id),
                .alloc_word_id      (rs_issue_entry.word_id),
                .alloc_tag          (rs_issue_entry.tag),
                .alloc_way          (rs_issue_entry.way),

                .alloc_victim_dirty (rs_issue_entry.victim_dirty),
                .alloc_victim_tag   (rs_issue_entry.victim_tag),
                .alloc_victim_line  (rs_issue_entry.victim_line),
                .alloc_victim_word_valid (rs_issue_entry.victim_word_valid),

                .issue_done         (issue_done[i]),

                .resp_valid         (mshr_resp_valid[i]),
                .resp_data          (mshr_resp_data),

                .valid              (entry_valid[i]),
                .issue_pending      (entry_issue_pending[i]),

                .req_valid          (req_valid[i]),
                .req_write          (req_write[i]),
                .req_addr           (req_addr[i]),
                .req_wdata          (req_wdata[i]),
                .req_mshr_id        (req_id[i]),

                .line_addr          (entry_line_addr[i]),
                .set_id             (entry_set_id[i]),
                .word_id            (entry_word_id[i]),
                .tag                (entry_tag[i]),
                .way                (entry_way[i]),

                .refill_wen         (entry_refill_wen[i]),
                .fill_line          (entry_fill_line[i])
            );

        end
    endgenerate

endmodule
