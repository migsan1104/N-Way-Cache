// ============================================================
// FWFT FIFO with almost_full flag
// rd_data is valid whenever empty == 0
// rd_en pops the currently visible front entry
// almost_full asserts when occupancy >= DEPTH - ALMOST_FULL_GAP
// ============================================================

module FIFO_Almost #(
    parameter int WIDTH           = 16,
    parameter int DEPTH           = 32,
    parameter int ALMOST_FULL_GAP = 5
) (
    input  logic             clk,
    input  logic             rst,

    output logic             full,
    output logic             almost_full,

    input  logic             wr_en,
    input  logic [WIDTH-1:0] wr_data,

    output logic             empty,
    input  logic             rd_en,
    output logic [WIDTH-1:0] rd_data
);

    localparam int ADDR_WIDTH = $clog2(DEPTH) + 1;

    logic [WIDTH-1:0] ram [DEPTH];

    logic [ADDR_WIDTH-1:0] wr_addr_r;
    logic [ADDR_WIDTH-1:0] rd_addr_r;

    logic [ADDR_WIDTH-1:0] used_count;

    logic valid_wr;
    logic valid_rd;

    assign used_count = wr_addr_r - rd_addr_r;

    assign full  = (rd_addr_r[ADDR_WIDTH-2:0] == wr_addr_r[ADDR_WIDTH-2:0]) &&
                   (rd_addr_r[ADDR_WIDTH-1]   != wr_addr_r[ADDR_WIDTH-1]);

    assign empty = rd_addr_r == wr_addr_r;

    assign almost_full = used_count >= (DEPTH - ALMOST_FULL_GAP);

    assign valid_wr = wr_en && !full;
    assign valid_rd = rd_en && !empty;

    // FWFT read: front entry is always visible when FIFO is not empty
    assign rd_data = ram[rd_addr_r[ADDR_WIDTH-2:0]];

    always_ff @(posedge clk) begin
        if (valid_wr) begin
            ram[wr_addr_r[ADDR_WIDTH-2:0]] <= wr_data;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_addr_r <= '0;
            rd_addr_r <= '0;
        end
        else begin
            if (valid_wr) begin
                wr_addr_r <= wr_addr_r + 1'b1;
            end

            if (valid_rd) begin
                rd_addr_r <= rd_addr_r + 1'b1;
            end
        end
    end

endmodule