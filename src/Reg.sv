// ============================================================
// Simple parameterized register
// No reset
// ============================================================

module Reg #(
    parameter int D_WIDTH = 1
)(
    input  logic                 clk,
    input  logic [D_WIDTH-1:0] d,
    output logic [D_WIDTH-1:0] q
);

    always_ff @(posedge clk) begin
        q <= d;
    end

endmodule