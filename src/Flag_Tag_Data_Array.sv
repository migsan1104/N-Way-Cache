// ============================================================
// Flag_Tag_Data_Array
//
// Three memories, each in its natural implementation (Entry 5):
//
//   FLAG memory  (allocated/dirty/word_valid) - FLOPS, permanently.
//     2R3W with bit-granular updates and same-edge priorities; no RAM
//     primitive has this port profile, and it feeds the S1 compare cone.
//
//   TAG memory   (tag_mem) - FLOPS at this size.
//     2R1W (pipeline read + refill-guard read), 800b/way, head of the
//     tag-compare critical cone: flop access wins. Revisit if
//     CACHE_BYTES scales ~8x.
//
//   DATA memory  (one bank per line word) - RAM-SHAPED (Entry 5).
//     Each bank is a true 1R1W simple-dual-port memory: one sync read
//     at raddr every cycle, ONE write port muxed CPU-vs-refill. Coded
//     as the canonical inference template so Vivado maps it to
//     LUTRAM/BRAM instead of ~33k flops with a CE fanout tree (the
//     out_tag -> data_bank CE population, ~95% of the FPGA worst-1000).
//
// The single write port is possible because the refill DRAINS instead
// of bursting (extends Entry 4's registered decision):
//   - CPU writes have absolute priority on a bank's port (they cannot
//     stall); the refill writes every other still-pending bank.
//   - A CPU write to the refill's set+word clears that pending bit
//     without writing (the word is now valid with newer data).
//   - An alloc to the refill's set kills all pending (line renamed).
//   - A new refill overwrites old pending state; abandoned words simply
//     stay word_valid=0 and re-fetch on a later miss. Sub-line valid
//     makes a PARTIAL refill architecturally legal - this is what lets
//     the drain be abandoned instead of ever stalling anything.
//   - word_valid is set per bank AS IT DRAINS, never wholesale.
//
// Read-during-write notes (safe by construction):
//   - Read vs CPU write, same set: handled by the EXTERNAL forward
//     (fwd_*_r) muxed over the RAM output - the RAM itself needs no
//     internal bypass, which is what makes it inferable.
//   - Read vs refill drain, same set: the reader's word_valid (flops,
//     same-edge) still shows the draining words invalid, and every
//     consumer of rline words (hit data, victim writeback) is gated by
//     word_valid - so a stale/undefined collision word is never used.
// ============================================================

