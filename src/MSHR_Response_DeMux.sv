// ============================================================
// MSHR response valid demux
// Broadcasts registered response data to all MSHRs
// Routes registered valid pulse by response ID
//
// IMPORTANT:
//   mshr_resp_valid and mshr_resp_data are phase-aligned.
// ============================================================

module MSHR_Response_DeMux #(
    parameter int MSHR_COUNT    = 4,
    parameter int DATA_WIDTH    = 32,
    parameter int MSHR_ID_WIDTH = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic                     mem_resp_valid,
    input  logic [MSHR_ID_WIDTH-1:0] mem_resp_id,
    input  logic [DATA_WIDTH-1:0]    mem_resp_rdata,

    output logic [MSHR_COUNT-1:0]    mshr_resp_valid,
    output logic [DATA_WIDTH-1:0]    mshr_resp_data
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mshr_resp_valid <= '0;
          
        end
        else begin
            mshr_resp_valid <= '0;

            if (mem_resp_valid) begin
                mshr_resp_valid[mem_resp_id] <= 1'b1;
            end
        end
    end
    always_ff @(posedge clk) begin
        mshr_resp_data <= mem_resp_rdata;
    end
endmodule