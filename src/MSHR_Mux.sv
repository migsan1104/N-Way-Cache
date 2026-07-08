module MSHR_Mux #(
    parameter int MSHR_COUNT  = 4,
    parameter int SET_INDEX_W = 4,
    parameter int TAG_WIDTH   = 16,
    parameter int WAY_INDEX_W = 2,
    parameter int LINE_WIDTH  = 128
)(
    input  logic clk,
    input  logic rst,

    input  logic [MSHR_COUNT-1:0]  entry_refill_wen,
    input  logic [SET_INDEX_W-1:0] entry_set_id    [MSHR_COUNT],
    input  logic [TAG_WIDTH-1:0]   entry_tag       [MSHR_COUNT],
    input  logic [WAY_INDEX_W-1:0] entry_way       [MSHR_COUNT],
    input  logic [LINE_WIDTH-1:0]  entry_fill_line [MSHR_COUNT],

    output logic                   refill_wen,
    output logic [SET_INDEX_W-1:0] refill_set_id,
    output logic [TAG_WIDTH-1:0]   refill_tag,
    output logic [WAY_INDEX_W-1:0] refill_way,
    output logic [LINE_WIDTH-1:0]  refill_line
);

    logic found;
    logic [$clog2(MSHR_COUNT)-1:0] sel;

    always_comb begin
        found = 1'b0;
        sel   = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (entry_refill_wen[i] && !found) begin
                found = 1'b1;
                sel   = i[$clog2(MSHR_COUNT)-1:0];
            end
        end
    end

    always_ff @(posedge clk) begin
        refill_wen <= found;
        refill_line      <= entry_fill_line[sel];
        refill_set_id    <= entry_set_id[sel];
        refill_tag       <= entry_tag[sel];
        refill_way       <= entry_way[sel];
        
    end

endmodule
