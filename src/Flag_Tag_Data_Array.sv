// ============================================================
// Flag_Tag_Data_Array
//
// Three memories, each in its natural implementation (Entry 5):
//
//   FLAG memory  (allocated/dirty/word_valid) - FLOPS, permanently.
//     2R3W with bit-granular updates and same-edge priorities; no RAM
//     primitive has this port profile, and it feeds the S1 compare cone.
//
//   TAG memory   (tag_bank) - LUTRAM, EXPLICITLY BANKED 64 deep
//     (Entry 16). 2R1W (pipeline read + refill-guard read). At 16KB
//     depths Vivado was already banking the inferred array into
//     64-deep RAMD64Es; writing the banks down in RTL is what lets the
//     S0 compare run per bank BEFORE the bank mux (see the S0 tap).
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
// Entry 21 (TAG_READ_ONEHOT, ASIC-only generate fork): the metadata
// READ has two shapes.
//   =0 (FPGA + default): the historical form. S0 muxes the tag bank
//      (BANK_DEPTH:1) and the flat flag arrays (DEPTH:1) at raddr and
//      REGISTERS the result into S1; same-edge writes are patched in
//      by explicit bypasses. The mux depth is the S0 cone Genus
//      measured at ~2.6 ns of the 4.09 ns tag read (64:1, ASIC A4).
//   =1 (ASIC): S0 registers nothing but a ONE-HOT of raddr (decoded
//      once in Cache, SHARED by all ways - the tagbank16 probe showed
//      mux depth, not address fanout, dominates, so per-way copies buy
//      nothing). S1 reads the arrays LIVE through a flat AND-OR
//      against that registered one-hot. The read registers and their
//      same-edge bypasses DISAPPEAR: a write landing on the S0->S1
//      edge is simply array state by the time S1 reads it. Writes
//      landing on the S1->S2 edge stay invisible under NBA semantics -
//      identical visibility to the registered form, so CSR's Entry 20
//      elder patch is untouched.
//      ONE deliberate exception: a refill-drain write landing on the
//      S0->S1 edge. The registered form MISSES it (word_valid read is
//      pre-edge) and that miss is load-bearing: the data-side read
//      (rline_raw) is also pre-edge, so showing the word valid would
//      hit on stale data. The live read WOULD see it, so the one-hot
//      branch carries wv_drain_hide_r - a one-cycle mask of the words
//      drained into the read set on the capture edge - to reproduce
//      the registered form's conservative view exactly. (The CPU-write
//      same-edge case needs no such mask: its data side is covered by
//      the fwd_* forward, so the live-visible flag is backed by
//      forwarded data, same as the old explicit flag bypass.)
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
        (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE),
    parameter bit EN_SRAM_MACRO  = 1'b0,
    // Entry 21: 1 = live AND-OR metadata read against raddr_onehot
    // (ASIC form); 0 = registered mux read at raddr (FPGA form).
    parameter bit TAG_READ_ONEHOT = 1'b0
)(
    input  logic                      clk,
    input  logic                      rst,

    input  logic [SET_INDEX_W-1:0]    raddr,
    // Registered one-hot of the PREVIOUS cycle's raddr (S1-aligned),
    // decoded once in Cache and shared by all ways. Consumed only when
    // TAG_READ_ONEHOT=1; tie to '0 otherwise.
    input  logic [DEPTH-1:0]          raddr_onehot,

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

    // ---- Metadata ----------------------------------------------------
    // Tags are explicitly banked 64 deep (Entry 16) - the RAMD64E
    // geometry Vivado banks by anyway. Flags stay flat (1-4 bits wide;
    // their read muxes are not on the measured cone).
    // Tag bank depth. 64 is the measured sweet spot on FPGA (Entry 16); the
    // `define exists so an ASIC run can probe other depths without an RTL
    // edit (asic: ASIC_HDL_DEFINES="TAG_BANK_DEPTH=16" ./run_genus.sh 4).
    // Deeper banks = fewer, wider muxes; shallower = more parallel compares
    // and a wider final 1-bit select.
`ifndef TAG_BANK_DEPTH
`define TAG_BANK_DEPTH 64
`endif
    localparam int BANK_DEPTH  = (DEPTH < `TAG_BANK_DEPTH) ? DEPTH : `TAG_BANK_DEPTH;
    localparam int TAG_NBANKS  = DEPTH / BANK_DEPTH;
    localparam int BANK_ADDR_W = (BANK_DEPTH <= 1) ? 1 : $clog2(BANK_DEPTH);
    localparam int BANK_SEL_W  = (TAG_NBANKS <= 1) ? 1 : $clog2(TAG_NBANKS);

    logic                      allocated_mem  [0:DEPTH-1];
    logic                      dirty_mem      [0:DEPTH-1];
    logic [WORDS_PER_LINE-1:0] word_valid_mem [0:DEPTH-1];

    // Bank-select slices of the three addresses that touch tags. These
    // are raw address MSBs through zero logic - ready at cycle start,
    // which is exactly what lets the S0 select below come LAST.
    logic [BANK_SEL_W-1:0] r_bank_sel_c;
    logic [BANK_SEL_W-1:0] alloc_bank_sel_c;
    logic [BANK_SEL_W-1:0] refill_bank_sel_c;

    generate
        if (TAG_NBANKS == 1) begin : g_tag_one_bank
            assign r_bank_sel_c      = '0;
            assign alloc_bank_sel_c  = '0;
            assign refill_bank_sel_c = '0;
        end
        else begin : g_tag_bank_sel
            assign r_bank_sel_c      = raddr[SET_INDEX_W-1:BANK_ADDR_W];
            assign alloc_bank_sel_c  = alloc_waddr[SET_INDEX_W-1:BANK_ADDR_W];
            assign refill_bank_sel_c = refill_waddr[SET_INDEX_W-1:BANK_ADDR_W];
        end
    endgenerate

    // ---- Tag read ----------------------------------------------------
    // Entry 20 retired the S0 write-grant taps (Entry 10/16): the tag
    // compare now happens ONLY in S1, in Compare_Select_Replace, on the
    // registered rtag. The array's job in S0 is the read and nothing
    // else - the shape a synchronous-read macro drops into (E24).
    // Captured refill set index (E22) - declared early: the tag banks'
    // sim-only live read below indexes it.
    logic [SET_INDEX_W-1:0]    refill_set_idx_r;

`ifndef SYNTHESIS
    // E22 assertion helpers: the LIVE tag at the captured refill index.
    logic [TAG_WIDTH-1:0] bank_live_rtag_c [TAG_NBANKS];
    logic [TAG_WIDTH-1:0] bank_tags_live_c;
    logic [BANK_SEL_W-1:0] live_bank_sel_c;
    generate
        if (TAG_NBANKS == 1) begin : g_live_one
            assign live_bank_sel_c = '0;
        end
        else begin : g_live_sel
            assign live_bank_sel_c = refill_set_idx_r[SET_INDEX_W-1:BANK_ADDR_W];
        end
    endgenerate
    assign bank_tags_live_c = bank_live_rtag_c[live_bank_sel_c];
