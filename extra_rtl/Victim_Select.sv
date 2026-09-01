// ============================================================
// Victim_Select
//
// Phase:
//   Runs with compare stage using array-read flag outputs.
//
// Purpose:
//   Finds the first unallocated way.
//   Does not know or care whether the request is a hit or miss.
//   Does not update PLRU.
//
// Cache.sv decides:
//   - if compare miss, use this regular victim if found
//   - otherwise advance to Replacement
// ============================================================

module Victim_Select #(
    parameter int ASSOC = 4,
    parameter int WAY_W = (ASSOC <= 1) ? 1 : $clog2(ASSOC)
)(
    input  logic             clk,
    input  logic             rst,

    input  logic [ASSOC-1:0] allocated_vec,

    output logic             regular_found,
    output logic [WAY_W-1:0] regular_way
);

    logic             regular_found_c;
    logic [WAY_W-1:0] regular_way_c;

    always_comb begin
        regular_found_c = 1'b0;
        regular_way_c   = '0;

        for (int i = 0; i < ASSOC; i++) begin
            if (!allocated_vec[i] && !regular_found_c) begin
                regular_found_c = 1'b1;
                regular_way_c   = WAY_W'(i);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            regular_found <= 1'b0;
            regular_way   <= '0;
        end
        else begin
            regular_found <= regular_found_c;
            regular_way   <= regular_way_c;
        end
    end

endmodule