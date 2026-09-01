// ============================================================
// Parameterized delay pipeline using Reg modules - NO reset.
// DELAY = 0 creates a pure combinational passthrough
//
// Reset-free twin of Delay_r (Entry 29(f), 2026-08-25): identical
// structure, built from Reg instead of Reg_r, no rst port. Use it for
// PAYLOAD pipes whose consumers are gated by reset-held control; use
// Delay_r where the pipe's value must be defined out of reset. The
// pair is an optimization knob (see Reg.sv).
// ============================================================

module Delay #(
    parameter int D_WIDTH = 1,
    parameter int DELAY   = 0
)(
    input  logic                   clk,
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
        Reg #(
            .D_WIDTH(D_WIDTH)
        ) REG_STAGE0 (
            .clk(clk),
            .d  (din),
            .q  (pipe[0])
        );

        // Remaining stages
        for (genvar i = 1; i < DELAY; i++) begin : GEN_STAGES

            Reg #(
                .D_WIDTH(D_WIDTH)
            ) REG_STAGE (
                .clk(clk),
                .d  (pipe[i-1]),
                .q  (pipe[i])
            );

        end

        assign dout = pipe[DELAY-1];

    end

endgenerate

endmodule
