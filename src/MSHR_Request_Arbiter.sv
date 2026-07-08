// ============================================================
// MSHR request arbiter
// Drains MSHR request streams in the order they become pending.
//
// This makes requests come out as contiguous per-MSHR bundles
// while preventing a younger low-ID MSHR from passing an older
// dirty writeback stream.
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
    input  logic [DATA_WIDTH-1:0]            req_wdata [MSHR_COUNT],
    input  logic [MSHR_ID_WIDTH-1:0]         req_id    [MSHR_COUNT],

    output logic [MSHR_COUNT-1:0]            issued,

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
    logic [DATA_WIDTH-1:0]        selected_wdata;
    logic [MSHR_ID_WIDTH-1:0]     selected_id;
    logic [MSHR_ID_WIDTH-1:0]     selected_idx;

    logic [MSHR_COUNT-1:0]        req_pending_d;
    logic [MSHR_ID_WIDTH-1:0]     order_q [MSHR_COUNT];
    logic [ORDER_PTR_W-1:0]       order_head_r;
    logic [ORDER_PTR_W-1:0]       order_tail_r;
    logic [ORDER_COUNT_W-1:0]     order_count_r;

    logic [MSHR_ID_WIDTH-1:0]     order_q_n [MSHR_COUNT];
    logic [ORDER_PTR_W-1:0]       order_head_n;
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

    assign mem_req_valid = found_req;
    assign mem_req_write = selected_write;
    assign mem_req_addr  = selected_addr;
    assign mem_req_wdata = selected_wdata;
    assign mem_req_id    = selected_id;

    assign issued = found_req ? selected_onehot : '0;

    always_comb begin
        found_req        = 1'b0;
        selected_onehot  = '0;
        selected_write   = 1'b0;
        selected_addr    = '0;
        selected_wdata   = '0;
        selected_id      = '0;
        selected_idx     = '0;

        if (order_count_r != '0) begin
            selected_idx = order_q[order_head_r];

            if (req_pending[selected_idx] && req_valid[selected_idx]) begin
                found_req                    = 1'b1;
                selected_onehot[selected_idx] = 1'b1;
                selected_write               = req_write[selected_idx];
                selected_addr                = req_addr [selected_idx];
                selected_wdata               = req_wdata[selected_idx];
                selected_id                  = req_id   [selected_idx];
            end
        end
    end

    always_comb begin
        order_q_n     = order_q;
        order_head_n  = order_head_r;
        order_tail_n  = order_tail_r;
        order_count_n = order_count_r;

        if ((order_count_n != '0) && !req_pending[order_q_n[order_head_n]]) begin
            order_head_n  = ptr_inc(order_head_n);
            order_count_n = order_count_n - 1'b1;
        end

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (req_pending[i] && !req_pending_d[i] &&
                (order_count_n != ORDER_COUNT_W'(MSHR_COUNT))) begin
                order_q_n[order_tail_n] = i[MSHR_ID_WIDTH-1:0];
                order_tail_n            = ptr_inc(order_tail_n);
                order_count_n           = order_count_n + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            req_pending_d <= '0;
            order_head_r  <= '0;
            order_tail_r  <= '0;
            order_count_r <= '0;

            for (int i = 0; i < MSHR_COUNT; i++) begin
                order_q[i] <= '0;
            end
        end
        else begin
            req_pending_d <= req_pending;
            order_head_r  <= order_head_n;
            order_tail_r  <= order_tail_n;
            order_count_r <= order_count_n;

            for (int i = 0; i < MSHR_COUNT; i++) begin
                order_q[i] <= order_q_n[i];
            end
        end
    end

endmodule
