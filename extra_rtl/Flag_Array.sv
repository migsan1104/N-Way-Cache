// ============================================================
// Flag_Array
// One flag array for ONE WAY.
//
// Registered read.
// Same-cycle write bypass is applied to registered outputs.
//
// CPU word write:
//   allocated = 1
//   dirty = 1
//   word_valid[word_id] = 1
//
// Refill:
//   allocated = 1
//   dirty = refill_dirty
//   word_valid |= refill_word_mask
// ============================================================

module Flag_Array #(
    parameter int DEPTH          = 16,
    parameter int WORDS_PER_LINE = 4,
    parameter int SET_INDEX_W    = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int WORD_OFFSET_W  = (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE)
)(
    input  logic                         clk,
    input  logic                         rst,

    input  logic [SET_INDEX_W-1:0]       raddr,

    output logic                         allocated,
    output logic                         dirty,
    output logic [WORDS_PER_LINE-1:0]    word_valid,

    input  logic                         refill_wen,
    input  logic [SET_INDEX_W-1:0]       refill_waddr,
    input  logic [WORDS_PER_LINE-1:0]    refill_word_mask,
    input  logic                         refill_dirty,

    input  logic                         cpu_word_wen,
    input  logic [SET_INDEX_W-1:0]       cpu_waddr,
    input  logic [WORD_OFFSET_W-1:0]     cpu_word_id
);

    logic                      allocated_mem  [0:DEPTH-1];
    logic                      dirty_mem      [0:DEPTH-1];
    logic [WORDS_PER_LINE-1:0] word_valid_mem [0:DEPTH-1];

    function automatic logic [WORDS_PER_LINE-1:0] set_valid_bit;
        input logic [WORDS_PER_LINE-1:0] old_valid;
        input logic [WORD_OFFSET_W-1:0]  word_id;

        logic [WORDS_PER_LINE-1:0] result;
        begin
            result = old_valid;
            result[word_id] = 1'b1;
            return result;
        end
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            allocated  <= 1'b0;
            dirty      <= 1'b0;
            word_valid <= '0;

            for (int i = 0; i < DEPTH; i++) begin
                allocated_mem [i] <= 1'b0;
                dirty_mem     [i] <= 1'b0;
                word_valid_mem[i] <= '0;
            end
        end
        else begin
            logic                      alloc_next;
            logic                      dirty_next;
            logic [WORDS_PER_LINE-1:0] valid_next;

            // ----------------------------
            // Registered read + bypass
            // ----------------------------
            alloc_next = allocated_mem[raddr];
            dirty_next = dirty_mem[raddr];
            valid_next = word_valid_mem[raddr];

            if (refill_wen && (refill_waddr == raddr)) begin
                alloc_next = 1'b1;
                dirty_next = refill_dirty;
                valid_next = valid_next | refill_word_mask;
            end

            if (cpu_word_wen && (cpu_waddr == raddr)) begin
                alloc_next = 1'b1;
                dirty_next = 1'b1;
                valid_next = set_valid_bit(valid_next, cpu_word_id);
            end

            allocated  <= alloc_next;
            dirty      <= dirty_next;
            word_valid <= valid_next;

            // ----------------------------
            // Memory writes
            // ----------------------------
            if (refill_wen && cpu_word_wen && (refill_waddr == cpu_waddr)) begin
                allocated_mem[refill_waddr] <= 1'b1;
                dirty_mem    [refill_waddr] <= 1'b1;

                word_valid_mem[refill_waddr] <= set_valid_bit(
                    word_valid_mem[refill_waddr] | refill_word_mask,
                    cpu_word_id
                );
            end
            else begin
                if (refill_wen) begin
                    allocated_mem [refill_waddr] <= 1'b1;
                    dirty_mem     [refill_waddr] <= refill_dirty;
                    word_valid_mem[refill_waddr] <=
                        word_valid_mem[refill_waddr] | refill_word_mask;
                end

                if (cpu_word_wen) begin
                    allocated_mem [cpu_waddr] <= 1'b1;
                    dirty_mem     [cpu_waddr] <= 1'b1;
                    word_valid_mem[cpu_waddr] <= set_valid_bit(
                        word_valid_mem[cpu_waddr],
                        cpu_word_id
                    );
                end
            end
        end
    end

endmodule