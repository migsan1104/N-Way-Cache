// ============================================================
// Flag_Data_Array
// ============================================================

module Flag_Data_Array #(
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
    output logic                      allocated,
    output logic                      dirty,
    output logic [WORDS_PER_LINE-1:0] word_valid,

    input  logic                      refill_wen,
    input  logic [SET_INDEX_W-1:0]    refill_waddr,
    input  logic [LINE_WIDTH-1:0]     refill_line,
    input  logic                      refill_dirty,
    input  logic                      refill_eviction,

    input  logic                      alloc_wen,
    input  logic [SET_INDEX_W-1:0]    alloc_waddr,

    input  logic                      cpu_word_wen,
    input  logic                      cpu_replace,
    input  logic [SET_INDEX_W-1:0]    cpu_waddr,
    input  logic [WORD_OFFSET_W-1:0]  cpu_word_id,
    input  logic [DATA_WIDTH-1:0]     cpu_wdata
);

    logic [LINE_WIDTH-1:0]     data_mem       [0:DEPTH-1];
    logic                      allocated_mem  [0:DEPTH-1];
    logic                      dirty_mem      [0:DEPTH-1];
    logic [WORDS_PER_LINE-1:0] word_valid_mem [0:DEPTH-1];

    logic [WORDS_PER_LINE-1:0] cpu_word_mask;

    always_comb begin
        cpu_word_mask = '0;
        cpu_word_mask[cpu_word_id] = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            rline      <= '0;
            allocated  <= 1'b0;
            dirty      <= 1'b0;
            word_valid <= '0;

            for (int i = 0; i < DEPTH; i++) begin
                data_mem[i]       <= '0;
                allocated_mem[i]  <= 1'b0;
                dirty_mem[i]      <= 1'b0;
                word_valid_mem[i] <= '0;
            end
        end
        else begin
            rline      <= data_mem[raddr];
            allocated  <= allocated_mem[raddr];
            dirty      <= dirty_mem[raddr];
            word_valid <= word_valid_mem[raddr];

            if (refill_wen) begin
                allocated_mem[refill_waddr] <= 1'b1;

                if (refill_eviction) begin
                    data_mem[refill_waddr]       <= refill_line;
                    dirty_mem[refill_waddr]      <= refill_dirty;
                    word_valid_mem[refill_waddr] <= '1;
                end
                else begin
                    for (int w = 0; w < WORDS_PER_LINE; w++) begin
                        if (!word_valid_mem[refill_waddr][w]) begin
                            data_mem[refill_waddr][w*DATA_WIDTH +: DATA_WIDTH]
                                <= refill_line[w*DATA_WIDTH +: DATA_WIDTH];
                        end
                    end

                    word_valid_mem[refill_waddr] <= '1;
                    dirty_mem[refill_waddr]      <= refill_dirty;
                end
            end

            if (alloc_wen) begin
                allocated_mem[alloc_waddr]  <= 1'b1;
                dirty_mem[alloc_waddr]      <= 1'b0;
                word_valid_mem[alloc_waddr] <= '0;
            end

            if (cpu_word_wen) begin
                data_mem[cpu_waddr][cpu_word_id*DATA_WIDTH +: DATA_WIDTH]
                    <= cpu_wdata;

                allocated_mem[cpu_waddr] <= 1'b1;
                dirty_mem[cpu_waddr]     <= 1'b1;

                if (cpu_replace) begin
                    word_valid_mem[cpu_waddr] <= cpu_word_mask;
                end
                else begin
                    word_valid_mem[cpu_waddr][cpu_word_id] <= 1'b1;
                end
            end

            if (refill_wen && (refill_waddr == raddr)) begin
                allocated <= 1'b1;
                dirty     <= refill_dirty;

                if (refill_eviction) begin
                    rline      <= refill_line;
                    word_valid <= '1;
                end
                else begin
                    for (int w = 0; w < WORDS_PER_LINE; w++) begin
                        if (!word_valid_mem[refill_waddr][w]) begin
                            rline[w*DATA_WIDTH +: DATA_WIDTH]
                                <= refill_line[w*DATA_WIDTH +: DATA_WIDTH];
                        end
                    end

                    word_valid <= '1;
                end
            end

            if (alloc_wen && (alloc_waddr == raddr)) begin
                allocated  <= 1'b1;
                dirty      <= 1'b0;
                word_valid <= '0;
            end

            if (cpu_word_wen && (cpu_waddr == raddr)) begin
                rline[cpu_word_id*DATA_WIDTH +: DATA_WIDTH] <= cpu_wdata;
                allocated <= 1'b1;
                dirty     <= 1'b1;

                if (cpu_replace) begin
                    word_valid <= cpu_word_mask;
                end
                else begin
                    word_valid[cpu_word_id] <= 1'b1;
                end
            end
        end
    end

endmodule