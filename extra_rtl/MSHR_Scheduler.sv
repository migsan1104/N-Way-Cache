// ============================================================
// MSHR scheduler
// Chooses one allocated MSHR with pending read beats and issues
// CWF word requests to the read request queue
// ============================================================

module MSHR_Scheduler #(
    parameter int MSHR_COUNT      = 4,
    parameter int LINE_WIDTH      = 128,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int WORD_OFFSET_W   = 2,
    parameter int MSHR_ID_WIDTH   = 2
)(
    input  logic clk,
    input  logic rst,

    // One bit per MSHR entry saying this entry still needs read beats issued
    input  logic [MSHR_COUNT-1:0] issue_pending,

    // Metadata from MSHR entries
    input  logic [LINE_ADDR_WIDTH-1:0] issue_line_addr [MSHR_COUNT],
    input  logic [WORD_OFFSET_W-1:0]   issue_word_id   [MSHR_COUNT],

    // Clear issue_pending for this MSHR after all beats are accepted
    output logic                       issue_done_valid,
    output logic [MSHR_ID_WIDTH-1:0]   issue_done_mshr_id,

    // Read request queue push
    output logic                       miss_valid,
    input  logic                       miss_ready,
    output logic [LINE_ADDR_WIDTH+WORD_OFFSET_W-1:0] miss_word_addr,
    output logic [MSHR_ID_WIDTH-1:0]   miss_id
);

    localparam int WORDS_PER_LINE = LINE_WIDTH / DATA_WIDTH;

    typedef enum logic [0:0] {
        S_IDLE,
        S_SEND_BEATS
    } state_t;

    state_t state;

    logic                       found_pending;
    logic [MSHR_ID_WIDTH-1:0]   selected_mshr_id;

    logic [MSHR_ID_WIDTH-1:0]   active_mshr_id;
    logic [LINE_ADDR_WIDTH-1:0] active_line_addr;
    logic [WORD_OFFSET_W-1:0]   active_word_id;
    logic [WORD_OFFSET_W-1:0]   beat_count;
    logic [WORD_OFFSET_W-1:0]   send_word_id;

    logic beat_fire;
    logic last_beat;

    // Pick the first MSHR that still needs read beats issued
    always_comb begin
        found_pending    = 1'b0;
        selected_mshr_id = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (issue_pending[i] && !found_pending) begin
                found_pending    = 1'b1;
                selected_mshr_id = i[MSHR_ID_WIDTH-1:0];
            end
        end
    end

    assign send_word_id = active_word_id + beat_count;

    assign miss_valid     = (state == S_SEND_BEATS);
    assign miss_word_addr = {active_line_addr, send_word_id};
    assign miss_id        = active_mshr_id;

    assign beat_fire = miss_valid && miss_ready;
    assign last_beat = (beat_count == WORDS_PER_LINE-1);

    assign issue_done_valid   = beat_fire && last_beat;
    assign issue_done_mshr_id = active_mshr_id;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= S_IDLE;
            active_mshr_id   <= '0;
            active_line_addr <= '0;
            active_word_id   <= '0;
            beat_count       <= '0;
        end
        else begin

            case (state)

                S_IDLE: begin
                    if (found_pending) begin
                        active_mshr_id   <= selected_mshr_id;
                        active_line_addr <= issue_line_addr[selected_mshr_id];
                        active_word_id   <= issue_word_id[selected_mshr_id];
                        beat_count       <= '0;
                        state            <= S_SEND_BEATS;
                    end
                end

                S_SEND_BEATS: begin
                    if (beat_fire) begin
                        if (last_beat) begin
                            beat_count <= '0;
                            state      <= S_IDLE;
                        end
                        else begin
                            beat_count <= beat_count + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase

        end
    end

endmodule