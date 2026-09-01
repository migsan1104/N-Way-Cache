// ============================================================
// Simple parameterized flip-flop
// Active-high synchronous reset
// No enable
// ============================================================

module FF_r #(
    parameter int WIDTH = 1
)(
    input  logic             clk,
    input  logic             rst,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

    always_ff @(posedge clk) begin
        if (rst)
            q <= '0;
        else
            q <= d;
    end

endmodule