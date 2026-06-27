// ============================================================
// Dispacher
//
// CWF/data-ready dispatcher.
// No dispatch_ready.
// No miss_ready/backpressure.
//
// Assumption:
//   RS only sends dispatch_valid when this dispatcher is idle.
// ============================================================

module Dispacher #(
    parameter int DATA_WIDTH      = 32,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int MAX_WAITERS     = 4,

    localparam int WORDS_PER_LINE = (1 << WORD_OFFSET_W),
    localparam int WAITER_COUNT_W = $clog2(MAX_WAITERS + 1),
    localparam int MEM_PHASE_W    = $clog2(WORDS_PER_LINE + 1),
    localparam logic DEBUG        = 1'b0
)(
    input  logic clk,
    input  logic rst,

    input  logic [DATA_WIDTH-1:0]      delayed_miss_data,

    input  logic                       dispatch_valid,
    input  logic [WAITER_COUNT_W-1:0]  dispatch_cpu_id_count,
    input  logic [CPU_ID_WIDTH-1:0]    dispatch_cpu_ids  [MAX_WAITERS],
    input  logic [WORD_OFFSET_W-1:0]   dispatch_word_ids [MAX_WAITERS],

    output logic                       miss_valid,
    output logic [DATA_WIDTH-1:0]      miss_data,
    output logic [CPU_ID_WIDTH-1:0]    miss_id
);

    logic busy_r;

    logic [WAITER_COUNT_W-1:0] cpu_id_count_r;
    logic [WAITER_COUNT_W-1:0] sent_count_r;

    logic [WORD_OFFSET_W-1:0] critical_word_r;
    logic [MEM_PHASE_W-1:0]   mem_phase_r;

    logic [CPU_ID_WIDTH-1:0]  cpu_ids_r  [MAX_WAITERS];
    logic [WORD_OFFSET_W-1:0] word_ids_r [MAX_WAITERS];

    logic [DATA_WIDTH-1:0]     word_data_r [WORDS_PER_LINE];
    logic [WORDS_PER_LINE-1:0] word_seen_r;
    logic [MAX_WAITERS-1:0]    sent_r;

    logic new_bundle_c;
    logic refill_active_c;

    logic [WORD_OFFSET_W-1:0] cur_critical_word_c;
    logic [WORD_OFFSET_W-1:0] mem_word_c;
    logic [WORDS_PER_LINE-1:0] word_seen_eff_c;

    logic                      ready_found_c;
    logic [WAITER_COUNT_W-1:0] ready_idx_c;
    logic [WORD_OFFSET_W-1:0]  ready_word_c;
    logic [CPU_ID_WIDTH-1:0]   ready_cpu_id_c;

    logic all_sent_next_c;

    assign new_bundle_c =
        !busy_r &&
        dispatch_valid &&
        (dispatch_cpu_id_count != '0);

    assign cur_critical_word_c =
        new_bundle_c ? dispatch_word_ids[0] : critical_word_r;

    assign refill_active_c =
        new_bundle_c ||
        (busy_r && (mem_phase_r < MEM_PHASE_W'(WORDS_PER_LINE)));

    assign mem_word_c =
        WORD_OFFSET_W'((cur_critical_word_c +
                       WORD_OFFSET_W'(new_bundle_c ? 0 : mem_phase_r)) %
                       WORDS_PER_LINE);

    always_comb begin
        word_seen_eff_c = word_seen_r;

        if (new_bundle_c) begin
            word_seen_eff_c = '0;
            word_seen_eff_c[mem_word_c] = 1'b1;
        end
        else if (busy_r && (mem_phase_r < MEM_PHASE_W'(WORDS_PER_LINE))) begin
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
                if (new_bundle_c) begin
                    if ((WAITER_COUNT_W'(i) < dispatch_cpu_id_count) &&
                        word_seen_eff_c[dispatch_word_ids[i]]) begin
                        ready_found_c  = 1'b1;
                        ready_idx_c    = WAITER_COUNT_W'(i);
                        ready_word_c   = dispatch_word_ids[i];
                        ready_cpu_id_c = dispatch_cpu_ids[i];
                    end
                end
                else if (busy_r) begin
                    if ((WAITER_COUNT_W'(i) < cpu_id_count_r) &&
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

    assign miss_valid = (new_bundle_c || busy_r) && ready_found_c;
    assign miss_id    = ready_cpu_id_c;

    always_comb begin
        miss_data = word_data_r[ready_word_c];

        if (refill_active_c && (ready_word_c == mem_word_c)) begin
            miss_data = delayed_miss_data;
        end
    end

    always_comb begin
        if (new_bundle_c) begin
            all_sent_next_c =
                (dispatch_cpu_id_count == WAITER_COUNT_W'(1)) &&
                miss_valid;
        end
        else begin
            all_sent_next_c =
                busy_r &&
                ((sent_count_r + WAITER_COUNT_W'(miss_valid)) >= cpu_id_count_r);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_r          <= 1'b0;
            cpu_id_count_r  <= '0;
            sent_count_r    <= '0;
            critical_word_r <= '0;
            mem_phase_r     <= '0;
            word_seen_r     <= '0;
            sent_r          <= '0;

            for (int i = 0; i < MAX_WAITERS; i++) begin
                cpu_ids_r[i]  <= '0;
                word_ids_r[i] <= '0;
            end

            for (int w = 0; w < WORDS_PER_LINE; w++) begin
                word_data_r[w] <= '0;
            end
        end
        else begin
            if (new_bundle_c) begin
                busy_r          <= !all_sent_next_c;
                cpu_id_count_r  <= dispatch_cpu_id_count;
                sent_count_r    <= WAITER_COUNT_W'(miss_valid);
                critical_word_r <= dispatch_word_ids[0];
                mem_phase_r     <= MEM_PHASE_W'(1);
                word_seen_r     <= word_seen_eff_c;
                sent_r          <= '0;

                for (int i = 0; i < MAX_WAITERS; i++) begin
                    cpu_ids_r[i]  <= dispatch_cpu_ids[i];
                    word_ids_r[i] <= dispatch_word_ids[i];
                end

                for (int w = 0; w < WORDS_PER_LINE; w++) begin
                    word_data_r[w] <= '0;
                end

                word_data_r[mem_word_c] <= delayed_miss_data;

                if (miss_valid) begin
                    sent_r[ready_idx_c] <= 1'b1;
                end
            end
            else if (busy_r) begin
                word_seen_r <= word_seen_eff_c;

                if (mem_phase_r < MEM_PHASE_W'(WORDS_PER_LINE)) begin
                    word_data_r[mem_word_c] <= delayed_miss_data;
                    mem_phase_r <= mem_phase_r + 1'b1;
                end

                if (miss_valid) begin
                    sent_r[ready_idx_c] <= 1'b1;
                    sent_count_r <= sent_count_r + 1'b1;
                end

                if (all_sent_next_c) begin
                    busy_r      <= 1'b0;
                    mem_phase_r <= '0;
                end
            end

            if (DEBUG && miss_valid) begin
    $display("[%0t] DISP_SEND: miss_id=%0d idx=%0d word=%0d data=%h stored=%h delayed=%h phase=%0d mem_word=%0d seen=%b",
             $time,
             miss_id,
             ready_idx_c,
             ready_word_c,
             miss_data,
             word_data_r[ready_word_c],
             delayed_miss_data,
             mem_phase_r,
             mem_word_c,
             word_seen_eff_c);
end

          if (DEBUG && dispatch_valid) begin
    $display("[%0t] DISP_ACCEPT: count=%0d busy=%0b critical_word=%0d delayed_data=%h ids={%0d,%0d,%0d,%0d} words={%0d,%0d,%0d,%0d}",
             $time,
             dispatch_cpu_id_count,
             busy_r,
             dispatch_word_ids[0],
             delayed_miss_data,
             dispatch_cpu_ids[0], dispatch_cpu_ids[1],
             dispatch_cpu_ids[2], dispatch_cpu_ids[3],
             dispatch_word_ids[0], dispatch_word_ids[1],
             dispatch_word_ids[2], dispatch_word_ids[3]);
end 
        end
    end

endmodule