`endif

    // Per-bank read data, collected for the two whole-tag consumers
    // (the rtag pipeline read and the refill guard).
    logic [TAG_WIDTH-1:0] bank_rtag_c        [TAG_NBANKS];
    logic [TAG_WIDTH-1:0] bank_refill_rtag_c [TAG_NBANKS];
    // Entry 21: per-bank AND-OR read against the one-hot slice. Driven
    // only when TAG_READ_ONEHOT=1 (see g_onehot_rd inside the bank
    // loop); the one-hot is exclusive ACROSS banks too, so the final
    // rtag is a plain OR of these - no bank-select mux anywhere.
    logic [TAG_WIDTH-1:0] bank_onehot_rtag_c [TAG_NBANKS];

    // Each bank is its OWN 1-D array with a DECODED write enable - the
    // canonical single-write-port distributed-RAM template, per bank.
    // (Entry 16 attempt 1 used one 2-D array written through two
    // dynamic indices; that shape is outside Vivado's RAM-inference
    // pattern and the whole array fell back to FLOPS - tag_bank_reg
    // cells in the post-place netlist, ~22-24k of them. The bank-select
    // compare below is constant per instance and register-fed: it costs
    // nothing on any measured cone.)
    generate
        for (genvar gb = 0; gb < TAG_NBANKS; gb++) begin : g_tag_banks
            (* ram_style = "distributed" *)
            logic [TAG_WIDTH-1:0] bank_tags [0:BANK_DEPTH-1];

            logic bank_alloc_wen_c;

            assign bank_alloc_wen_c =
                alloc_wen && (alloc_bank_sel_c == BANK_SEL_W'(gb));

            always_ff @(posedge clk) begin
                if (bank_alloc_wen_c) begin
                    bank_tags[alloc_waddr[BANK_ADDR_W-1:0]] <= alloc_tag;
                end
            end

            assign bank_rtag_c[gb] =
                bank_tags[raddr[BANK_ADDR_W-1:0]];
            assign bank_refill_rtag_c[gb] =
                bank_tags[refill_waddr[BANK_ADDR_W-1:0]];

            // Entry 21: the one-hot read of this bank's slice. A flat
            // AND-OR over BANK_DEPTH entries - the mux this replaces is
            // the ~2.6 ns term of the ASIC tag read. Elaborated only in
            // the one-hot form so the FPGA branch keeps its clean
            // LUTRAM inference pattern.
            if (TAG_READ_ONEHOT) begin : g_onehot_rd
                always_comb begin
                    bank_onehot_rtag_c[gb] = '0;
                    for (int k = 0; k < BANK_DEPTH; k++) begin
                        if (raddr_onehot[gb*BANK_DEPTH + k]) begin
                            bank_onehot_rtag_c[gb] |= bank_tags[k];
                        end
                    end
                end
            end
`ifndef SYNTHESIS
            assign bank_live_rtag_c[gb] =
                bank_tags[refill_set_idx_r[BANK_ADDR_W-1:0]];
