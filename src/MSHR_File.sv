// ============================================================
// 4-entry MSHR file with Reservation Station + Dispacher
//
// MSHR_Entry no longer tracks CPU IDs.
// Reservation_Station owns CPU waiter IDs.
// Dispacher emits CPU miss response IDs + data.
//
// Refill path is separate:
//   MSHR_Entry -> MSHR_Mux -> cache refill arrays
//
// CPU miss data is delayed outside this file, then passed into
// Dispacher so miss_valid/miss_id/miss_data stay aligned.
// ============================================================

module MSHR_File #(
    parameter int ADDR_WIDTH      = 32,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int MSHR_ID_WIDTH   = 2,
    parameter int MISSQ_DEPTH     = 64,
    parameter int MSHR_AF         = 7,
    parameter int MAX_WAITERS     = 4
)(
    input  logic clk,
    input  logic rst,

    input  logic                       alloc_valid,
    output logic                       alloc_ready,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,

    // Compare-stage line address, one cycle ahead of alloc_line_addr
    // (Entry 11) - pass-through for the RS same-line CAM precompute.
    input  logic [LINE_ADDR_WIDTH-1:0] pre_line_addr,

    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,

    input  logic                       alloc_write,
    input  logic [DATA_WIDTH-1:0]      alloc_wdata,
    input  logic [CPU_ID_WIDTH-1:0]    alloc_cpu_req_id,

    input  logic                       alloc_victim_dirty,
    input  logic [TAG_WIDTH-1:0]       alloc_victim_tag,
    input  logic [LINE_WIDTH-1:0]      alloc_victim_line,
    input  logic [LINE_WIDTH/DATA_WIDTH-1:0] alloc_victim_word_valid,

    input  logic [3:0]                 issue_done,
    // Entry 23: arbiter's order-head entry (pre-qualification).
    // Entry 31: ONE-HOT over entries, so the wb selects below are an
    // AND-OR reduce instead of a mux whose index had to be decoded.
    // Width is the literal 4 for the same reason issue_done above is:
    // MSHR_COUNT is a localparam declared in the body, after the ports.
    input  logic [3:0]                 head_oh,

    input  logic                       mem_resp_valid,
    input  logic [MSHR_ID_WIDTH-1:0]   mem_resp_id,
    input  logic [DATA_WIDTH-1:0]      mem_resp_rdata,

    input  logic [DATA_WIDTH-1:0]      delayed_miss_data,

    output logic                       miss_valid,
    output logic [DATA_WIDTH-1:0]      miss_data,
    output logic [CPU_ID_WIDTH-1:0]    miss_id,

    output logic                       refill_wen,
    output logic [SET_INDEX_W-1:0]     refill_set_id,
    output logic [TAG_WIDTH-1:0]       refill_tag,
    output logic [WAY_INDEX_W-1:0]     refill_way,
    output logic [LINE_WIDTH-1:0]      refill_line,

    output logic [3:0]                 issue_pending,

    output logic [3:0]                 req_valid,
    output logic [3:0]                 req_write,
    output logic [ADDR_WIDTH-1:0]      req_addr  [4],
    // Entry 23: the victim word for the order-head entry (was four
    // identical per-entry data lanes).
    output logic [DATA_WIDTH-1:0]      wb_data,
    output logic [MSHR_ID_WIDTH-1:0]   req_id    [4]
);

    localparam int MSHR_COUNT     = 4;
    localparam int RS_ID_WIDTH    = (MISSQ_DEPTH <= 1) ? 1 : $clog2(MISSQ_DEPTH);
    localparam int WAITER_COUNT_W = $clog2(MAX_WAITERS + 1);

    typedef struct packed {
        logic [LINE_ADDR_WIDTH-1:0] line_addr;
        logic [SET_INDEX_W-1:0]     set_id;
        logic [WORD_OFFSET_W-1:0]   word_id;
        logic [TAG_WIDTH-1:0]       tag;
        logic [WAY_INDEX_W-1:0]     way;
    } rs_issue_entry_t;

    rs_issue_entry_t rs_issue_entry;

    // Entry 18: at issue the RS hands over only victim METADATA plus the
    // vbuf slot the victim line lives in. The line itself stays in the
    // RS and is read back one word per granted writeback beat through
    // the wb_* port below. (This replaced Entry 15/17's per-entry
    // 155-bit read copies - the copies' routes owned WNS and the pins
    // needed to keep them real cost more than they saved.)
    logic                             rs_issue_victim_dirty;
    logic [TAG_WIDTH-1:0]             rs_issue_victim_tag;
    logic [LINE_WIDTH/DATA_WIDTH-1:0] rs_issue_victim_word_valid;
    logic [RS_ID_WIDTH-1:0]           rs_issue_victim_slot;

    // Entry 18 writeback read plumbing. One shared port is enough
    // because the request arbiter grants at most one memory beat per
    // cycle: whichever entry it grants, that entry's {slot, word}
    // coordinates are muxed into the RS (an AND-OR over the grant
    // one-hot), the vbuf answers combinationally, and the word becomes
    // the memory write data for the SAME beat. The chain is
    //   grant -> 5-bit mux -> LUTRAM read -> mem_req_wdata
    // and it lives entirely on the memory-port side, which no measured
    // census has ever put near the critical path. There is no
    // combinational loop: the arbiter's grant depends on req_valid and
    // its ordering FIFO, never on write data.
    logic [RS_ID_WIDTH-1:0]   entry_wb_slot [MSHR_COUNT];
    logic [WORD_OFFSET_W-1:0] entry_wb_word [MSHR_COUNT];
    logic [WORD_OFFSET_W-1:0] entry_wb_word_n [MSHR_COUNT];  // Entry 27b
    logic [RS_ID_WIDTH-1:0]   wb_slot_sel;
    logic [WORD_OFFSET_W-1:0] wb_word_sel;
    logic                     wb_active;
    logic [DATA_WIDTH-1:0]    vbuf_wb_data;

    logic rs_issue_valid;
    logic rs_issue_accept;
    logic [RS_ID_WIDTH-1:0] rs_issue_id;

    logic rs_retire_valid;
    logic [MSHR_ID_WIDTH-1:0] rs_retire_mshr_id;

    logic dispatch_valid;
    logic [WAITER_COUNT_W-1:0] dispatch_cpu_id_count;
    logic [CPU_ID_WIDTH-1:0]   dispatch_cpu_ids  [MAX_WAITERS];
    logic [WORD_OFFSET_W-1:0]  dispatch_word_ids [MAX_WAITERS];

    logic [MSHR_COUNT-1:0] entry_valid;
    logic [MSHR_COUNT-1:0] entry_issue_pending;
    logic [MSHR_COUNT-1:0] entry_refill_wen;

    logic [LINE_ADDR_WIDTH-1:0] entry_line_addr [MSHR_COUNT];
    logic [SET_INDEX_W-1:0]     entry_set_id    [MSHR_COUNT];
    logic [WORD_OFFSET_W-1:0]   entry_word_id   [MSHR_COUNT];
    logic [TAG_WIDTH-1:0]       entry_tag       [MSHR_COUNT];
    logic [WAY_INDEX_W-1:0]     entry_way       [MSHR_COUNT];

    logic [LINE_WIDTH-1:0]      entry_fill_line [MSHR_COUNT];

    logic [MSHR_COUNT-1:0]      mshr_resp_valid;
    logic [DATA_WIDTH-1:0]      mshr_resp_data;
    logic [MSHR_ID_WIDTH-1:0]   entry_alloc_idx;

    logic entry_alloc_ready;
    logic entry_alloc_fire;

    logic retire_sel_valid;
    logic [MSHR_ID_WIDTH-1:0] retire_sel_idx;
    // Entry 30(a): the registered retire broadcast (see the retire
    // section below for the full story).
    logic                     retire_valid_r;
    logic [MSHR_ID_WIDTH-1:0] retire_idx_r;

    // ============================================================
    // Reservation Station
    // ============================================================

    Reservation_Station #(
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
        .SET_INDEX_W    (SET_INDEX_W),
        .WORD_OFFSET_W  (WORD_OFFSET_W),
        .TAG_WIDTH      (TAG_WIDTH),
        .WAY_INDEX_W    (WAY_INDEX_W),
        .DATA_WIDTH     (DATA_WIDTH),
        .LINE_WIDTH     (LINE_WIDTH),
        .CPU_ID_WIDTH   (CPU_ID_WIDTH),
        .MSHR_ID_WIDTH  (MSHR_ID_WIDTH),
        .RS_DEPTH       (MISSQ_DEPTH),
        .MSHR_AF        (MSHR_AF),
        .MAX_WAITERS    (MAX_WAITERS)
    ) RES_STATION (
        .clk                (clk),
        .rst                (rst),

        .alloc_valid        (alloc_valid),
        .alloc_ready        (alloc_ready),

        .alloc_line_addr    (alloc_line_addr),
        .pre_line_addr      (pre_line_addr),
        .alloc_word_id      (alloc_word_id),
        .alloc_way          (alloc_way),
        .alloc_write        (alloc_write),
        .alloc_wdata        (alloc_wdata),
        .alloc_cpu_req_id   (alloc_cpu_req_id),

        .alloc_victim_dirty (alloc_victim_dirty),
        .alloc_victim_tag   (alloc_victim_tag),
        .alloc_victim_line  (alloc_victim_line),
        .alloc_victim_word_valid (alloc_victim_word_valid),

        .issue_valid        (rs_issue_valid),
        .issue_accept       (rs_issue_accept),
        .issue_mshr_id      (entry_alloc_idx),

        .issue_rs_id        (rs_issue_id),
        .issue_line_addr    (rs_issue_entry.line_addr),
        .issue_set_id       (rs_issue_entry.set_id),
        .issue_tag          (rs_issue_entry.tag),
        .issue_way          (rs_issue_entry.way),

   
        .issue_word_id      (rs_issue_entry.word_id),

        .issue_victim_dirty (rs_issue_victim_dirty),
        .issue_victim_tag   (rs_issue_victim_tag),
        .issue_victim_word_valid (rs_issue_victim_word_valid),
        .issue_victim_slot  (rs_issue_victim_slot),

        .wb_active          (wb_active),
        .wb_slot            (wb_slot_sel),
        .wb_word            (wb_word_sel),
        .wb_victim_word     (vbuf_wb_data),

        .retire_valid       (rs_retire_valid),
        .retire_mshr_id     (rs_retire_mshr_id),
        // Entry 30(b): the pre-registered retire (Entry 30(a)'s D) -
        // lets the RS's registered merge decision pre-shift for the
        // retire that will fire alongside its consumption.
        .retire_valid_next  (retire_sel_valid),

        .dispatch_valid        (dispatch_valid),
        .dispatch_cpu_id_count (dispatch_cpu_id_count),
        .dispatch_cpu_ids      (dispatch_cpu_ids),
        .dispatch_word_ids     (dispatch_word_ids)
    );

    // ============================================================
    // Dispacher
    // ============================================================

    Dispacher #(
        .DATA_WIDTH   (DATA_WIDTH),
        .CPU_ID_WIDTH (CPU_ID_WIDTH),
        .WORD_OFFSET_W(WORD_OFFSET_W),
        .MAX_WAITERS  (MAX_WAITERS)
    ) MISS_DISPACHER (
        .clk                  (clk),
        .rst                  (rst),

        .delayed_miss_data    (delayed_miss_data),

        .dispatch_valid       (dispatch_valid),
        // Entry 30(a): read at the REGISTERED index - the entry's
        // registers still hold this request (retire_hold_r).
        .dispatch_critical_word(entry_word_id[retire_idx_r]),
        .dispatch_cpu_id_count(dispatch_cpu_id_count),
        .dispatch_cpu_ids     (dispatch_cpu_ids),
        .dispatch_word_ids    (dispatch_word_ids),

        .miss_valid           (miss_valid),
        .miss_data            (miss_data),
        .miss_id              (miss_id)
    );

    // ============================================================
    // Free MSHR select
    // ============================================================

    always_comb begin
        entry_alloc_ready = 1'b0;
        entry_alloc_idx   = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (!entry_valid[i] && !entry_alloc_ready) begin
                entry_alloc_ready = 1'b1;
                entry_alloc_idx   = i[MSHR_ID_WIDTH-1:0];
            end
        end
    end

    assign entry_alloc_fire = rs_issue_valid && entry_alloc_ready;
    assign rs_issue_accept  = entry_alloc_fire;


    // ============================================================
    // Completed MSHR select for response dispatch.
    // Match MSHR_Mux priority so refill and CPU response retire
    // consume the same completed entry if completions overlap.
    // ============================================================

    always_comb begin
        retire_sel_valid = 1'b0;
        retire_sel_idx   = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (entry_refill_wen[i] && !retire_sel_valid) begin
                retire_sel_valid = 1'b1;
                retire_sel_idx   = i[MSHR_ID_WIDTH-1:0];
            end
        end
    end

    // ============================================================
    // Entry 30(a): the retire broadcast is REGISTERED.
    //
    // retire_sel_* is a priority resolve over the entries' refill
    // pulses, and everything it used to drive combinationally is WIDE:
    // the RS shift-down muxes into 8 x 155-bit rs entries, the waiter
    // dispatch, the vbuf head advance, plus the Dispacher's critical
    // word - 245 of the top-400 paths of the -729 baseline census
    // rooted in refill_wen_r / the merge dups (2026-08-24). One
    // register here lets all of that launch from a clean flop.
    //
    // Latency: the RS retire and the CPU miss responses land one cycle
    // later. Delay_r in Cache.sv goes 5 -> 6 to keep the delayed
    // memory data aligned with the cycle the Dispacher now sees the
    // retire (re-derived for this entry; regression is the proof).
    // The ARRAY refill is deliberately NOT moved - MSHR_Mux still
    // writes on the pulse cycle - so the refill/retire priority mirror
    // holds with the retire side exactly one cycle behind.
    //
    // Consistency: an entry stays busy through the retire cycle
    // (retire_hold_r in MSHR_Entry), so it cannot be re-allocated
    // while its retire - and the entry_word_id read below - is in
    // flight. RS credit sees the retiring entry one cycle longer:
    // alloc_ready is conservative by one cycle, never optimistic.
    //
    // Reset: NONE, as of Entry 29(e) (2026-08-25). retire_sel_valid is a
    // priority-OR of the entries' refill_wen_r, every one of which keeps
    // its reset, so retire_valid_r is a defined 0 from the second reset
    // edge - the same derivation E29(d) used for MSHR_Mux.refill_wen.
    // The index is payload and free-runs, consumed only under
    // retire_valid_r. (Declarations live up with retire_sel_* - the
    // Dispacher instance reads retire_idx_r above this point.)
    // ============================================================
    always_ff @(posedge clk) begin
        retire_valid_r <= retire_sel_valid;
        retire_idx_r   <= retire_sel_idx;
    end

    assign rs_retire_valid   = retire_valid_r;
    assign rs_retire_mshr_id = retire_idx_r;

