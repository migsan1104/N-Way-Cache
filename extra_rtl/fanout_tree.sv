`timescale 1ns/1ps

module fanout_tree #(
    parameter int DWIDTH   = 1,
    parameter int CLUSTERS = 4,
    localparam int STAGES  = (CLUSTERS <= 1) ? 1 : $clog2(CLUSTERS) + 1
)(
    input  logic clk,
    input  logic rst,

    input  logic [DWIDTH-1:0] din,
    output logic [CLUSTERS-1:0][DWIDTH-1:0] dout
);

    logic [DWIDTH-1:0] stage [0:STAGES-1][0:CLUSTERS-1];

    genvar s, n;
    generate
        if (CLUSTERS == 1) begin : GEN_SINGLE
            Register #(
                .DWIDTH(DWIDTH)
            ) reg_root (
                .clk(clk),
                .rst(rst),
                .d  (din),
                .q  (stage[0][0])
            );

            assign dout[0] = stage[0][0];
        end else begin : GEN_TREE
            Register #(
                .DWIDTH(DWIDTH)
            ) reg_root (
                .clk(clk),
                .rst(rst),
                .d  (din),
                .q  (stage[0][0])
            );

            for (s = 1; s < STAGES; s++) begin : GEN_STAGE
                localparam int NODES_THIS_STAGE = (1 << (s-1));

                for (n = 0; n < NODES_THIS_STAGE; n++) begin : GEN_NODE
                    Register #(
                        .DWIDTH(DWIDTH)
                    ) reg_left (
                        .clk(clk),
                        .rst(rst),
                        .d  (stage[s-1][n]),
                        .q  (stage[s][2*n])
                    );

                    if ((2*n + 1) < CLUSTERS) begin : GEN_RIGHT
                        Register #(
                            .DWIDTH(DWIDTH)
                        ) reg_right (
                            .clk(clk),
                            .rst(rst),
                            .d  (stage[s-1][n]),
                            .q  (stage[s][2*n+1])
                        );
                    end
                end
            end

            for (n = 0; n < CLUSTERS; n++) begin : GEN_OUT
                assign dout[n] = stage[STAGES-1][n];
            end
        end
    endgenerate

endmodule