`endif

        end
    endgenerate

    // ---- Refill drain state (extends Entry 4's registered decision) --
    // Binary set index now - the RAM write port takes a binary address,
    // so Entry 4's one-hot decode is no longer needed anywhere.
    logic [WORDS_PER_LINE-1:0] refill_bank_pending_r;
    logic [LINE_WIDTH-1:0]     refill_line_r;


    // ---- Entry 22: the refill decision takes two cycles -------------
    // Cycle R (refill_wen): the MSHR_Mux register fans the set index to
    // every way, the tag bank answers through its 64:1 mux and the flat
    // word_valid array through a 256:1 one - and in Entry 4's form the
    // compare, the alloc-kill, the mask and pending's D all followed in
    // the same cycle: the WNS holder on FPGA A4 after Entry 20 (-1372,
    // 25 paths) and #2 on ASIC (-2252, 16 paths). Now cycle R only
    // CAPTURES: the raw tag and word_valid reads, the payload, and the
    // two race terms of THAT cycle (an alloc or a CPU write to the
    // refill set landing on the R edge). Cycle R+1 decides from
    // registers: compare, the two alloc-kill terms (captured R, live
    // R+1), the mask (captured read | captured R write | live R+1
    // write), and loads pending. The drain starts at R+2, one cycle
    // later than before - invisible to the Dispatcher, which serves
    // waiters from memory data, not the array.
    //
    // pending is ZEROED on the R edge. It must be: set_idx/line reload
    // there (as before), and a previous refill's drain still in flight
    // would otherwise write the NEW line through the OLD mask. That is
    // the same "abandon on new refill" rule Entry 5 established; the
    // abandoned words stay word_valid=0 and re-fetch later.
    //
    // Back-to-back refill_wen (R+1 while a decision is staged): the new
    // refill wins and the staged one is abandoned whole (all its words
    // stay word_valid=0). MSHR_Mux can only raise refill_wen once per 4
    // response beats per MSHR and the arbiter keeps each MSHR's beats
    // contiguous, so consecutive pulses should be >= 4 cycles apart -
    // asserted below, and counted, rather than assumed.
    logic                      refill_stage_v_r;     // decide this cycle
    logic [TAG_WIDTH-1:0]      refill_rd_tag_r;      // tag read at R
    logic [WORDS_PER_LINE-1:0] refill_rd_wv_r;       // word_valid read at R
    logic [TAG_WIDTH-1:0]      refill_stage_tag_r;   // refill_tag, held
    logic                      refill_alloc_hit_r;   // alloc to set at R
    logic [WORDS_PER_LINE-1:0] refill_cpu_word_r;    // CPU write to set at R

    logic                      refill_guard_ok_c;
    logic [WORDS_PER_LINE-1:0] refill_words_valid_c;
    logic [WORDS_PER_LINE-1:0] refill_grant_c;
    logic [WORDS_PER_LINE-1:0] refill_pending_next_c;

    // Cycle R+1 guard: captured tag vs held refill tag, alloc-kill over
    // both cycles (Entry 4's term, evaluated at R and again live at R+1
    // against the captured index).
    assign refill_guard_ok_c =
        (refill_stage_tag_r == refill_rd_tag_r);

    // Words already valid: the R read, plus a CPU write landing on the R
    // edge (captured), plus one landing on the R+1 edge (live) - Entry
    // 4's blind-spot fold, now over both cycles.
    assign refill_words_valid_c =
        refill_rd_wv_r | refill_cpu_word_r |
        ((cpu_word_wen && (cpu_waddr == refill_set_idx_r))
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
    // Entry 29(a): the capture registers carry NO reset
    // values, so they live in their own reset-free block - rst leaves
    // their load-enable cones entirely (the `rst -> refill_rd_*` class,
    // 13 paths at -1190..-1066 in the e26 census, existed only because
    // these sat in the guarded block's else). A refill_wen glitch
    // DURING reset can now load garbage here - harmless: nothing reads
    // these except under refill_stage_v_r/pending, both reset-held at 0,
    // and any real refill reloads them first.
    // Entry 35(a) (2026-08-25): only the registers the DRAIN reads keep the
    // refill_wen load-enable. refill_set_idx_r / refill_line_r /
    // refill_stage_tag_r are read by refill_bank_pending_r for as long as
    // it drains, so they must hold. The other four are consumed ONLY at
    // R+1 - refill_guard_ok_c and refill_words_valid_c, both under
    // refill_stage_v_r - and a free-running register holds exactly the
    // cycle-R read at R+1, so they capture every cycle and refill_wen
    // leaves their enable. Measured reason (e29all census): the refill
    // half of the wall was refill_set_id -> refill_rd_tag_r (62 @ -619),
    // refill_way -> (33) and refill_wen -> refill_rd_tag_r (18 @ -619),
    // with the enable AND as the last gates of the tag-bank read cone.
    // refill_waddr (= MSHR_Mux refill_set_id) is itself free-running, so
    // the address is stable to read on every edge.
    always_ff @(posedge clk) begin
        if (refill_wen) begin
            // Cycle R: capture only.
            refill_set_idx_r   <= refill_waddr;
            refill_line_r      <= refill_line;
            refill_stage_tag_r <= refill_tag;
        end
        refill_rd_tag_r    <= bank_refill_rtag_c[refill_bank_sel_c];
        refill_rd_wv_r     <= word_valid_mem[refill_waddr];
        refill_alloc_hit_r <= alloc_wen && (alloc_waddr == refill_waddr);
        refill_cpu_word_r  <=
            (cpu_word_wen && (cpu_waddr == refill_waddr))
                ? (WORDS_PER_LINE'(1'b1) << cpu_word_id)
                : '0;
    end

    // Control state: the drain mask keeps its reset - it is the ROOT
    // that decides whether anything is written into the arrays.
    //
    // Entry 29(m) (2026-08-25): refill_stage_v_r loses its reset. It is
    // a one-cycle pulse follower - set by refill_wen, cleared the next
    // cycle by itself - so it is SELF-CLEARING: whatever it powers up
    // as, it is 0 one edge later unless a refill is in flight, and
    // refill_wen is a defined 0 from e3 (Entry 29(d)/(l)). Its only
    // state consumer is refill_bank_pending_r, which keeps its reset:
    // during the flush cycles rst wins in this block, so a random
    // stage_v can decide nothing. In sim it is X until the first
    // refill (X != 0 in the `else if` is not taken, so nothing moves
    // and pending stays at its reset 0), and the first refill_wen
    // defines it. The two registers stay in one block because the
    // if/else-if priority between them is load-bearing.
    always_ff @(posedge clk) begin
        if (rst) begin
            refill_bank_pending_r <= '0;
        end
        else if (refill_wen) begin
            refill_stage_v_r      <= 1'b1;
            refill_bank_pending_r <= '0;   // pending zeroed (see above)
        end
        else if (refill_stage_v_r) begin
            // Cycle R+1: decide.
            refill_stage_v_r      <= 1'b0;
            refill_bank_pending_r <=
                refill_guard_ok_c ? ~refill_words_valid_c : '0;
        end
        else begin
            refill_bank_pending_r <= refill_pending_next_c;
        end
    end

`ifdef FTDA_E22_ASSERT
    // DISABLED by default 2026-08-25 (compile with +define+FTDA_E22_ASSERT to
    // re-enable): fires ~500x/job on E38 attempts (tag 0 vs live, way 1,
    // sets 0..24) - cause undiagnosed, see optimizations.md. The guard
    // itself (refill_guard_ok_c) is untouched.
    // E22 invariants (sim-only). (1) The staged decision must see the
    // array as the old same-cycle form would have: if the guard passes,
    // the live tag at the captured index still equals the held tag
    // (no alloc slipped past both kill terms). (2) Back-to-back pulses
    // are counted (FTDA INFO) and flagged - if this ever fires, the
    // "abandon the staged refill" rule above is being exercised.
    always_ff @(posedge clk) begin
        if (!rst && refill_stage_v_r && refill_guard_ok_c) begin
            assert (bank_tags_live_c == refill_stage_tag_r)
                else $error("FTDA E22: guard passed but live tag %h != held %h at set %0d",
                            bank_tags_live_c, refill_stage_tag_r, refill_set_idx_r);
        end
    end
