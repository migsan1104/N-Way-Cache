// ============================================================
// Parameterized delay pipeline using Reg_r modules
// DELAY = 0 creates a pure combinational passthrough
// ============================================================

module Delay_r #(
    parameter int D_WIDTH = 1,
    parameter int DELAY   = 0
)(
    input  logic                   clk,
    input  logic                   rst,
    input  logic [D_WIDTH-1:0] din,
    output logic [D_WIDTH-1:0] dout
);

generate

    // Pure combinational passthrough
    if (DELAY == 0) begin : GEN_COMB

        assign dout = din;

    end

    // Register pipeline
    else begin : GEN_PIPE

        logic [D_WIDTH-1:0] pipe [DELAY-1:0];

        // First stage
        Reg_r #(
            .D_WIDTH(D_WIDTH)
        ) REG_STAGE0 (
            .clk(clk),
            .rst(rst),
            .d  (din),
            .q  (pipe[0])
        );

        // Remaining stages
        for (genvar i = 1; i < DELAY; i++) begin : GEN_STAGES

            Reg_r #(
                .D_WIDTH(D_WIDTH)
            ) REG_STAGE (
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