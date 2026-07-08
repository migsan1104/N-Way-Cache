// ============================================================
// Dispacher
//
// Further reduced:
//   - only busy_r is reset
//   - removed critical_word_r
//   - removed modulo add path for mem_word_c
//   - uses rotating mem_word_r pointer
// ============================================================

module Dispacher #(
    parameter int DATA_WIDTH      = 32,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int MAX_WAITERS     = 4,

    localparam int WORDS_PER_LINE = (1 << WORD_OFFSET_W),
    localparam int WAITER_COUNT_W = $clog2(MAX_WAITERS + 1)
)(
    input  logic clk,
    input  logic rst,

    input  logic [DATA_WIDTH-1:0]      delayed_miss_data,

    input  logic                       dispatch_valid,
    input  logic [WORD_OFFSET_W-1:0]   dispatch_critical_word,
    input  logic [WAITER_COUNT_W-1:0]  dispatch_cpu_id_count,
    input  logic [CPU_ID_WIDTH-1:0]    dispatch_cpu_ids  [MAX_WAITERS],
    input  logic [WORD_OFFSET_W-1:0]   dispatch_word_ids [MAX_WAITERS],

    output logic                       miss_valid,
    output logic [DATA_WIDTH-1:0]      miss_data,
    output logic [CPU_ID_WIDTH-1:0]    miss_id
);

    logic busy_r;

    logic [WORD_OFFSET_W-1:0]  mem_word_r;

    logic [CPU_ID_WIDTH-1:0]   cpu_ids_r  [MAX_WAITERS];
    logic [WORD_OFFSET_W-1:0]  word_ids_r [MAX_WAITERS];

    logic [DATA_WIDTH-1:0]     word_data_r [WORDS_PER_LINE];
    logic [WORDS_PER_LINE-1:0] word_seen_r;
    logic [MAX_WAITERS-1:0]    sent_r;

    logic [MAX_WAITERS-1:0]    sent_next_c;
    logic [WORD_OFFSET_W-1:0]  mem_word_c;
    logic [WORDS_PER_LINE-1:0] word_seen_eff_c;

    logic                      ready_found_c;
    logic [WAITER_COUNT_W-1:0] ready_idx_c;
    logic [WORD_OFFSET_W-1:0]  ready_word_c;
    logic [CPU_ID_WIDTH-1:0]   ready_cpu_id_c;

    logic all_sent_next_c;

    assign mem_word_c = dispatch_valid ? dispatch_critical_word : mem_word_r;

    always_comb begin
        word_seen_eff_c = dispatch_valid ? '0 : word_seen_r;

        if (dispatch_valid || busy_r) begin
            word_seen_eff_c[mem_word_c] = 1'b1;
        end
    end

    always_comb begin
        ready_found_c  = 1'b0;
        ready_idx_c    = '0;
        ready_word_c   = '0;
        ready_cpu_id_c = '0;

        for (int i = 0; i < MAX_WAITERS; i++) begin
            if (!ready_found_c) begin
                if (dispatch_valid) begin
                    if (word_seen_eff_c[dispatch_word_ids[i]]) begin
                        ready_found_c  = 1'b1;
                        ready_idx_c    = WAITER_COUNT_W'(i);
                        ready_word_c   = dispatch_word_ids[i];
                        ready_cpu_id_c = dispatch_cpu_ids[i];
                    end
                end
                else begin
                    if (
                        !sent_r[i] &&
                        word_seen_eff_c[word_ids_r[i]]) begin
                        ready_found_c  = 1'b1;
                        ready_idx_c    = WAITER_COUNT_W'(i);
                        ready_word_c   = word_ids_r[i];
                        ready_cpu_id_c = cpu_ids_r[i];
                    end
                end
            end
        end
    end

    assign miss_valid = (dispatch_valid || busy_r) && ready_found_c;
    assign miss_id    = ready_cpu_id_c;

    always_comb begin
        miss_data = word_data_r[ready_word_c];

        if ((dispatch_valid || busy_r) && (ready_word_c == mem_word_c)) begin
            miss_data = delayed_miss_data;
        end
    end

    always_comb begin
        sent_next_c = dispatch_valid ? '1 : sent_r;

        if (dispatch_valid) begin
            for (int i = 0; i < MAX_WAITERS; i++) begin
                if (i < dispatch_cpu_id_count) begin
                    sent_next_c[i] = 1'b0;
                end
            end
        end

        if (miss_valid) begin
            sent_next_c[ready_idx_c] = 1'b1;
        end
    end

    assign all_sent_next_c = &sent_next_c;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_r <= 1'b0;
        end
        else begin
            if (dispatch_valid) begin
                busy_r         <= 1'b1;
                mem_word_r     <= dispatch_critical_word + 1'b1;
                word_seen_r    <= word_seen_eff_c;
                sent_r         <= sent_next_c;

                for (int i = 0; i < MAX_WAITERS; i++) begin
                    cpu_ids_r[i]  <= dispatch_cpu_ids[i];
                    word_ids_r[i] <= dispatch_word_ids[i];
                end

                word_data_r[mem_word_c] <= delayed_miss_data;
            end
            else begin
                word_seen_r <= word_seen_eff_c;
                sent_r      <= sent_next_c;

               
                word_data_r[mem_word_c] <= delayed_miss_data;
                mem_word_r  <= mem_word_r + 1'b1;
                

                if (all_sent_next_c) begin
                    busy_r <= 1'b0;
                end
            end
            
        end
    end

endmodule
