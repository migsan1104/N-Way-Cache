// ============================================================
// Data_Array
// One data array for ONE WAY.
//
// Registered read.
// CPU same-cycle word-write bypass only.
//
// Storage is line-wide:
//   mem[set] = full cache line
//
// Writes:
//   refill_wen   -> masked line write
//   cpu_word_wen -> one word write
//
// Priority:
//   refill first, CPU word write wins if same set/word.
// ============================================================

module Data_Array #(
    parameter int DATA_WIDTH     = 32,
    parameter int LINE_WIDTH     = 128,
    parameter int DEPTH          = 16,
    parameter int SET_INDEX_W    = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int WORDS_PER_LINE = LINE_WIDTH / DATA_WIDTH,
    parameter int WORD_OFFSET_W  = (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE)
)(
    input  logic                      clk,
    input  logic                      rst,

    input  logic [SET_INDEX_W-1:0]    raddr,
    output logic [LINE_WIDTH-1:0]     rline,

    input  logic                      refill_wen,
    input  logic [SET_INDEX_W-1:0]    refill_waddr,
    input  logic [LINE_WIDTH-1:0]     refill_line,
    input  logic [WORDS_PER_LINE-1:0] refill_word_mask,

    input  logic                      cpu_word_wen,
    input  logic [SET_INDEX_W-1:0]    cpu_waddr,
    input  logic [WORD_OFFSET_W-1:0]  cpu_word_id,
    input  logic [DATA_WIDTH-1:0]     cpu_wdata
);

    logic [LINE_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            

            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
        end
        else begin
            // Registered read.
            rline <= mem[raddr];

            // Same-cycle CPU word write bypass into registered read output.
            if (cpu_word_wen && (cpu_waddr == raddr)) begin
                rline[cpu_word_id*DATA_WIDTH +: DATA_WIDTH] <= cpu_wdata;
            end

            // Masked refill line write.
            for (int w = 0; w < WORDS_PER_LINE; w++) begin
                if (refill_wen && refill_word_mask[w]) begin
                    mem[refill_waddr][w*DATA_WIDTH +: DATA_WIDTH]
                        <= refill_line[w*DATA_WIDTH +: DATA_WIDTH];
                end
            end

            // CPU word write has final priority for same set/word.
            if (cpu_word_wen) begin
                mem[cpu_waddr][cpu_word_id*DATA_WIDTH +: DATA_WIDTH]
                    <= cpu_wdata;
            end
        end
    end

endmodule