// ============================================================
// Tree-based pseudo-LRU replacement policy
// ASSOC = 1 returns way 0
// ASSOC > 1 uses ASSOC-1 PLRU bits per set
//
// Fully sequential lookup:
//   replacement_way is registered.
//   Output corresponds to previous cycle's lookup_set.
//
// This module is PLRU only.
// It does NOT check valid bits.
// Invalid-way priority is handled outside this module.
// ============================================================

module Replacement #(
    parameter int ASSOC       = 4,
    parameter int NUM_SETS    = 64,

    parameter int WAY_INDEX_W = (ASSOC <= 1) ? 1 : $clog2(ASSOC),
    parameter int SET_INDEX_W = (NUM_SETS <= 1) ? 1 : $clog2(NUM_SETS)
)(
    input  logic clk,
    input  logic rst,

    // PLRU victim lookup
    input  logic [SET_INDEX_W-1:0] lookup_set,
    output logic [WAY_INDEX_W-1:0] replacement_way,

    // PLRU state update
    input  logic                   update_valid,
    input  logic [SET_INDEX_W-1:0] update_set,
    input  logic [WAY_INDEX_W-1:0] update_way
);

    generate
        if (ASSOC == 1) begin : GEN_DIRECT_MAPPED

            always_ff @(posedge clk) begin
                if (rst) begin
                    replacement_way <= '0;
                end else begin
                    replacement_way <= '0;
                end
            end

        end else begin : GEN_TREE_PLRU

            localparam int PLRU_BITS = ASSOC - 1;
            localparam int LEVELS    = $clog2(ASSOC);

            logic [PLRU_BITS-1:0]    plru_bits [NUM_SETS-1:0];
            logic [PLRU_BITS-1:0]    curr_bits;
            logic [PLRU_BITS-1:0]    next_bits;
            logic [WAY_INDEX_W-1:0]  replacement_way_n;

            assign curr_bits = plru_bits[update_set];

            // ====================================================
            // PLRU victim select for current lookup_set
            // Registered into replacement_way on clk edge.
            // ====================================================

            always_comb begin
                int node;

                replacement_way_n = '0;
                node              = 0;

                for (int level = 0; level < LEVELS; level++) begin
                    if (plru_bits[lookup_set][node] == 1'b0) begin
                        replacement_way_n[LEVELS-1-level] = 1'b0;
                        node = (2 * node) + 1;
                    end else begin
                        replacement_way_n[LEVELS-1-level] = 1'b1;
                        node = (2 * node) + 2;
                    end
                end
            end

            // ====================================================
            // PLRU update
            // Points away from accessed / installed way.
            // ====================================================

            always_comb begin
                int node;

                next_bits = curr_bits;
                node      = 0;

                for (int level = 0; level < LEVELS; level++) begin
                    if (update_way[LEVELS-1-level] == 1'b0) begin
                        next_bits[node] = 1'b1;
                        node = (2 * node) + 1;
                    end else begin
                        next_bits[node] = 1'b0;
                        node = (2 * node) + 2;
                    end
                end
            end

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int i = 0; i < NUM_SETS; i++) begin
                        plru_bits[i] <= '0;
                    end

                    replacement_way <= '0;
                end else begin
                    if (update_valid) begin
                        plru_bits[update_set] <= next_bits;
                    end

                    replacement_way <= replacement_way_n;
                end
            end

        end
    endgenerate

endmodule