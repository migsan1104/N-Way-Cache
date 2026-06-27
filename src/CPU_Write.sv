// ============================================================
// CPU_Write
// Handles CPU write-hit data update only.
// Does not write tag.
// Does not write flags.
//
// DEBUG:
//   DEBUG = 1 prints when a CPU write-hit updates a cache line.
// ============================================================

module CPU_Write #(
    parameter int ASSOC         = 4,
    parameter int DATA_WIDTH    = 32,
    parameter int LINE_WIDTH    = 128,
    parameter int WAY_INDEX_W   = 2,
    parameter int WORD_OFFSET_W = 2,

    localparam bit DEBUG         = 1'b0
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

    logic [DATA_WIDTH-1:0] old_word;
    logic [LINE_WIDTH-1:0] new_line_debug;

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

    always_comb begin
        old_word       = '0;
        new_line_debug = '0;

        if (valid && hit && write) begin
            old_word       = old_line[hit_way][word_id * DATA_WIDTH +: DATA_WIDTH];
            new_line_debug = old_line[hit_way];
            new_line_debug[word_id * DATA_WIDTH +: DATA_WIDTH] = wdata;
        end
    end

    always_comb begin
        if (DEBUG && valid && hit && write) begin
            $display("[%0t] CPU_WRITE_DEBUG: hit_way=%0d word_id=%0d slice_lsb=%0d old_word=%h wdata=%h old_line=%h new_line=%h data_wen=%b",
                     $time,
                     hit_way,
                     word_id,
                     word_id * DATA_WIDTH,
                     old_word,
                     wdata,
                     old_line[hit_way],
                     new_line_debug,
                     data_wen);
        end
    end

endmodule