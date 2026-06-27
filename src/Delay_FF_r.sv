// ============================================================
// Parameterized delay pipeline using FF_r modules
// DELAY = 0 creates a pure combinational passthrough
// ============================================================

module Delay_FF_r #(
    parameter int WIDTH = 1,
    parameter int DELAY = 0
)(
    input  logic             clk,
    input  logic             rst,
    input  logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout
);

generate

    // Pure combinational passthrough
    if (DELAY == 0) begin : GEN_COMB

        assign dout = din;

    end

    // Flip-flop pipeline
    else begin : GEN_PIPE

        logic [WIDTH-1:0] pipe [DELAY-1:0];

        // First stage
        FF_r #(
            .WIDTH(WIDTH)
        ) FF_STAGE0 (
            .clk(clk),
            .rst(rst),
            .d  (din),
            .q  (pipe[0])
        );

        // Remaining stages
        for (genvar i = 1; i < DELAY; i++) begin : GEN_STAGES

            FF_r #(
                .WIDTH(WIDTH)
            ) FF_STAGE (
                .clk(clk),
                .rst(rst),
                .d  (pipe[i-1]),
                .q  (pipe[i])
            );

        end

        assign dout = pipe[DELAY-1];

    end

endgenerate

endmodule