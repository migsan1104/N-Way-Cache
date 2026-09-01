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

    // Entry 29(c): synchronous reset (was async). Reset VALUES and branches
    // are unchanged - this is a cell-mapping edit: an async reset pin is
    // architectural (dfrtp/sdfrtp/dfstp), a sync one Genus folds into the
    // D-side logic and maps to dfxtp.
    // Entry 29(j) (2026-08-25): sent_r and beats_left_r lose their reset.
    // live_r / cap_ctx_r / snd_ctx_r are the roots and keep theirs (the
    // two context pointers are a lockstep pair - an X pointer would
    // index-write nothing in sim and the wrong context in silicon).
    //   sent_r: every reader is ANDed with live_r[snd_ctx_r] (miss_valid,
    //     drain_done_c) - 0 && X = 0 - and a dispatch writes the whole
    //     vector of the context it loads. Its reset value was '1, which
    //     is what put these 8 flops on SET-type cells (dfstp).
    //   beats_left_r: the capture branch is `else if (beats_left_r != 0)`
    //     - in sim X != 0 is X and the branch is not taken; in silicon
    //     a random count drains garbage beats into the NON-live context
    //     (word_data_r / ready_r of cap_ctx_r), which the next dispatch
    //     into that context rewrites in full before anything reads it.
    //     The first dispatch loads 3 either way.
    // Entry 29(o) (2026-08-25): the send/capture logic leaves the
    // else-branch; the reset block moves to the END of the process so the
    // last assignment wins and live_r / cap_ctx_r / snd_ctx_r behave
    // exactly as before. Everything else in here has no reset value, and
    // under `else` rst was a hold-enable that Genus routed into the scan
    // mux of every payload flop (e29cd: rst -> cpu_ids_r/SCE -111 x13,
    // worst flop-rooted path to the same pins > +300). Reset-window
    // safety: dispatch_valid is retire_valid_r (0 from the second reset
    // edge), miss_valid / drain_done_c are live_r-qualified, and a
    // garbage beats_left_r writes only the non-live context - the E29(j)
    // argument, unchanged.
    always_ff @(posedge clk) begin
        begin
            // ---- send side: drain the oldest live context ----
            // Entry 35(c) (2026-08-25): the miss_valid guard is gone.
            // sent_next_c is sent_r[snd_ctx_r] with one bit set ONLY when
            // miss_valid, so the unguarded write stores the value already
            // held whenever the guard was false - bit-identical by
            // construction; live_r && found_c leaves the load-enable. The
            // dispatch_valid write below stays later in the block and
            // still wins on a same-context cycle, as before.
            sent_r[snd_ctx_r] <= sent_next_c;

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

        if (rst) begin
            live_r       <= '{default: 1'b0};
            cap_ctx_r    <= 1'b1;   // first dispatch loads context 0
            snd_ctx_r    <= 1'b0;
        end
    end

endmodule