`endif

    // ---- Data memory: one 1R1W RAM per line word ---------------------
    // Canonical simple-dual-port template: one write port (muxed
    // CPU-vs-refill), one sync read, no other drivers, no reset, no
    // internal bypass. Vivado infers LUTRAM ("distributed" is right at
    // DEPTH 32-256; switch to "block" if CACHE_BYTES scales).
    logic [LINE_WIDTH-1:0] rline_raw;

    // SRAM macro binding, gated by the EN_SRAM_MACRO parameter (a
    // parameter, not a define, so every tool can drive it: Genus via
    // elaborate -parameters, simulators via the testbench, FPGA never
    // sets it). The macro branch is taken only when the geometry
    // matches the hard macro exactly (256 x 32, i.e. 16KB ASSOC=4);
    // any other geometry falls back to behavioral - the Genus flow
    // fails the run if it expected macros and found none. The
    // simulation model for the macro lives in the VERIFICATION file
    // lists only (xcelium/filelist.f, Cache_verification.yml); timing
    // and ASIC lists bind the real macro views instead.
    localparam bit USE_SRAM_MACRO =
        EN_SRAM_MACRO && (DEPTH == 256) && (DATA_WIDTH == 32);

    generate
        for (genvar gw = 0; gw < WORDS_PER_LINE; gw++) begin : g_bank

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

            if (USE_SRAM_MACRO) begin : g_sram
                // OpenRAM 1RW+1R hard macro: port 0 write-only (csb/web
                // active low, full word mask), port 1 the every-cycle
                // sync read. Same read-during-write story as the
                // behavioral RAM: a colliding word is word_valid=0 to
                // its reader, so an undefined collision value is never
                // consumed.
                sram_1rw1r_32_256_8_sky130 u_sram (
                    .clk0   (clk),
                    .csb0   (~bank_wen_c),
                    .web0   (~bank_wen_c),
                    .wmask0 (4'hF),
                    .addr0  (bank_waddr_c),
                    .din0   (bank_wdata_c),
                    .dout0  (),
                    .clk1   (clk),
                    .csb1   (1'b0),
                    .addr1  (raddr),
                    .dout1  (rline_raw[gw*DATA_WIDTH +: DATA_WIDTH])
                );
            end
            else begin : g_flops
                (* ram_style = "distributed" *)
                logic [DATA_WIDTH-1:0] bank [0:DEPTH-1];

                always_ff @(posedge clk) begin
                    if (bank_wen_c) begin
                        bank[bank_waddr_c] <= bank_wdata_c;
                    end

                    rline_raw[gw*DATA_WIDTH +: DATA_WIDTH] <= bank[raddr];
                end
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

    // Entry 29: payload has no reset value -> own reset-free block.
    // During reset it loads whatever the inputs hold; fwd_hit_r gates
    // every consumer.
    // Entry 29(e): fwd_hit_r loses its reset too. It is an AND-term of
    // cpu_word_wen, the CSR grant, which is a defined 0 from e3 (see the
    // CSR Entry 29(e) note), so fwd_hit_r is 0 from e4 - rst is held
    // five edges. A random fwd_hit_r during the flush cycles only steers
    // the rline forward mux, whose output is unconsumed while the
    // pipeline valids are being flushed.
    always_ff @(posedge clk) begin
        fwd_word_r <= cpu_word_id;
        fwd_data_r <= cpu_wdata;
        fwd_hit_r  <= cpu_word_wen && (cpu_waddr == raddr);
    end

    always_comb begin
        rline = rline_raw;

        if (fwd_hit_r) begin
            rline[fwd_word_r*DATA_WIDTH +: DATA_WIDTH] = fwd_data_r;
        end
    end

    // ---- Flag memory, WRITE side (flops, both read forms) ------------
    // NOTE: statement order is load-bearing (NBA, later wins):
    // refill drain < alloc < CPU write.
    // Entry 21 split this block: storage writes here (unconditional),
    // the READ in the generate fork below. RHS array reads elsewhere
    // still see pre-edge values under NBA whether or not they share
    // this block, so the split is semantically free.
    // Entry 29(b) (2026-08-24): word_valid_mem left this block.
    // Entry 29(g) (2026-08-25): dirty_mem left it too (see below).
    // allocated_mem is the ONE flag array that keeps its reset: it must
    // read "cold cache" from cycle one (the TB catches its removal), and
    // it is the mask every other flag hides behind.
    //
    // Statement order is still load-bearing within each block (NBA,
    // later wins). The two blocks touch DISJOINT variables, so the split
    // costs no ordering guarantee: alloc < CPU write here, refill drain
    // < alloc < CPU write below, exactly as the single block had them.
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < DEPTH; i++) begin
                allocated_mem[i]  <= 1'b0;
            end
        end
        else begin
            // Allocate a new line.
            if (alloc_wen) begin
                allocated_mem[alloc_waddr]  <= 1'b1;
                // tag write lives in the per-bank blocks (g_tag_banks) -
                // separate always_ff, same edge, same NBA semantics.
            end
        end
    end

    // Entry 29(g) (2026-08-25): dirty_mem is RESET-FREE. E29(a) kept its
    // reset as "the X-optimism trap": an X victim_dirty branches FALSE
    // in simulation (no writeback) while silicon would write garbage
    // back to a stale tag. That trap is now closed BY CONSTRUCTION, not
    // by luck: Compare_Select_Replace qualifies out_victim_dirty with
    // allocated_eff[victim way], and a line's dirty bit is written to a
    // defined 0 by the alloc that sets allocated - the same edge, this
    // block. So for an allocated line dirty is always defined, and for
    // an unallocated one (the only source of X / power-up garbage) it is
    // ANDed with allocated = 0, which is 0 in silicon exactly as in a
    // 4-state simulator - the E29(b) word_valid_mem argument, applied to
    // the last flag array. Removes 512 loads (4 ways x 128 sets) from
    // the rst buffer tree; rst -> dirty_mem was a -30 ps class.
    //
    // Statement order stays load-bearing (NBA, later wins): alloc < CPU
    // write, as before.
    always_ff @(posedge clk) begin
        if (alloc_wen) begin
            dirty_mem[alloc_waddr] <= 1'b0;
        end

        // CPU write: flag side (data went through the bank port).
        if (cpu_word_wen) begin
            dirty_mem[cpu_waddr] <= 1'b1;
        end
    end

    // Entry 29(b): word_valid_mem is RESET-FREE, in its own
    // block so rst leaves its load-enable cone (the E29(a)
    // convention). Removes the last two rst-startpoint paths in the
    // census (word_valid_mem_reg[*][2]/D at -5 ps).
    //
    // WHY THIS IS SAFE, and NOT by X-luck (the standing E29 caveat):
    // word_valid is never consulted for a line that is not allocated -
    // a read hit requires allocated && word_valid[word] - and
    // allocated_mem KEEPS its reset, so every line reads "not
    // allocated" from cycle one. The moment a line IS allocated, the
    // alloc below CLEARS its word_valid to a defined '0 on that same
    // edge, before any reader can consult it. So for allocated lines
    // the value is always defined, and for unallocated lines the X is
    // masked by allocated=0 through a plain AND - which is 0 in
    // silicon exactly as it is in a 4-state simulator. The registered
    // read output word_valid_raw_r keeps its own reset regardless, so
    // cycle-one reads are defined at the output too.
    always_ff @(posedge clk) begin
        // Refill drain: mark each word valid AS its bank is written.
        // An alloc to this set later in the block re-clears these -
        // a refill landing on a just-renamed line stays invisible.
        for (int w = 0; w < WORDS_PER_LINE; w++) begin
            if (refill_grant_c[w]) begin
                word_valid_mem[refill_set_idx_r][w] <= 1'b1;
            end
        end

        if (alloc_wen) begin
            word_valid_mem[alloc_waddr] <= '0;
        end

        if (cpu_word_wen) begin
            word_valid_mem[cpu_waddr][cpu_word_id] <= 1'b1;
        end
    end

    // ---- Metadata READ side (Entry 21 generate fork) -----------------
    generate
        if (!TAG_READ_ONEHOT) begin : g_read_registered
            // Entry 26: the same-edge bypass is DEFERRED to S1. The old
            // form compared the S2 writer's address (alloc_waddr /
            // cpu_waddr, both = CSR's out_set_id) against raddr and
            // patched the read registers' D - putting out_set_id's Q
            // (871 ps at signoff) plus its congested write-decode net
            // in front of every read capture: the -1512..-1301
            // `out_set_id -> word_valid/dirty` class of the macro16
            // census, and FPGA's `cpu_req_addr -> word_valid_reg` tail.
            // Now the capture takes the RAW read; the bypass DECISION is
            // registered (one bit per writer) and the patch happens
            // after the registers, as one 2:1 mux per output with a
            // register-fed select - the E20/E25 shape.
            //
            // The compare never touches out_set_id at all: raddr flows
            // raddr -> dec_set_id -> out_set_id through UNCONDITIONAL
            // free-running registers (AD and CSR out_* have no enables),
            // so a private two-deep echo of raddr equals the writer's
            // address BY CONSTRUCTION - raddr_d2_r == alloc_waddr ==
            // cpu_waddr, always, bubbles included (asserted below). The
            // compare is register-vs-input on private short nets.
            //
            // The refill drain stays unpatched, exactly like the old
            // bypass: a same-edge drain mark must stay invisible for
            // one cycle because rline_raw is pre-drain on that edge
            // (see the Entry 21 header note - same hazard class).
            logic [SET_INDEX_W-1:0]    raddr_d1_r, raddr_d2_r;
            logic                      wr_set_match_c;

            // Entry 28(B) STRUCK 2026-08-24 (user call: measure E28(A)
            // alone). The group-registered read + S1 late select lives
            // in run 093545_e27b2e28b / notebook Entry 28(B); restore
            // from there if the A-world census says it still earns its
            // S1 mux.
            logic [TAG_WIDTH-1:0]      rtag_raw_r;
            logic                      allocated_raw_r;
            logic                      dirty_raw_r;
            logic [WORDS_PER_LINE-1:0] word_valid_raw_r;

            logic                      byp_alloc_r;
            logic                      byp_cpu_r;
            logic [WORD_OFFSET_W-1:0]  byp_cpu_word_r;
            logic [TAG_WIDTH-1:0]      byp_alloc_tag_r;

            assign wr_set_match_c = (raddr_d2_r == raddr);

            always_ff @(posedge clk) begin
                raddr_d1_r <= raddr;
                raddr_d2_r <= raddr_d1_r;
            end

            // Entry 29: rtag_raw_r and the byp payload carry no reset
            // values (rtag never reset historically) -> own block, rst
            // out of their cones. (E29(a) kept reset on the flag raw
            // regs + byp decisions; Entry 29(e) below removes it - they
            // are defined by the arrays' and grants' own resets.)
            always_ff @(posedge clk) begin
                rtag_raw_r      <= bank_rtag_c[r_bank_sel_c];
                byp_cpu_word_r  <= cpu_word_id;
                byp_alloc_tag_r <= alloc_tag;
            end

            // Entry 29(e) (2026-08-25): the flag read registers and the
            // bypass decision bits lose their reset. E29(a) kept them
            // ("must read as empty cache from cycle one") - but they READ
            // arrays that keep their reset: allocated_mem / dirty_mem are
            // forced 0 on the first reset edge, so allocated_raw_r /
            // dirty_raw_r load a defined 0 on the second, with rst held
            // five edges. word_valid_raw_r reads the reset-free
            // word_valid_mem, and is masked exactly as E29(b) argued for
            // the array itself: every consumer ANDs it with allocated,
            // which is 0 for any line not yet allocated (0 in silicon as
            // in 4-state sim). byp_alloc_r / byp_cpu_r are AND-terms of
            // alloc_wen / cpu_word_wen, which descend from the reset root
            // inreg_valid_r (e1) via dec_valid (e2) and the CSR grants
            // (e3): defined 0 from e4.
            //
            // Measured reason (baseline 20260824_180915, final db probe):
            // allocated_raw_r -758, word_valid_raw_r -755 and dirty_raw_r
            // -732 are the WALL endpoints of the tag-bank read cone, and
            // the reset term was folded into their last gate. byp_alloc_r
            // is the worst path's STARTPOINT; its reset put it on the rst
            // tree (rst -> byp_alloc_r at -18).
            always_ff @(posedge clk) begin
                allocated_raw_r  <= allocated_mem[raddr];
                dirty_raw_r      <= dirty_mem[raddr];
                word_valid_raw_r <= word_valid_mem[raddr];

                byp_alloc_r      <= alloc_wen    && wr_set_match_c;
                byp_cpu_r        <= cpu_word_wen && wr_set_match_c;
            end

            // S1-side patch. Priority mirrors the old NBA order exactly
            // (alloc base, CPU-write override); per way the two writers
            // are mutually exclusive anyway - one S2 request is either
            // an alloc or a write hit, never both.
            always_comb begin
                rtag      = byp_alloc_r ? byp_alloc_tag_r : rtag_raw_r;
                allocated = byp_alloc_r ? 1'b1 : allocated_raw_r;
                dirty     = byp_cpu_r   ? 1'b1
                          : byp_alloc_r ? 1'b0
                          :               dirty_raw_r;

                word_valid = byp_alloc_r ? '0 : word_valid_raw_r;
                if (byp_cpu_r) begin
                    word_valid[byp_cpu_word_r] = 1'b1;
                end
            end

`ifndef SYNTHESIS
            // Entry 26 structural invariant: the private raddr echo IS
            // the writer's address. If this ever fires, an enable crept
            // into the AD/CSR out_* registers and the whole deferral is
            // unsound - fail loudly, don't limp.
            always_ff @(posedge clk) begin
                if (!rst) begin
                    if (alloc_wen) begin
                        assert (alloc_waddr == raddr_d2_r)
                            else $error("FTDA E26: alloc_waddr %0d != raddr echo %0d",
                                        alloc_waddr, raddr_d2_r);
                    end
                    if (cpu_word_wen) begin
                        assert (cpu_waddr == raddr_d2_r)
                            else $error("FTDA E26: cpu_waddr %0d != raddr echo %0d",
                                        cpu_waddr, raddr_d2_r);
                    end
                end
            end
