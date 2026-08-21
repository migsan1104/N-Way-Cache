// ============================================================
// Dispacher
//
// Entry 9: double-buffered dispatch contexts.
//   - a retire loads the free context while the other keeps
//     draining, so a back-to-back retire never overwrites a
//     stream that still owes responses
//   - waiter readiness is a registered mask (ready_r), so the
//     send scan and the data mux read flops only; the retire
//     cone ends at load enables instead of steering the
//     response path
//   - responses start the cycle after dispatch (+1 miss latency)
//   - beats always land in the newest context (capture side),
//     responses always drain the oldest (send side); loads
//     strictly alternate contexts and the send pointer flips
//     once per drain, which keeps the two pointers in lockstep
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

    logic                      live_r      [2];
    logic [CPU_ID_WIDTH-1:0]   cpu_ids_r   [2][MAX_WAITERS];
    logic [WORD_OFFSET_W-1:0]  word_ids_r  [2][MAX_WAITERS];
    logic [MAX_WAITERS-1:0]    sent_r      [2];
    logic [MAX_WAITERS-1:0]    ready_r     [2];
    logic [DATA_WIDTH-1:0]     word_data_r [2][WORDS_PER_LINE];

    logic                      cap_ctx_r;
    logic [WORD_OFFSET_W-1:0]  mem_word_r;
    logic [1:0]                beats_left_r;
    logic                      snd_ctx_r;

    logic load_ctx_c;

    logic [MAX_WAITERS-1:0]    sendable_c;
    logic                      found_c;
    logic [WAITER_COUNT_W-1:0] win_idx_c;
    logic [WORD_OFFSET_W-1:0]  win_word_c;
    logic [CPU_ID_WIDTH-1:0]   win_cpu_id_c;
    logic [MAX_WAITERS-1:0]    sent_next_c;
    logic                      drain_done_c;

    assign load_ctx_c = ~cap_ctx_r;

    // Send scan: registers only. ready_r is maintained on the capture
    // side, so a waiter is sendable the cycle after its word lands.
    assign sendable_c = ready_r[snd_ctx_r] & ~sent_r[snd_ctx_r];

    always_comb begin
        found_c      = 1'b0;
        win_idx_c    = '0;
        win_word_c   = '0;
        win_cpu_id_c = '0;

        for (int i = 0; i < MAX_WAITERS; i++) begin
            if (!found_c && sendable_c[i]) begin
                found_c      = 1'b1;
                win_idx_c    = WAITER_COUNT_W'(i);
                win_word_c   = word_ids_r[snd_ctx_r][i];
                win_cpu_id_c = cpu_ids_r[snd_ctx_r][i];
            end
        end
    end

    assign miss_valid = live_r[snd_ctx_r] && found_c;
    assign miss_id    = win_cpu_id_c;
    assign miss_data  = word_data_r[snd_ctx_r][win_word_c];

    always_comb begin
        sent_next_c = sent_r[snd_ctx_r];

        if (miss_valid) begin
            sent_next_c[win_idx_c] = 1'b1;
        end
    end

    assign drain_done_c = live_r[snd_ctx_r] && (&sent_next_c);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            live_r       <= '{default: 1'b0};
            sent_r       <= '{default: '1};
            cap_ctx_r    <= 1'b1;   // first dispatch loads context 0
            snd_ctx_r    <= 1'b0;
            beats_left_r <= '0;
        end
        else begin
            // ---- send side: drain the oldest live context ----
            if (miss_valid) begin
                sent_r[snd_ctx_r] <= sent_next_c;
            end

            if (drain_done_c) begin
                live_r[snd_ctx_r] <= 1'b0;
                snd_ctx_r         <= ~snd_ctx_r;
            end

            // ---- capture side: beats belong to the newest context ----
            if (dispatch_valid) begin
                cap_ctx_r          <= load_ctx_c;
                live_r[load_ctx_c] <= 1'b1;
                mem_word_r         <= dispatch_critical_word + 1'b1;
                beats_left_r       <= 2'd3;

                word_data_r[load_ctx_c][dispatch_critical_word]
                    <= delayed_miss_data;

                for (int i = 0; i < MAX_WAITERS; i++) begin
                    cpu_ids_r [load_ctx_c][i] <= dispatch_cpu_ids[i];
                    word_ids_r[load_ctx_c][i] <= dispatch_word_ids[i];
                    sent_r    [load_ctx_c][i] <= (i >= 32'(dispatch_cpu_id_count));
                    ready_r   [load_ctx_c][i] <=
                        (dispatch_word_ids[i] == dispatch_critical_word);
                end
            end
            else if (beats_left_r != '0) begin
                word_data_r[cap_ctx_r][mem_word_r] <= delayed_miss_data;

                for (int i = 0; i < MAX_WAITERS; i++) begin
                    if (word_ids_r[cap_ctx_r][i] == mem_word_r) begin
                        ready_r[cap_ctx_r][i] <= 1'b1;
                    end
                end

                mem_word_r   <= mem_word_r + 1'b1;
                beats_left_r <= beats_left_r - 1'b1;
            end
        end
    end

endmodule
