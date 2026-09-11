// ============================================================
// Response_Unit.sv
// Two response channels:
//   1. Hit response FIFO
//   2. Miss response FIFO
//
// Uses FIFO_FWFT.
// Miss FIFO has priority over hit FIFO.
// Supports back-to-back responses with no bubbles.
// ============================================================

module Response_Unit #(
    parameter int DATA_WIDTH   = 32,
    parameter int CPU_ID_WIDTH = 3,
    parameter int FIFO_DEPTH   = 8,
    parameter int FIFO_DEPTH_MISS = 8
)(
    input  logic clk,
    input  logic rst,

    // Hit response input
    input  logic                    hit_valid,
    output logic                    hit_ready,
    input  logic [DATA_WIDTH-1:0]   hit_data,
    input  logic [CPU_ID_WIDTH-1:0] hit_id,

    // Miss response input
    input  logic                    miss_valid,

    input  logic [DATA_WIDTH-1:0]   miss_data,
    input  logic [CPU_ID_WIDTH-1:0] miss_id,

    // CPU response output
    output logic                    cpu_resp_valid,
    input  logic                    cpu_resp_ready,
    output logic                    cpu_resp_hit,
    output logic [DATA_WIDTH-1:0]   cpu_resp_rdata,
    output logic [CPU_ID_WIDTH-1:0] cpu_resp_id
);

    localparam int RESP_WIDTH = 1 + CPU_ID_WIDTH + DATA_WIDTH;

    logic hit_fifo_full;
    logic hit_fifo_empty;
    logic hit_fifo_rd_en;
    logic [RESP_WIDTH-1:0] hit_fifo_wr_data;
    logic [RESP_WIDTH-1:0] hit_fifo_rd_data;


    logic miss_fifo_empty;
    logic miss_fifo_rd_en;
    logic [RESP_WIDTH-1:0] miss_fifo_wr_data;
    logic miss_valid_r;
    logic [RESP_WIDTH-1:0] miss_fifo_wr_data_r;
    logic [RESP_WIDTH-1:0] miss_fifo_rd_data;

    logic choose_miss;
    logic choose_hit;
    

    assign hit_ready  = !hit_fifo_full;

    assign hit_fifo_wr_data  = {1'b1, hit_id, hit_data};
    assign miss_fifo_wr_data = {1'b0, miss_id, miss_data};

    // Entry 29(e) (2026-08-25): miss_valid_r loses its reset. miss_valid
    // is Dispacher's live_r[snd_ctx_r] && found_c, and live_r keeps its
    // reset (0 from the first reset edge), so this is a defined 0 from
    // the second. Its only consumer is MISS_FIFO's wr_en, whose pointers
    // are reset-held during the flush cycles.
    always_ff @(posedge clk) begin
        miss_valid_r        <= miss_valid;
        miss_fifo_wr_data_r <= miss_fifo_wr_data;
    end

    FIFO_FWFT #(
        .WIDTH(RESP_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) HIT_FIFO (
        .clk     (clk),
        .rst     (rst),

        .full    (hit_fifo_full),
        .wr_en   (hit_valid),
        .wr_data (hit_fifo_wr_data),

        .empty   (hit_fifo_empty),
        .rd_en   (hit_fifo_rd_en),
        .rd_data (hit_fifo_rd_data)
    );

    FIFO_NF #(
        .WIDTH(RESP_WIDTH),
        .DEPTH(FIFO_DEPTH_MISS)
    ) MISS_FIFO (
        .clk     (clk),
        .rst     (rst),


        .wr_en   (miss_valid_r),
        .wr_data (miss_fifo_wr_data_r),

        .empty   (miss_fifo_empty),
        .rd_en   (miss_fifo_rd_en),
        .rd_data (miss_fifo_rd_data)
    );

    assign choose_miss = !miss_fifo_empty;
    assign choose_hit  = miss_fifo_empty && !hit_fifo_empty;

    // ------------------------------------------------------------
    // iter21 experiment (2026-09-07): the CPU response port goes through
    // a Skid_Buffer. Before, cpu_resp_{valid,hit,id,rdata} were the FIFO
    // read pointers -> 8:1 FWFT RAM mux -> hit/miss select straight to the
    // pins (4.67 ns at ss_100C_1v60, Tempus SI, iter19b) and cpu_resp_ready
    // gated both FIFO pops in the same cycle (4.56 ns in, incl. hold
    // padding). Now every output launches from the skid's output register
    // and cpu_resp_ready only reaches the skid's own valid flops; the pop
    // decision sees src_ready, a flop output.
    // Cost: +1 cycle on every response. The hit FIFO's credit bound is
    // unchanged (its capacity is unchanged; the skid only adds drain).
    // ------------------------------------------------------------
    logic                  src_valid;
    logic                  src_ready;
    logic                  src_fire;
    logic [RESP_WIDTH-1:0] src_data;
    logic [RESP_WIDTH-1:0] out_data;

    assign src_valid = choose_miss || choose_hit;
    assign src_data  = choose_miss ? miss_fifo_rd_data : hit_fifo_rd_data;
    assign src_fire  = src_valid && src_ready;

    Skid_Buffer #(
        .WIDTH(RESP_WIDTH)
    ) RESP_SKID (
        .clk       (clk),
        .rst       (rst),

        .in_valid  (src_valid),
        .in_ready  (src_ready),
        .in_data   (src_data),

        .out_valid (cpu_resp_valid),
        .out_ready (cpu_resp_ready),
        .out_data  (out_data)
    );

    assign cpu_resp_hit   = out_data[RESP_WIDTH-1];
    assign cpu_resp_id    = out_data[DATA_WIDTH +: CPU_ID_WIDTH];
    assign cpu_resp_rdata = out_data[DATA_WIDTH-1:0];

    assign miss_fifo_rd_en = src_fire && choose_miss;
    assign hit_fifo_rd_en  = src_fire && choose_hit;

endmodule