`ifndef SYNTHESIS
    // Entry 30(a) invariant: the entry a registered retire points at
    // must still be holding its request state (retire_hold_r keeps it
    // valid). If this fires, the busy extension is broken and the
    // Dispacher may read a re-allocated entry's critical word.
    always_ff @(posedge clk) begin
        if (!rst && retire_valid_r) begin
            assert (entry_valid[retire_idx_r])
                else $error("MSHR E30a: retire in flight for entry %0d but it is no longer valid",
                            retire_idx_r);
        end
    end
`endif

    // ============================================================
    // Memory response demux
    // ============================================================

    MSHR_Response_DeMux #(
        .MSHR_COUNT   (MSHR_COUNT),
        .DATA_WIDTH   (DATA_WIDTH),
        .MSHR_ID_WIDTH(MSHR_ID_WIDTH)
    ) RESP_DEMUX (
        .clk            (clk),
        .rst            (rst),
        .mem_resp_valid (mem_resp_valid),
        .mem_resp_id    (mem_resp_id),
        .mem_resp_rdata (mem_resp_rdata),
        .mshr_resp_valid(mshr_resp_valid),
        .mshr_resp_data (mshr_resp_data)
    );

    // ============================================================
    // Refill mux
    // Refill path is independent from RS/Dispacher response path.
    // ============================================================

    MSHR_Mux #(
        .MSHR_COUNT (MSHR_COUNT),
        .SET_INDEX_W(SET_INDEX_W),
        .TAG_WIDTH  (TAG_WIDTH),
        .WAY_INDEX_W(WAY_INDEX_W),
        .LINE_WIDTH (LINE_WIDTH)
    ) REFILL_MUX (
        .clk                   (clk),
        .rst                   (rst),
        .entry_refill_wen      (entry_refill_wen),
        .entry_set_id          (entry_set_id),
        .entry_tag             (entry_tag),
        .entry_way             (entry_way),
        .entry_fill_line       (entry_fill_line),
        .refill_wen            (refill_wen),
        .refill_set_id         (refill_set_id),
        .refill_tag            (refill_tag),
        .refill_way            (refill_way),
        .refill_line           (refill_line)
    );

    // ============================================================
    // Status outputs
    // ============================================================

    assign issue_pending = entry_issue_pending;

    // ============================================================
    // Entry 18 / Entry 23: victim writeback data, read for the HEAD
    //
    // Entry 18 read the vbuf at the GRANTED entry's {slot, word}: an
    // AND-OR over the arbiter's issue_done one-hot. That one-hot carries
    // found_req = order_count != 0 && req_pending[head] && req_valid[head],
    // and req_valid reaches into each entry's FSM state and beat-skip
    // mask - four LUT levels in front of the RAM address on FPGA, the
    // 32-path `order_head_r -> mem_req_wdata` class on ASIC.
    //
    // Entry 23: the arbiter only ever grants the order-HEAD entry, so on
    // every cycle a write beat issues, the granted entry IS head_idx.
    // Read the vbuf at the head's coordinates - two 4:1 muxes of
    // registers - and let the grant drop out of the data path. Cycles
    // without a grant read a don't-care (no beat; RAM_ID consumes wdata
    // only on valid && write). One word leaves on wb_data; the arbiter
    // no longer muxes four identical lanes. Same value on every cycle
    // that matters: bit-identical by construction.
    // ============================================================

    // Entry 27b STRUCK FOR GOOD 2026-08-24 (both revisions measured):
    //   rev 1 (word pre-read at next-cycle coords): -2377 - the address
    //     serialized arbiter pop/insert + FSM-counter-D (grant reach) +
    //     the full vbuf mux into one cycle.
    //   rev 2 (full-LINE pre-read at next head's slot, word select next
    //     cycle): -1614 - no grant reach, no word mux, and STILL the
    //     design wall: the head_idx_n front (order_head_r 800 ps CLK->Q
    //     + pop compare + insert + order_q_n mux) plus the 8:1 x 128b
    //     line read does not fit either.
    // Meanwhile the plain Entry 23 read below closed at -729 in the
    // same stack (run 20260824_091117). The pre-read idea is dead:
    // nothing useful fits behind head_idx_n in one cycle. head_idx_n
    // itself is GONE as of Entry 31 - the one-hot queue has no
    // next-state form to export. entry_wb_word_n / MSHR_Entry.wb_word_n
    // remain as unloaded 27b residue, to be swept separately.
    // Entry 31: entry_wb_slot[head_idx] / entry_wb_word[head_idx] were
    // the second of the three serial indirections on the -911 cone -
    // a 4:1 mux whose select was itself muxed out of order_q one level
    // up. With the head arriving pre-decoded these are AND-OR reduces
    // straight off flops.
    //
    // Accumulate discipline (the Entry 30(b) trap): initialise, then
    // |= in order; each read sees only what this activation wrote.
    //
    // head_oh is all-zero on an empty queue, which reads 0 on both -
    // a defined don't-care. The encoded form used to read a stale
    // index instead. Neither is consumed: a beat only leaves on a
    // grant (see wb_active below), and RAM_ID consumes wdata only on
    // valid && write.
    always_comb begin
        wb_slot_sel = '0;
        wb_word_sel = '0;
        for (int i = 0; i < MSHR_COUNT; i++) begin
            wb_slot_sel |= entry_wb_slot[i] & {RS_ID_WIDTH{head_oh[i]}};
            wb_word_sel |= entry_wb_word[i] & {WORD_OFFSET_W{head_oh[i]}};
        end
    end

    // A grant for a WRITE beat is the only cycle the read matters -
    // this arms the RS-side slot-liveness assertion (sim-only there).
    // Still keyed on the GRANT, not the head: it must fire exactly when
    // a beat is issued.
    assign wb_active = |(issue_done & req_write);

    assign wb_data = vbuf_wb_data;   // Entry 23 read (27b struck)

    // ============================================================
    // MSHR entries
    // ============================================================

    genvar i;

    generate
        for (i = 0; i < MSHR_COUNT; i++) begin : GEN_MSHR_ENTRIES

            MSHR_Entry #(
                .ADDR_WIDTH      (ADDR_WIDTH),
                .LINE_ADDR_WIDTH (LINE_ADDR_WIDTH),
                .SET_INDEX_W     (SET_INDEX_W),
                .WORD_OFFSET_W   (WORD_OFFSET_W),
                .TAG_WIDTH       (TAG_WIDTH),
                .WAY_INDEX_W     (WAY_INDEX_W),
                .DATA_WIDTH      (DATA_WIDTH),
                .LINE_WIDTH      (LINE_WIDTH),
                .MSHR_ID_WIDTH   (MSHR_ID_WIDTH),
                .ENTRY_ID        (i),
                .VBUF_SLOT_W     (RS_ID_WIDTH)
            ) ENTRY (
                .clk                (clk),
                .rst                (rst),

                .alloc              (entry_alloc_fire && (entry_alloc_idx == i[MSHR_ID_WIDTH-1:0])),

                .alloc_line_addr    (rs_issue_entry.line_addr),
                .alloc_set_id       (rs_issue_entry.set_id),
                .alloc_word_id      (rs_issue_entry.word_id),
                .alloc_tag          (rs_issue_entry.tag),
                .alloc_way          (rs_issue_entry.way),

                .alloc_victim_dirty (rs_issue_victim_dirty),
                .alloc_victim_tag   (rs_issue_victim_tag),
                .alloc_victim_slot  (rs_issue_victim_slot),
                .alloc_victim_word_valid (rs_issue_victim_word_valid),

                .issue_done         (issue_done[i]),

                .resp_valid         (mshr_resp_valid[i]),
                .resp_data          (mshr_resp_data),

                .valid              (entry_valid[i]),
                .issue_pending      (entry_issue_pending[i]),

                .req_valid          (req_valid[i]),
                .req_write          (req_write[i]),
                .req_addr           (req_addr[i]),
                .req_mshr_id        (req_id[i]),

                .wb_slot            (entry_wb_slot[i]),
                .wb_word            (entry_wb_word[i]),
                .wb_word_n          (entry_wb_word_n[i]),

                .line_addr          (entry_line_addr[i]),
                .set_id             (entry_set_id[i]),
                .word_id            (entry_word_id[i]),
                .tag                (entry_tag[i]),
                .way                (entry_way[i]),

                .refill_wen         (entry_refill_wen[i]),
                .fill_line          (entry_fill_line[i])
            );

        end
    endgenerate

endmodule
