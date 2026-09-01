// ============================================================
// FIFO_FWFT.sv
// First-Word Fall-Through FIFO
//
// empty = 0 means rd_data is valid immediately.
// rd_en pops the current front entry.
// No rd_valid needed.
// ============================================================

module FIFO_NF #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 32
)(
    input  logic             clk,
    input  logic             rst,

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

    assign empty = (wr_ptr_r == rd_ptr_r);

    assign rd_data = ram[rd_ptr_r[IDX_W-1:0]];

    // Entry 29(c): synchronous reset (was async). Reset VALUES and branches
    // are unchanged - this is a cell-mapping edit: an async reset pin is
    // architectural (dfrtp/sdfrtp/dfstp), a sync one Genus folds into the
    // D-side logic and maps to dfxtp.
    // Entry 29(o) (2026-08-25): the storage write leaves the else-branch.
    // ram[] has no reset value; under `else` rst was a hold-enable on
    // every storage flop and Genus put it on the scan-mux enable (e29cd:
    // rst -> MISS_FIFO ram/SCE -82 x18). A write during the reset window
    // lands in a slot both pointers are reset away from.
    always_ff @(posedge clk) begin
        if (wr_en) begin
            ram[wr_ptr_r[IDX_W-1:0]] <= wr_data;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr_r <= '0;
            rd_ptr_r <= '0;
        end
        else begin
            if (wr_en) begin
                wr_ptr_r <= wr_ptr_r + 1'b1;
            end

            if (rd_en) begin
                rd_ptr_r <= rd_ptr_r + 1'b1;
            end
        end
    end

endmodule