module Flag_Tag_Data_Array #(
    parameter int DATA_WIDTH     = 32,
    parameter int LINE_WIDTH     = 128,
    parameter int TAG_WIDTH      = 24,
    parameter int DEPTH          = 16,
    parameter int SET_INDEX_W    = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int WORDS_PER_LINE = LINE_WIDTH / DATA_WIDTH,
    parameter int WORD_OFFSET_W  =
        (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE)
)(
    input  logic                      clk,
    input  logic                      rst,

    input  logic [SET_INDEX_W-1:0]    raddr,

    output logic [LINE_WIDTH-1:0]     rline,
    output logic [TAG_WIDTH-1:0]      rtag,
    output logic                      allocated,
    output logic                      dirty,
    output logic [WORDS_PER_LINE-1:0] word_valid,

    input  logic                      refill_wen,
    input  logic [SET_INDEX_W-1:0]    refill_waddr,
    input  logic [TAG_WIDTH-1:0]      refill_tag,
    input  logic [LINE_WIDTH-1:0]     refill_line,

    input  logic                      alloc_wen,
    input  logic [SET_INDEX_W-1:0]    alloc_waddr,
    input  logic [TAG_WIDTH-1:0]      alloc_tag,

    input  logic                      cpu_word_wen,
    input  logic [SET_INDEX_W-1:0]    cpu_waddr,
    input  logic [WORD_OFFSET_W-1:0]  cpu_word_id,
    input  logic [DATA_WIDTH-1:0]     cpu_wdata
);

    // ---- Metadata (flops) --------------------------------------------
    logic [TAG_WIDTH-1:0]      tag_mem        [0:DEPTH-1];
    logic                      allocated_mem  [0:DEPTH-1];
    logic                      dirty_mem      [0:DEPTH-1];
    logic [WORDS_PER_LINE-1:0] word_valid_mem [0:DEPTH-1];

    // ---- Refill drain state (extends Entry 4's registered decision) --
    // Binary set index now - the RAM write port takes a binary address,
    // so Entry 4's one-hot decode is no longer needed anywhere.
    logic [SET_INDEX_W-1:0]    refill_set_idx_r;
    logic [WORDS_PER_LINE-1:0] refill_bank_pending_r;
    logic [LINE_WIDTH-1:0]     refill_line_r;

    logic                      refill_guard_ok_c;
    logic [WORDS_PER_LINE-1:0] refill_words_valid_c;
    logic [WORDS_PER_LINE-1:0] refill_grant_c;
    logic [WORDS_PER_LINE-1:0] refill_pending_next_c;

    // Cycle-R guard: tag check + same-edge-alloc kill (Entry 4).
    assign refill_guard_ok_c =
        refill_wen &&
        (refill_tag == tag_mem[refill_waddr]) &&
        !(alloc_wen && (alloc_waddr == refill_waddr));

    // Words already valid, including a CPU write landing this edge
    // (Entry 4's blind-spot fold).
    assign refill_words_valid_c =
        word_valid_mem[refill_waddr] |
        ((cpu_word_wen && (cpu_waddr == refill_waddr))
             ? (WORDS_PER_LINE'(1'b1) << cpu_word_id)
             : '0);

    // Per-bank port grant: the CPU owns a bank's single write port the
    // cycle it writes that word - regardless of address. The refill
    // drains every other pending bank.
    always_comb begin
        for (int w = 0; w < WORDS_PER_LINE; w++) begin
            refill_grant_c[w] =
                refill_bank_pending_r[w] &&
                !(cpu_word_wen && (cpu_word_id == WORD_OFFSET_W'(w)));
        end
    end

    // Pending next-state during a drain:
    //   - drained banks clear;
    //   - a CPU write to the refill set clears ITS word (newer data -
    //     the refill must never overwrite it);
    //   - an alloc to the refill set kills everything (line renamed).
    always_comb begin
        refill_pending_next_c = refill_bank_pending_r & ~refill_grant_c;

        if (cpu_word_wen && (cpu_waddr == refill_set_idx_r)) begin
            refill_pending_next_c[cpu_word_id] = 1'b0;
        end

        if (alloc_wen && (alloc_waddr == refill_set_idx_r)) begin
            refill_pending_next_c = '0;
        end
    end

    // line/idx are pure capture registers - only pending decides whether
    // anything drains - so they load on RAW refill_wen (shallow MSHR cone),
    // keeping the S3 compare cone (alloc_wen inside refill_guard_ok_c) off
    // their wide clock enable. The guard survives only in pending's D.
    // Coupling: a failed-guard refill must ZERO pending, else stale pending
    // bits would drain the newly captured line at the new index. Any
    // abandoned words stay word_valid=0 and re-fetch on a later miss.
    always_ff @(posedge clk) begin
        if (rst) begin
            refill_bank_pending_r <= '0;
        end
        else if (refill_wen) begin
            refill_set_idx_r      <= refill_waddr;
            refill_line_r         <= refill_line;
            refill_bank_pending_r <=
                refill_guard_ok_c ? ~refill_words_valid_c : '0;
        end
        else begin
            refill_bank_pending_r <= refill_pending_next_c;
        end
    end

    // ---- Data memory: one 1R1W RAM per line word ---------------------
    // Canonical simple-dual-port template: one write port (muxed
    // CPU-vs-refill), one sync read, no other drivers, no reset, no
    // internal bypass. Vivado infers LUTRAM ("distributed" is right at
    // DEPTH 32-256; switch to "block" if CACHE_BYTES scales).
    logic [LINE_WIDTH-1:0] rline_raw;

    generate
        for (genvar gw = 0; gw < WORDS_PER_LINE; gw++) begin : g_bank

            (* ram_style = "distributed" *)
            logic [DATA_WIDTH-1:0] bank [0:DEPTH-1];

            logic                   cpu_owns_c;
            logic                   bank_wen_c;
            logic [SET_INDEX_W-1:0] bank_waddr_c;
            logic [DATA_WIDTH-1:0]  bank_wdata_c;

            assign cpu_owns_c =
                cpu_word_wen && (cpu_word_id == WORD_OFFSET_W'(gw));

            assign bank_wen_c   = cpu_owns_c || refill_grant_c[gw];
            assign bank_waddr_c = cpu_owns_c ? cpu_waddr : refill_set_idx_r;
            assign bank_wdata_c =
                cpu_owns_c ? cpu_wdata
                           : refill_line_r[gw*DATA_WIDTH +: DATA_WIDTH];

            always_ff @(posedge clk) begin
                if (bank_wen_c) begin
                    bank[bank_waddr_c] <= bank_wdata_c;
                end

                rline_raw[gw*DATA_WIDTH +: DATA_WIDTH] <= bank[raddr];
            end

        end
    endgenerate

    // ---- External read-after-CPU-write forward -----------------------
    // Replaces the in-array rline bypass: the same-edge CPU write is
    // captured at the write edge and muxed over the RAM's read output.
    // Select is registered (computed from S0-stable addresses), so this
    // adds one mux level with an early select to the S1 input.
    logic                     fwd_hit_r;
    logic [WORD_OFFSET_W-1:0] fwd_word_r;
    logic [DATA_WIDTH-1:0]    fwd_data_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            fwd_hit_r <= 1'b0;
        end
        else begin
            fwd_hit_r  <= cpu_word_wen && (cpu_waddr == raddr);
            fwd_word_r <= cpu_word_id;
            fwd_data_r <= cpu_wdata;
        end
    end

    always_comb begin
        rline = rline_raw;

        if (fwd_hit_r) begin
            rline[fwd_word_r*DATA_WIDTH +: DATA_WIDTH] = fwd_data_r;
        end
    end

    // ---- Flag + tag memory (flops) -----------------------------------
    // NOTE: statement order is load-bearing (NBA, later wins):
    // refill drain < alloc < CPU write < read bypasses.
    always_ff @(posedge clk) begin
        if (rst) begin
            allocated  <= 1'b0;
            dirty      <= 1'b0;
            word_valid <= '0;

            for (int i = 0; i < DEPTH; i++) begin
                allocated_mem[i]  <= 1'b0;
                dirty_mem[i]      <= 1'b0;
                word_valid_mem[i] <= '0;
            end
        end
        else begin
            rtag       <= tag_mem[raddr];
            allocated  <= allocated_mem[raddr];
            dirty      <= dirty_mem[raddr];
            word_valid <= word_valid_mem[raddr];

            // Refill drain: mark each word valid AS its bank is written.
            // An alloc to this set later in the block re-clears these -
            // a refill landing on a just-renamed line stays invisible.
            for (int w = 0; w < WORDS_PER_LINE; w++) begin
                if (refill_grant_c[w]) begin
                    word_valid_mem[refill_set_idx_r][w] <= 1'b1;
                end
            end

            // Allocate a new line.
            if (alloc_wen) begin
                allocated_mem[alloc_waddr]  <= 1'b1;
                dirty_mem[alloc_waddr]      <= 1'b0;
                word_valid_mem[alloc_waddr] <= '0;
                tag_mem[alloc_waddr]        <= alloc_tag;
            end

            // CPU write: flag side (data went through the bank port).
            if (cpu_word_wen) begin
                dirty_mem[cpu_waddr] <= 1'b1;
                word_valid_mem[cpu_waddr][cpu_word_id]
                    <= 1'b1;
            end

            // Read-after-allocation bypass (tag/flags only).
            if (alloc_wen && (alloc_waddr == raddr)) begin
                allocated  <= 1'b1;
                dirty      <= 1'b0;
                word_valid <= '0;
                rtag       <= alloc_tag;
            end

            // Read-after-CPU-write bypass, flag side (the data side is
            // the external fwd_* forward above).
            if (cpu_word_wen && (cpu_waddr == raddr)) begin
                word_valid[cpu_word_id] <= 1'b1;
                dirty                   <= 1'b1;
            end
        end
    end

endmodule
