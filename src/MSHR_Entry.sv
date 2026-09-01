// ============================================================
// Single MSHR entry - reduced version
//
// Keeps victim_word_valid so dirty victim writeback only writes
// valid victim words.
//
// Entry 18: holds a POINTER to the victim line (its RS vbuf slot),
// not a copy - writeback beats read the vbuf one word at a time.
// See the vbuf section of Reservation_Station.sv for the full story.
//
// Removed:
//   - alloc_write / alloc_wdata storage
//   - write_r / wdata_r
//   - refill_dirty / refill_eviction refill metadata
//   - alloc_mshr_id / mshr_id register/output
//   - S_REFILL state
//
// Uses fixed ENTRY_ID parameter for req_mshr_id.
// ============================================================

module MSHR_Entry #(
    parameter int ADDR_WIDTH      = 32,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int MSHR_ID_WIDTH   = 2,
    parameter int ENTRY_ID        = 0,

    // Entry 18: width of a Reservation Station vbuf slot id.
    parameter int VBUF_SLOT_W     = 4
)(
    input  logic clk,
    input  logic rst,

    input  logic alloc,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,
    input  logic [SET_INDEX_W-1:0]     alloc_set_id,
    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [TAG_WIDTH-1:0]       alloc_tag,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,

    // Entry 18: the victim LINE stays in the RS vbuf; this entry latches
    // only the slot it lives in and reads it back one word per writeback
    // beat (wb_slot/wb_word out, data muxed onto the memory port at the
    // file level).
    input  logic                       alloc_victim_dirty,
    input  logic [TAG_WIDTH-1:0]       alloc_victim_tag,
    input  logic [VBUF_SLOT_W-1:0]     alloc_victim_slot,
    input  logic [LINE_WIDTH/DATA_WIDTH-1:0] alloc_victim_word_valid,

    input  logic                       issue_done,

    input  logic                       resp_valid,
    input  logic [DATA_WIDTH-1:0]      resp_data,

    output logic                       valid,
    output logic                       issue_pending,

    output logic                       req_valid,
    output logic                       req_write,
    output logic [ADDR_WIDTH-1:0]      req_addr,
    output logic [MSHR_ID_WIDTH-1:0]   req_mshr_id,

    // Entry 18: coordinates of the victim word this entry would write
    // back this cycle. The file muxes the GRANTED entry's coordinates
    // into the vbuf read port and drives the memory write data from it.
    output logic [VBUF_SLOT_W-1:0]     wb_slot,
    output logic [WORD_OFFSET_W-1:0]   wb_word,
    // Entry 27b: the word this entry will present NEXT cycle (its own
    // counter's D value - includes both granted-beat advances and
    // beat-skips over invalid victim words). Feeds the vbuf pre-read.
    output logic [WORD_OFFSET_W-1:0]   wb_word_n,

    output logic [LINE_ADDR_WIDTH-1:0] line_addr,
    output logic [SET_INDEX_W-1:0]     set_id,
    output logic [WORD_OFFSET_W-1:0]   word_id,
    output logic [TAG_WIDTH-1:0]       tag,
    output logic [WAY_INDEX_W-1:0]     way,

    output logic                       refill_wen,
    output logic [LINE_WIDTH-1:0]      fill_line
);

    localparam int WORDS_PER_LINE = LINE_WIDTH / DATA_WIDTH;
    localparam int BEAT_COUNT_W   = (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE);

    typedef enum logic [2:0] {
        S_IDLE,
        S_ISSUE_W,
        S_ISSUE_R,
        S_WAIT_R
    } state_t;

    state_t state, state_n;

    logic [BEAT_COUNT_W-1:0] wb_count, wb_count_n;
    logic [BEAT_COUNT_W-1:0] issue_count, issue_count_n;
    logic [BEAT_COUNT_W-1:0] recv_count, recv_count_n;

    logic [WORD_OFFSET_W-1:0] miss_word_id_r, miss_word_id_n;
    logic [WORD_OFFSET_W-1:0] wb_word_id;
    logic [WORD_OFFSET_W-1:0] read_issue_word_id;
    logic [WORD_OFFSET_W-1:0] read_recv_word_id;

    // Entry 18: the victim's DATA is not copied here. Before this entry,
    // a 128-bit victim_line_r register captured the whole line at alloc
    // and req_wdata muxed words out of it - four such copies (one per
    // MSHR) plus their 155-bit RS->MSHR capture routes owned the worst
    // timing path in every measured build. The insight: the line already
    // lives in the RS victim buffer, it is write-once, and the memory
    // port only ever consumes it ONE WORD PER BEAT - so a copy buys
    // nothing a pointer doesn't. victim_slot_r is that pointer. The tag
    // and word_valid mask stay as registers: they are ~25 bits, and the
    // FSM needs them combinationally every writeback cycle (address
    // formation, beat skipping).
    logic [TAG_WIDTH-1:0] victim_tag_r, victim_tag_n;
    logic [VBUF_SLOT_W-1:0] victim_slot_r, victim_slot_n;
    logic [WORDS_PER_LINE-1:0] victim_word_valid_r, victim_word_valid_n;
    logic [LINE_ADDR_WIDTH-1:0] victim_line_addr;

    logic [LINE_ADDR_WIDTH-1:0] line_addr_n;
    logic [SET_INDEX_W-1:0]     set_id_n;
    logic [TAG_WIDTH-1:0]       tag_n;
    logic [WAY_INDEX_W-1:0]     way_n;

    logic [LINE_WIDTH-1:0] fill_line_r, fill_line_n;

    logic refill_wen_r, refill_wen_n;
    logic retire_hold_r;   // Entry 30(a): refill_wen one cycle later

    assign wb_word_id = wb_count[WORD_OFFSET_W-1:0];

    assign read_issue_word_id =
        miss_word_id_r + issue_count[WORD_OFFSET_W-1:0];

    assign read_recv_word_id =
        miss_word_id_r + recv_count[WORD_OFFSET_W-1:0];

    assign victim_line_addr = {victim_tag_r, set_id};

    // Entry 30(a): the RS-side retire now arrives one cycle after the
    // refill pulse (registered in MSHR_File), so the entry must stay
    // busy through that cycle too - otherwise a new RS issue could
    // re-bind this MSHR while its old retire is still in flight, and
    // the file-level entry_word_id[retire_idx] read (the Dispacher's
    // critical word) would see the NEW request's registers.
    // retire_hold_r is refill_wen one cycle later: busy = FSM active,
    // OR refill pulse cycle (pre-existing), OR retire cycle (new).
    assign valid = (state != S_IDLE) || refill_wen || retire_hold_r;

    assign issue_pending =
        (state == S_ISSUE_W) ||
        (state == S_ISSUE_R);

    assign req_valid =
        ((state == S_ISSUE_W) && victim_word_valid_r[wb_word_id]) ||
        (state == S_ISSUE_R);

    assign req_write   = (state == S_ISSUE_W);
    assign req_mshr_id = ENTRY_ID[MSHR_ID_WIDTH-1:0];

    assign req_addr =
        (state == S_ISSUE_W)
        ? {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
           victim_line_addr,
           wb_word_id}
        : {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
           line_addr,
           read_issue_word_id};

    // Entry 18: instead of driving write data from a local copy, expose
    // WHERE the word lives (slot) and WHICH word this beat wants. These
    // are continuously valid whenever req_valid could be granted; the
    // file-level mux reads the vbuf for whichever entry the arbiter
    // grants this cycle. The read replaces a register mux with a shallow
    // LUTRAM lookup on the memory-port side, where nothing is critical.
    assign wb_slot = victim_slot_r;
    assign wb_word = wb_word_id;
    assign wb_word_n = wb_count_n[WORD_OFFSET_W-1:0];   // Entry 27b

    assign word_id         = miss_word_id_r;
    assign fill_line       = fill_line_r;
    assign refill_wen      = refill_wen_r;

    always_comb begin
        state_n        = state;

        wb_count_n     = wb_count;
        issue_count_n  = issue_count;
        recv_count_n   = recv_count;

        line_addr_n    = line_addr;
        set_id_n       = set_id;
        miss_word_id_n = miss_word_id_r;
        tag_n          = tag;
        way_n          = way;

        victim_tag_n   = victim_tag_r;
        victim_slot_n  = victim_slot_r;
        victim_word_valid_n = victim_word_valid_r;

        fill_line_n    = fill_line_r;

        refill_wen_n      = 1'b0;

        // Entry 35(b) (2026-08-25): the payload captures whenever the
        // entry is FREE (!valid), not only on the alloc grant. valid is
        // the busy extension that covers every reader past IDLE - the
        // Mux latches set_id/tag/way at refill_wen (IDLE+1) and the
        // Dispacher reads word_id under retire_hold_r (IDLE+2) - and
        // MSHR_File allocates only to !entry_valid, so alloc implies
        // !valid: every cycle alloc loaded these before, !valid loads the
        // same value now; on !valid && !alloc cycles they load an unread
        // don't-care. The grant term - rs_issue_valid (the RS
        // valid && !in_progress scan) and the free-entry priority scan -
        // leaves the load-enable; what remains is three local flops
        // (state, refill_wen_r, retire_hold_r). Counters and state_n
        // stay under alloc: they carry meaning. Measured reason (e29an
        // census): rs[valid] -> victim_tag_r 81 @ -274, rs[in_progress]
        // -> victim_tag_r 61 @ -329 (e29all), rs[valid] -> line_addr /
        // tag 20 + 18.
        if (!valid) begin
            line_addr_n    = alloc_line_addr;
            set_id_n       = alloc_set_id;
            miss_word_id_n = alloc_word_id;
            tag_n          = alloc_tag;
            way_n          = alloc_way;

            victim_tag_n   = alloc_victim_tag;
            victim_slot_n  = alloc_victim_slot;
            victim_word_valid_n = alloc_victim_word_valid;
        end

        case (state)

            S_IDLE: begin
                if (alloc) begin
                    wb_count_n     = '0;
                    issue_count_n  = '0;
                    recv_count_n   = '0;
                  

                    if (alloc_victim_dirty)
                        state_n = S_ISSUE_W;
                    else
                        state_n = S_ISSUE_R;
                end
            end

            S_ISSUE_W: begin
                if (!victim_word_valid_r[wb_word_id]) begin
                    if (wb_count == WORDS_PER_LINE-1) begin
                        wb_count_n = '0;
                        state_n    = S_ISSUE_R;
                    end
                    else begin
                        wb_count_n = wb_count + 1'b1;
                    end
                end
                else if (issue_done) begin
                    if (wb_count == WORDS_PER_LINE-1) begin
                        wb_count_n = '0;
                        state_n    = S_ISSUE_R;
                    end
                    else begin
                        wb_count_n = wb_count + 1'b1;
                    end
                end
            end

            S_ISSUE_R: begin
                if (issue_done) begin
                    if (issue_count == WORDS_PER_LINE-1) begin
                        issue_count_n = '0;
                        state_n       = S_WAIT_R;
                    end
                    else begin
                        issue_count_n = issue_count + 1'b1;
                    end
                end
            end

            S_WAIT_R: begin
                // Wait for remaining memory responses.
            end

            default: begin
                state_n = S_IDLE;
            end

        endcase

        // Entry 35(d) (2026-08-25): the beat DATA lands on state alone;
        // resp_valid gates only the counter / refill_wen / state. Between
        // beats the write hits slot recv_count - the next UNWRITTEN slot -
        // and the real beat overwrites it on the same edge it advances
        // recv_count. On the 4th beat the FSM leaves S_WAIT_R on that
        // same edge, so nothing is written after the line is complete and
        // the Mux read at IDLE+1 sees a clean fill_line_r. (The guard must
        // be S_WAIT_R, not !valid: one more write would wrap onto the
        // critical-word slot while the Mux reads it.) Takes
        // mshr_resp_valid[i] off 128 enable pins per entry; no census
        // class - a discipline letter, expected unmeasurable.
        if (state == S_WAIT_R) begin
            fill_line_n[read_recv_word_id * DATA_WIDTH +: DATA_WIDTH] = resp_data;
        end

        if (resp_valid) begin
            if (recv_count == WORDS_PER_LINE-1) begin
                recv_count_n      = '0;
                refill_wen_n      = 1'b1;
                state_n           = S_IDLE;
            end
            else begin
                recv_count_n = recv_count + 1'b1;
            end
        end
    end

    // Entry 29(c): synchronous reset (was async). Reset VALUES and branches
    // are unchanged - this is a cell-mapping edit: an async reset pin is
    // architectural (dfrtp/sdfrtp/dfstp), a sync one Genus folds into the
    // D-side logic and maps to dfxtp.
    // The FSM state is this entry's one reset ROOT.
    always_ff @(posedge clk) begin
        if (rst) begin
            state             <= S_IDLE;
        end
        else begin
            state             <= state_n;
        end
    end

    // Entry 29(l) (2026-08-25): refill_wen_r loses its reset. Its D is
    // refill_wen_n = resp_valid && (recv_count == WORDS_PER_LINE-1), and
    // resp_valid is MSHR_Response_DeMux.mshr_resp_valid, which KEEPS its
    // reset: 0 at the first reset edge, so refill_wen_r is a defined 0
    // at the second (recv_count is reset-free and X, but 0 && X = 0 in
    // sim as in silicon). Everything derived from it follows one edge
    // later - retire_hold_r (e3), MSHR_Mux.refill_wen (e3, the E29(d)
    // argument), MSHR_File.retire_valid_r (e3) - and rst is held five.
    // `valid` (state != IDLE || refill_wen || retire_hold) is X for two
    // edges in sim; its only consumer is the free-entry select, whose
    // fire term is ANDed with the RS's issue_valid, which descends from
    // the reset-held rs[*].valid bits. Silicon: a random pulse during
    // the flush cycles reaches the array behind FTDA's reset-held
    // refill_stage_v_r/pending pair (see 29(m) there) and the RS
    // retire behind reset-held valid_count - i.e. nowhere.
    always_ff @(posedge clk) begin
        refill_wen_r  <= refill_wen_n;
        retire_hold_r <= refill_wen_r;
    end

    // Entry 29(e) (2026-08-25): retire_hold_r lost its reset first
    // (Entry 30(a) had given it one - "must read free from cycle one");
    // it is refill_wen_r delayed by one edge, so it is defined one edge
    // after refill_wen_r is - e3 since 29(l). It now lives in the
    // reset-free block above with its source.

    always_ff @(posedge clk) begin
        wb_count       <= wb_count_n;
        issue_count    <= issue_count_n;
        recv_count     <= recv_count_n;

        line_addr      <= line_addr_n;
        set_id         <= set_id_n;
        miss_word_id_r <= miss_word_id_n;
        tag            <= tag_n;
        way            <= way_n;

        victim_tag_r   <= victim_tag_n;
        victim_slot_r  <= victim_slot_n;
        victim_word_valid_r <= victim_word_valid_n;

        fill_line_r    <= fill_line_n;
    end

endmodule
