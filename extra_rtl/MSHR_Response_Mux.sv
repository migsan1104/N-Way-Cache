// ============================================================
// Pipelined MSHR response metadata mux
//
// Muxes miss response ID metadata into the Response_Unit path.
// No enable is needed. No reset is needed.
// Correctness relies on phase alignment with miss_valid.
//
// Assumption:
// - entry_miss_valid is zero-hot or one-hot.
// - miss_valid is pipelined separately/in phase with miss_id.
// - miss data is delayed separately to match this mux latency.
// ============================================================

module MSHR_Response_Mux #(
    parameter int MSHR_COUNT   = 4,
    parameter int CPU_ID_WIDTH = 4
)(
    input  logic clk,

    input  logic [MSHR_COUNT-1:0]   entry_miss_valid,
    input  logic [CPU_ID_WIDTH-1:0] entry_miss_id [MSHR_COUNT],

    output logic [CPU_ID_WIDTH-1:0] miss_id
);

    logic [CPU_ID_WIDTH-1:0] miss_id_next;

    always_comb begin
        miss_id_next = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (entry_miss_valid[i]) begin
                miss_id_next = entry_miss_id[i];
            end
        end
    end

    always_ff @(posedge clk) begin
        miss_id <= miss_id_next;
    end

endmodule