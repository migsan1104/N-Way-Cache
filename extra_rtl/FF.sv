// ============================================================
// Simple parameterized flip-flop
// No reset
// No enable
// ============================================================

module FF #(
    parameter int WIDTH = 1
)(
    input  logic             clk,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

    always_ff @(posedge clk) begin
        q <= d;
    end

endmodule