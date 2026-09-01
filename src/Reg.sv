// ============================================================
// Simple parameterized register - NO reset.
//
// Reset-free twin of Reg_r (Entry 29(f), 2026-08-25). The two are
// kept as separate modules on purpose: which one a pipeline
// instantiates is an optimization knob - swap Delay_r/Reg_r for
// Delay/Reg to drop a reset, or back to restore it - so the cost of
// a reset can be measured without editing the register itself.
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