`endif
        end
        else begin : g_read_onehot
            // Entry 21 form: S1 reads the flop arrays LIVE through a
            // flat AND-OR against the registered one-hot. No read
            // registers, no bypasses - a write landing on the S0->S1
            // edge is array state by the time this settles, and a write
            // landing on the S1->S2 edge is invisible under NBA: the
            // exact visibility the registered+bypass form had.
            logic                      allocated_oh_c;
            logic                      dirty_oh_c;
            logic [WORDS_PER_LINE-1:0] wv_oh_c;
            logic [TAG_WIDTH-1:0]      rtag_oh_c;

            // The one deliberate difference (header note): words the
            // refill drain wrote into the READ set on the capture edge
            // must stay hidden for one cycle - their rline_raw data was
            // captured pre-drain on that same edge. Registered compare,
            // gated on an active drain so it is 0-clean before the
            // first refill (refill_set_idx_r starts X in sim).
            logic [WORDS_PER_LINE-1:0] wv_drain_hide_r;

            always_ff @(posedge clk) begin
                if (rst) begin
                    wv_drain_hide_r <= '0;
                end
                else begin
                    wv_drain_hide_r <=
                        ((refill_bank_pending_r != '0) &&
                         (refill_set_idx_r == raddr))
                            ? refill_grant_c : '0;
                end
            end

            always_comb begin
                allocated_oh_c = 1'b0;
                dirty_oh_c     = 1'b0;
                wv_oh_c        = '0;
                for (int i = 0; i < DEPTH; i++) begin
                    if (raddr_onehot[i]) begin
                        allocated_oh_c |= allocated_mem[i];
                        dirty_oh_c     |= dirty_mem[i];
                        wv_oh_c        |= word_valid_mem[i];
                    end
                end
            end

            // Tag: OR of the per-bank AND-OR taps (one-hot is exclusive
            // across banks, so this is an OR, not a mux).
            always_comb begin
                rtag_oh_c = '0;
                for (int b = 0; b < TAG_NBANKS; b++) begin
                    rtag_oh_c |= bank_onehot_rtag_c[b];
                end
            end

            assign rtag       = rtag_oh_c;
            assign allocated  = allocated_oh_c;
            assign dirty      = dirty_oh_c;
            assign word_valid = wv_oh_c & ~wv_drain_hide_r;
        end
    endgenerate

`ifndef SYNTHESIS
    // ---- INFO counters (sim-only, 2026-08-23): the refill guard and drain
    // interlock outcomes that E22 (snoop-based guard) and E24 (one-read-port
    // tag macros) must reproduce. Printed at end of sim, RS INFO style.
    int info_refills, info_guard_tag_mismatch, info_guard_alloc_kill;
    int info_refill_partial, info_drain_cycles, info_drain_cpu_block;
    int info_drain_alloc_kill, info_drain_cpu_clear, info_alloc_bypass_hits;
    int info_cpu_write_fwd_hits, info_rd_collide_drain, info_refill_back_to_back;

    // Counters accumulate across the TB's per-test resets (RS INFO style).
    initial begin
            info_refills = 0; info_guard_tag_mismatch = 0; info_guard_alloc_kill = 0;
            info_refill_partial = 0; info_drain_cycles = 0; info_drain_cpu_block = 0;
            info_drain_alloc_kill = 0; info_drain_cpu_clear = 0; info_alloc_bypass_hits = 0;
            info_cpu_write_fwd_hits = 0; info_rd_collide_drain = 0; info_refill_back_to_back = 0;
    end
    always @(posedge clk) begin
        if (!rst) begin
            if (refill_wen) begin
                info_refills++;
                if (refill_stage_v_r) info_refill_back_to_back++;
            end
            if (refill_stage_v_r && !refill_wen) begin
                if (refill_stage_tag_r != refill_rd_tag_r)
                    info_guard_tag_mismatch++;
                if (refill_alloc_hit_r ||
                    (alloc_wen && (alloc_waddr == refill_set_idx_r)))
                    info_guard_alloc_kill++;
                if (refill_guard_ok_c && (refill_words_valid_c != '0))
                    info_refill_partial++;
            end
            if (refill_bank_pending_r != '0) begin
                info_drain_cycles++;
                if (cpu_word_wen && refill_bank_pending_r[cpu_word_id])
                    info_drain_cpu_block++;
                if (alloc_wen && (alloc_waddr == refill_set_idx_r))
                    info_drain_alloc_kill++;
                if (cpu_word_wen && (cpu_waddr == refill_set_idx_r) &&
                    refill_bank_pending_r[cpu_word_id])
                    info_drain_cpu_clear++;
                if (refill_set_idx_r == raddr)
                    info_rd_collide_drain++;
            end
            if (alloc_wen && (alloc_waddr == raddr))
                info_alloc_bypass_hits++;
            if (cpu_word_wen && (cpu_waddr == raddr))
                info_cpu_write_fwd_hits++;
        end
    end

    final begin
        $display("FTDA INFO %m: refills=%0d back-to-back=%0d guard-tag-mismatch=%0d guard-alloc-kill=%0d partial(cpu-wrote-first)=%0d | drain cycles=%0d cpu-port-block=%0d alloc-kill-mid-drain=%0d cpu-clear-mid-drain=%0d read-collides-drain=%0d | same-edge bypass: alloc=%0d cpu-write=%0d",
                 info_refills, info_refill_back_to_back, info_guard_tag_mismatch, info_guard_alloc_kill,
                 info_refill_partial, info_drain_cycles, info_drain_cpu_block,
                 info_drain_alloc_kill, info_drain_cpu_clear, info_rd_collide_drain,
                 info_alloc_bypass_hits, info_cpu_write_fwd_hits);
    end
`endif

endmodule
