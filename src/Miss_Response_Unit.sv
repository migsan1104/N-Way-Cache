// ============================================================
// MSHR Response Unit
// Splits one in-phase MSHR refill beat into:
//   1. CPU response path for critical word
//   2. Cache refill/write path for every returned beat
//   3. MSHR free pulse on last beat
// ============================================================

module MSHR_Response_Unit #(
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int MSHR_ID_WIDTH   = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic                       mshr_resp_valid,
    input  logic [DATA_WIDTH-1:0]      mshr_resp_data,

    input  logic [CPU_ID_WIDTH-1:0]    mshr_resp_cpu_req_id,
    input  logic [MSHR_ID_WIDTH-1:0]   mshr_resp_mshr_id,

    input  logic [LINE_ADDR_WIDTH-1:0] mshr_resp_line_addr,
    input  logic [SET_INDEX_W-1:0]     mshr_resp_set_id,
    input  logic [WORD_OFFSET_W-1:0]   mshr_resp_word_id,
    input  logic [TAG_WIDTH-1:0]       mshr_resp_tag,
    input  logic [WAY_INDEX_W-1:0]     mshr_resp_way,

    input  logic                       mshr_resp_write,
    input  logic [DATA_WIDTH-1:0]      mshr_resp_wdata,

    input  logic                       mshr_resp_is_critical,
    input  logic                       mshr_resp_is_last,

    output logic                       cpu_resp_valid,
    output logic [CPU_ID_WIDTH-1:0]    cpu_resp_id,
    output logic [DATA_WIDTH-1:0]      cpu_resp_data,
    output logic                       cpu_resp_write,

    output logic                       refill_valid,
    output logic [LINE_ADDR_WIDTH-1:0] refill_line_addr,
    output logic [SET_INDEX_W-1:0]     refill_set_id,
    output logic [WORD_OFFSET_W-1:0]   refill_word_id,
    output logic [TAG_WIDTH-1:0]       refill_tag,
    output logic [WAY_INDEX_W-1:0]     refill_way,
    output logic [DATA_WIDTH-1:0]      refill_data,
    output logic                       refill_dirty,
    output logic                       refill_last,

    output logic                       free_valid,
    output logic [MSHR_ID_WIDTH-1:0]   free_mshr_id
);

    logic [DATA_WIDTH-1:0] selected_data;

    always_comb begin
        selected_data = mshr_resp_data;

        if (mshr_resp_write && mshr_resp_is_critical) begin
            selected_data = mshr_resp_wdata;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cpu_resp_valid   <= 1'b0;
            cpu_resp_id      <= '0;
            cpu_resp_data    <= '0;
            cpu_resp_write   <= 1'b0;

            refill_valid     <= 1'b0;
            refill_line_addr <= '0;
            refill_set_id    <= '0;
            refill_word_id   <= '0;
            refill_tag       <= '0;
            refill_way       <= '0;
            refill_data      <= '0;
            refill_dirty     <= 1'b0;
            refill_last      <= 1'b0;

            free_valid       <= 1'b0;
            free_mshr_id     <= '0;
        end
        else begin
            cpu_resp_valid <= mshr_resp_valid && mshr_resp_is_critical;
            cpu_resp_id    <= mshr_resp_cpu_req_id;
            cpu_resp_data  <= selected_data;
            cpu_resp_write <= mshr_resp_write;

            refill_valid     <= mshr_resp_valid;
            refill_line_addr <= mshr_resp_line_addr;
            refill_set_id    <= mshr_resp_set_id;
            refill_word_id   <= mshr_resp_word_id;
            refill_tag       <= mshr_resp_tag;
            refill_way       <= mshr_resp_way;
            refill_data      <= selected_data;
            refill_dirty     <= mshr_resp_write;
            refill_last      <= mshr_resp_is_last;

            free_valid   <= mshr_resp_valid && mshr_resp_is_last;
            free_mshr_id <= mshr_resp_mshr_id;
        end
    end

endmodule