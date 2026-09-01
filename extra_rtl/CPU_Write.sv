// ============================================================
// CPU_Write
// Handles CPU write-hit data update only.
// Does not write tag.
// Does not write flags.
// ============================================================

module CPU_Write #(
    parameter int ASSOC         = 4,
    parameter int DATA_WIDTH    = 32,
    parameter int LINE_WIDTH    = 128,
    parameter int WAY_INDEX_W   = 2,
    parameter int WORD_OFFSET_W = 2
)(
    input  logic                       valid,
    input  logic                       hit,
    input  logic                       write,
    input  logic [WAY_INDEX_W-1:0]     hit_way,
    input  logic [WORD_OFFSET_W-1:0]   word_id,
    input  logic [DATA_WIDTH-1:0]      wdata,
    input  logic [LINE_WIDTH-1:0]      old_line [ASSOC],

    output logic [ASSOC-1:0]           data_wen,
    output logic [LINE_WIDTH-1:0]      data_wline [ASSOC]
);

    always_comb begin
        data_wen = '0;

        for (int i = 0; i < ASSOC; i++) begin
            data_wline[i] = old_line[i];
        end

        if (valid && hit && write) begin
            data_wen[hit_way] = 1'b1;
            data_wline[hit_way][word_id * DATA_WIDTH +: DATA_WIDTH] = wdata;
        end
    end

endmodule
