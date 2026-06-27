// ============================================================
// FIFO_FWFT.sv
// First-Word Fall-Through FIFO
//
// empty = 0 means rd_data is valid immediately.
// rd_en pops the current front entry.
// No rd_valid needed.
// ============================================================

module FIFO_FWFT #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 32
)(
    input  logic             clk,
    input  logic             rst,

    output logic             full,
    input  logic             wr_en,
    input  logic [WIDTH-1:0] wr_data,

    output logic             empty,
    input  logic             rd_en,
    output logic [WIDTH-1:0] rd_data
);

    localparam int PTR_W = $clog2(DEPTH) + 1;
    localparam int IDX_W = $clog2(DEPTH);

    logic [WIDTH-1:0] ram [0:DEPTH-1];

    logic [PTR_W-1:0] wr_ptr_r;
    logic [PTR_W-1:0] rd_ptr_r;

    logic do_write;
    logic do_read;

    assign empty = (wr_ptr_r == rd_ptr_r);

    assign full =
        (wr_ptr_r[IDX_W-1:0] == rd_ptr_r[IDX_W-1:0]) &&
        (wr_ptr_r[PTR_W-1]   != rd_ptr_r[PTR_W-1]);

    assign do_write = wr_en && !full;
    assign do_read  = rd_en && !empty;

    assign rd_data = ram[rd_ptr_r[IDX_W-1:0]];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr_r <= '0;
            rd_ptr_r <= '0;
        end
        else begin
            if (do_write) begin
                ram[wr_ptr_r[IDX_W-1:0]] <= wr_data;
            end

            if (do_write) begin
                wr_ptr_r <= wr_ptr_r + 1'b1;
            end

            if (do_read) begin
                rd_ptr_r <= rd_ptr_r + 1'b1;
            end
        end
    end

endmodule