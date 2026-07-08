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
    logic [RESP_WIDTH-1:0] miss_fifo_rd_data;

    logic choose_miss;
    logic choose_hit;
    

    assign hit_ready  = !hit_fifo_full;

    assign hit_fifo_wr_data  = {1'b1, hit_id, hit_data};
    assign miss_fifo_wr_data = {1'b0, miss_id, miss_data};

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


        .wr_en   (miss_valid),
        .wr_data (miss_fifo_wr_data),

        .empty   (miss_fifo_empty),
        .rd_en   (miss_fifo_rd_en),
        .rd_data (miss_fifo_rd_data)
    );

    assign choose_miss = !miss_fifo_empty;
    assign choose_hit  = miss_fifo_empty && !hit_fifo_empty;

    assign cpu_resp_valid =
        choose_miss || choose_hit;

    assign cpu_resp_hit =
        choose_miss
        ? miss_fifo_rd_data[RESP_WIDTH-1]
        : hit_fifo_rd_data [RESP_WIDTH-1];

    assign cpu_resp_id =
        choose_miss
        ? miss_fifo_rd_data[DATA_WIDTH +: CPU_ID_WIDTH]
        : hit_fifo_rd_data [DATA_WIDTH +: CPU_ID_WIDTH];

    assign cpu_resp_rdata =
        choose_miss
        ? miss_fifo_rd_data[DATA_WIDTH-1:0]
        : hit_fifo_rd_data [DATA_WIDTH-1:0];

    assign miss_fifo_rd_en =
        cpu_resp_valid &&
        cpu_resp_ready &&
        choose_miss;

    assign hit_fifo_rd_en =
        cpu_resp_valid &&
        cpu_resp_ready &&
        choose_hit;
 
endmodule
