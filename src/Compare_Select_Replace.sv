// ============================================================
// Compare_Select_Replace
//
// Reduced metadata path:
//   - carries tag/set/word only
//   - removed in_addr / out_addr
//   - removed in_line_addr / out_line_addr
//
// Entry 3 (optimizations.md): one-hot restructure of the compare/
// select cone. The invariant everything below leans on:
//
//   line_match_c is one-hot BY CONSTRUCTION. A line is only
//   allocated when no way already matched (!line_found_c), so two
//   ways in a set can never hold the same tag. A partial-line read
//   miss raises miss_c WITHOUT allocating, so it cannot create a
//   duplicate either. Armed by the $onehot0 assertion at the bottom.
//
// With at most one match bit ever set, the match bits themselves can
// drive muxes and write enables directly - no priority encoder, no
// binary way index in the middle, no decoder back out. Every
// encode->decode round trip in the old code was serial-depth on the
// critical cone (out_tag -> data_bank write enables); the one-hot
// forms are flat AND-OR trees. Level-by-level accounting lives in
// optimizations.md Entry 3.
// ============================================================

module Compare_Select_Replace #(
    parameter int ASSOC           = 4,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int TAG_WIDTH       = 24,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int WORDS_PER_LINE  = 4,
    parameter int WAY_INDEX_W     = (ASSOC <= 1) ? 1 : $clog2(ASSOC)
)(
    input  logic clk,
    input  logic rst,

    input  logic                       in_valid,
    input  logic                       in_write,
    input  logic [DATA_WIDTH-1:0]      in_wdata,
    input  logic [CPU_ID_WIDTH-1:0]    in_cpu_req_id,
    input  logic [TAG_WIDTH-1:0]       in_tag,
    input  logic [SET_INDEX_W-1:0]     in_set_id,
    input  logic [WORD_OFFSET_W-1:0]   in_word_id,

    // Entry 25: the elder-patch compares, registered in Address_Decode
    // one stage early (see its header note). Replaces the S1-side
    // compares that rooted the victim-snapshot select cone.
    input  logic                       pre_same_set,
    input  logic                       pre_same_word,
    input  logic                       pre_tag_match,

    input  logic [LINE_WIDTH-1:0]      way_line       [ASSOC],
    input  logic [TAG_WIDTH-1:0]       way_tag        [ASSOC],
    input  logic                       way_allocated  [ASSOC],
    input  logic                       way_dirty      [ASSOC],
    input  logic [WORDS_PER_LINE-1:0]  way_word_valid [ASSOC],

    input  logic [WAY_INDEX_W-1:0]     replacement_way,

    output logic                       out_valid,
    output logic                       out_write,
    output logic                       out_hit,
    output logic                       out_miss,

    output logic [DATA_WIDTH-1:0]      out_wdata,
    output logic [DATA_WIDTH-1:0]      out_rdata,
    output logic [CPU_ID_WIDTH-1:0]    out_cpu_req_id,
    output logic [TAG_WIDTH-1:0]       out_tag,
    output logic [SET_INDEX_W-1:0]     out_set_id,
    output logic [WORD_OFFSET_W-1:0]   out_word_id,

    output logic [WAY_INDEX_W-1:0]     out_miss_way,

    output logic                       out_victim_dirty,
    output logic [TAG_WIDTH-1:0]       out_victim_tag,
    output logic [LINE_WIDTH-1:0]      out_victim_line,
    output logic [WORDS_PER_LINE-1:0]  out_victim_word_valid,

    output logic [ASSOC-1:0]           alloc_wen,
    output logic [SET_INDEX_W-1:0]     alloc_waddr,
    output logic [TAG_WIDTH-1:0]       alloc_tag,

    output logic [ASSOC-1:0]           cpu_write_wen,
    output logic [SET_INDEX_W-1:0]     cpu_write_set_id,
    output logic [WORD_OFFSET_W-1:0]   cpu_write_word_id,
    output logic [DATA_WIDTH-1:0]      cpu_write_wdata,

    output logic                       replacement_update_valid,
    output logic [SET_INDEX_W-1:0]     replacement_update_set,
    output logic [WAY_INDEX_W-1:0]     replacement_update_way
);

    logic [ASSOC-1:0]       line_match_c;
    logic [ASSOC-1:0]       way_hit_c;
    logic [DATA_WIDTH-1:0]  way_word_c [ASSOC];

    logic [WAY_INDEX_W-1:0] hit_way_c;       // binary, off-path (encoded below)
    logic [DATA_WIDTH-1:0]  selected_word_c;

    logic line_found_c;

    logic hit_c;
    logic miss_c;

    // Victim-way selection, one-hot form. All of these are EARLY: their
    // inputs are the registered array flags and the registered PLRU
    // index, so they settle at the start of the cycle, long before the
    // tag compare resolves. None of them add to the critical cone.
    logic [ASSOC-1:0]       way_allocated_v; // packed copy for reductions
    logic [ASSOC-1:0]       free_onehot;     // first non-allocated way
    logic [ASSOC-1:0]       repl_onehot;     // decoded PLRU victim
    logic [ASSOC-1:0]       miss_way_onehot; // chosen victim way
    logic                   has_free;

    logic [WAY_INDEX_W-1:0] miss_way_c;      // binary, off-path (encoded below)

    // One-hot -> binary OR-encoder. Legal only because the input has at
    // most one bit set: OR-ing together the indices of the set bits IS
    // the index. The |= form has no priority semantics, so this is a
    // flat AND-OR tree (~3 levels), not a serial chain. Used only for
    // the two consumers that still want binary (replacement_update_way,
    // out_miss_way / victim capture) - both slack endpoints.
    function automatic logic [WAY_INDEX_W-1:0] onehot_to_idx
        (input logic [ASSOC-1:0] onehot);
        logic [WAY_INDEX_W-1:0] idx;
        idx = '0;
        for (int i = 0; i < ASSOC; i++) begin
            if (onehot[i]) begin
                idx |= WAY_INDEX_W'(i);
            end
        end
        return idx;
    endfunction

    // ---- Entry 20: the elder patch ----------------------------------------
    // Array writes fire in S2 (from the registered grants below), one
    // cycle after the S1 decision. So the request one slot ahead of us -
    // "E", in S2 right now, its writes landing on the NEXT edge - is
    // invisible to the read we registered at the S0->S1 edge. The request
    // two ahead ("W") wrote on that very edge and is covered by the
    // array's own read-after-write bypasses. E is covered here: every S1
    // decision (hit, grant, victim select, victim snapshot) is made from
    // the patched *_eff view, which is the array as it will be after E's
    // write. E's grants and addresses are this module's own S2 registers.
    // Patch order alloc < write mirrors the array's NBA order.
    logic                       e_same_set_c;
    logic                       e_same_word_c;
    logic                       e_tag_match_c;
    logic [ASSOC-1:0]           e_alloc_c;
    logic [ASSOC-1:0]           e_write_c;

    logic                       allocated_eff  [ASSOC];
    logic                       tag_match_eff  [ASSOC];
    logic [WORDS_PER_LINE-1:0]  word_valid_eff [ASSOC];
    logic                       dirty_eff      [ASSOC];
    logic [TAG_WIDTH-1:0]       tag_eff        [ASSOC];
    logic [LINE_WIDTH-1:0]      line_eff       [ASSOC];

    // Entry 25: register-fed from Address_Decode (was: S1-side compares
    // of out_* vs in_* - the late root of every eff-select term; the A8
    // post-route probe measured ~1.4 ns of the victim snapshot's 2.25 ns
    // in this select cone). The internal names survive so every eff
    // term below is untouched.
    assign e_same_set_c  = pre_same_set;
    assign e_same_word_c = pre_same_word;
    assign e_tag_match_c = pre_tag_match;

`ifndef SYNTHESIS
    // Entry 25 equivalence guard: the pre-registered compare must equal
    // the live compare whenever both pipeline slots hold requests (the
    // only time the eff terms are consumed - the elder's write grants
    // gate them).
    always_ff @(posedge clk) begin
        if (!rst && in_valid && out_valid) begin
            assert (pre_same_set  == (out_set_id  == in_set_id) &&
                    pre_same_word == (out_word_id == in_word_id) &&
                    pre_tag_match == (in_tag == out_tag))
                else $error("CSR E25: pre-compare diverged from live compare (set %b/%b word %b/%b tag %b/%b)",
                            pre_same_set,  (out_set_id  == in_set_id),
                            pre_same_word, (out_word_id == in_word_id),
                            pre_tag_match, (in_tag == out_tag));
        end
    end
`endif

    always_comb begin
        for (int i = 0; i < ASSOC; i++) begin
            e_alloc_c[i] = alloc_wen[i]     && e_same_set_c;
            e_write_c[i] = cpu_write_wen[i] && e_same_set_c;

            allocated_eff[i] = e_alloc_c[i] ? 1'b1 : way_allocated[i];
            tag_eff[i]       = e_alloc_c[i] ? out_tag : way_tag[i];
            tag_match_eff[i] = e_alloc_c[i] ? e_tag_match_c
                                            : (way_tag[i] == in_tag);

            word_valid_eff[i] =
                (e_alloc_c[i] ? '0 : way_word_valid[i]) |
                (e_write_c[i] ? (WORDS_PER_LINE'(1'b1) << out_word_id)
                              : '0);

            dirty_eff[i] = e_write_c[i] ? 1'b1
                         : e_alloc_c[i] ? 1'b0
                         : way_dirty[i];

            // Victim snapshot only (slack endpoint): E's word folded in.
            line_eff[i] = way_line[i];
            if (e_write_c[i]) begin
                line_eff[i][out_word_id * DATA_WIDTH +: DATA_WIDTH]
                    = out_wdata;
            end
        end
    end

    // ---- Tag compare --------------------------------------------------------
    // Parallel per way: ~6 levels from out_tag to way_hit_c. A write hits
    // on tag match alone; a read additionally needs its word_valid bit
    // (sub-line valid - the word may not have arrived yet). The per-way
    // word takes E's data on the early side of the hit AND-OR, so the late
    // way_hit_c input gains no level from the patch.
    always_comb begin
        for (int i = 0; i < ASSOC; i++) begin
            way_word_c[i] =
                (e_write_c[i] && e_same_word_c)
                    ? out_wdata
                    : way_line[i][in_word_id * DATA_WIDTH +: DATA_WIDTH];

            line_match_c[i] = allocated_eff[i] && tag_match_eff[i];

            way_hit_c[i] =
                in_write
                    ? line_match_c[i]
                    : line_match_c[i] &&
                      word_valid_eff[i][in_word_id];
        end
    end

    // ---- Piece 1: read-data select --------------------------------------
    // Was: a last-match-wins for-loop - synthesizes to a serial
    // ASSOC-deep 2:1 mux cascade on the 32-bit word (~8 levels after
    // way_hit_c at ASSOC=8), because each iteration's result feeds the
    // next iteration's mux.
    // Now: AND-OR merge. |= carries no priority, so synthesis builds
    //   (hit[0]&word[0]) | (hit[1]&word[1]) | ... :
    // one AND level plus a log2(ASSOC) OR tree (~4 levels), every way in
    // parallel. Sound because way_hit_c is one-hot (it is a masked
    // subset of one-hot line_match_c).
    always_comb begin
        selected_word_c = '0;
        for (int i = 0; i < ASSOC; i++) begin
            if (way_hit_c[i]) begin
                selected_word_c |= way_word_c[i];
            end
        end
    end

    // Binary hit way survives only for replacement_update_way, encoded
    // from the one-hot off the critical path (that endpoint has slack).
    assign hit_way_c = onehot_to_idx(way_hit_c);

    // Was a for-loop OR; same tree either way, this is just the honest
    // spelling of it.
    assign line_found_c = |line_match_c;

    assign hit_c  = |way_hit_c;
    assign miss_c = in_valid && !hit_c;

    // ---- Piece 3: first-free way, prefix-AND form -----------------------
    // Was: a found/way ripple loop - iteration i's condition depended on
    // iteration i-1's regular_found_c (~ASSOC serial levels), and the
    // result was a binary index piece 2 then had to decode again.
    // Now: "way i is the first free way <=> way i is free AND every way
    // below it is allocated". Each bit is an independent AND-reduce over
    // a constant slice (~3 levels, all bits in parallel), and the result
    // is already the one-hot form piece 2 consumes.
    always_comb begin
        for (int i = 0; i < ASSOC; i++) begin
            way_allocated_v[i] = allocated_eff[i];
        end
    end

    generate
        for (genvar gi = 0; gi < ASSOC; gi++) begin : g_free
            if (gi == 0) begin : g_first
                assign free_onehot[0] = !way_allocated_v[0];
            end
            else begin : g_rest
                assign free_onehot[gi] =
                    !way_allocated_v[gi] &&
                    (&way_allocated_v[gi-1:0]);
            end
        end
    endgenerate

    // ---- Piece 4: victim mux, one-hot form ------------------------------
    // replacement_way arrives REGISTERED from the PLRU, so the 3->8
    // decode costs ~2 levels at the very start of the cycle, off-path.
    // has_free is register-fed too. miss_way_onehot is therefore sitting
    // ready before miss_c arrives - zero cost on the critical cone.
    // Semantics identical to the old
    //   miss_way_c = regular_found_c ? regular_way_c : replacement_way;
    assign repl_onehot = ASSOC'(1'b1) << replacement_way;

    assign has_free = !(&way_allocated_v);

    assign miss_way_onehot = has_free ? free_onehot : repl_onehot;

    // Binary victim index survives for out_miss_way and the victim
    // capture below - both early/slack endpoints, per the Genus and FPGA
    // worst-path lists. Deliberately NOT restructured (plan: don't touch
    // victim capture).
    assign miss_way_c = onehot_to_idx(miss_way_onehot);

    // ---- Piece 2: array write enables, decided in S1, applied in S2 -------
    // Entry 20. Entry 10 computed these in S0 from a combinational tag
    // read off the raw address - the cone that held WNS on every meter
    // (ASIC: 803 ps of input budget + ~1450 ps fanning the set index to
    // ~22k mux selects + ~2600 ps of 64:1 mux, before any compare). Now
    // S0 is the read and a register; the grant is the S1 reference model
    // Entry 10 kept for its equivalence check, registered, and the array
    // writes fire from these flops in S2, addressed by the S2 registers.
    // Writes become visible one cycle later - unobservable from outside;
    // the elder patch above keeps the next request consistent.
    // Entry 29(e) (2026-08-25): the grants lose their reset. Both are
    // AND-terms of in_valid (miss_c = in_valid && !hit_c; in_write is
    // dec_write = accept && in_write upstream), and in_valid descends
    // from the reset ROOT inreg_valid_r: 0 at e1 -> dec_valid 0 at e2 ->
    // these read 0 at e3, with rst held five edges. Measured reason: the
    // reset was the LAST gate on both D cones (alloc_wen_reg ends in a
    // nor2b_1, 199 ps, at -529; cpu_write_wen_reg at -744), i.e. on the
    // S1 compare cone that owns the wall. Silicon flush cycles: a random
    // grant can only write reset-held allocated_mem/dirty_mem (reset
    // wins), or the reset-free word_valid_mem / tag / data banks, whose
    // contents are masked by allocated=0 and re-initialised at alloc.
    always_ff @(posedge clk) begin
        for (int i = 0; i < ASSOC; i++) begin
            cpu_write_wen[i] <=
                in_write && (miss_c ? miss_way_onehot[i]
                                    : way_hit_c[i]);

            alloc_wen[i] <=
                miss_c && !line_found_c && miss_way_onehot[i];
        end
    end

    // Write addressing rides the S2 registers (Entry 20).
    assign alloc_waddr = out_set_id;
    assign alloc_tag   = out_tag;

    assign cpu_write_set_id  = out_set_id;
    assign cpu_write_word_id = out_word_id;
    assign cpu_write_wdata   = out_wdata;

    assign replacement_update_valid = in_valid;
    assign replacement_update_set   = in_set_id;
    assign replacement_update_way   =
        hit_c ? hit_way_c : miss_way_c;

    // Entry 29(e): the S2 control bits lose their reset - same derivation
    // as the grants above (in_valid/in_write are e2-defined from the
    // root; hit_c reads reset-held allocated_mem through e2-defined read
    // registers, so it is defined from e3; miss_c = in_valid && !hit_c).
    // out_hit (-310) and out_miss (-450) are endpoints of the tag-compare
    // cone; the reset was one extra term on each D.
    always_ff @(posedge clk) begin
        out_valid <= in_valid;
        out_write <= in_write;
        out_hit   <= hit_c;
        out_miss  <= miss_c;
    end

    always_ff @(posedge clk) begin
        out_wdata      <= in_wdata;
        out_rdata      <= selected_word_c;
        out_cpu_req_id <= in_cpu_req_id;
        out_tag        <= in_tag;
        out_set_id     <= in_set_id;
        out_word_id    <= in_word_id;

        out_miss_way <= miss_way_c;

        // Entry 29(g) (2026-08-25): the victim's dirty bit is qualified
        // by the victim way's allocated flag. Behaviourally a no-op - a
        // free way was never dirty (its dirty_mem read as reset 0) - but
        // it is what lets dirty_mem drop its reset in the array: an
        // unallocated way's dirty is garbage/X there now, and this AND
        // is the mask (X && 0 = 0 in sim, 0 && x = 0 in silicon). Both
        // operands are early (register-fed flags + the PLRU one-hot), so
        // this adds nothing to the -752 victim-snapshot cone.
        out_victim_dirty      <= dirty_eff[miss_way_c] &&
                                 allocated_eff[miss_way_c];
        out_victim_tag        <= tag_eff[miss_way_c];
        out_victim_line       <= line_eff[miss_way_c];
        out_victim_word_valid <= word_valid_eff[miss_way_c];
    end

`ifndef SYNTHESIS
    // Arms the invariant every one-hot rewrite above depends on.
    // Same style as the Entry 2 assertion in Reservation_Station.sv.
    always_ff @(posedge clk) begin
        if (!rst) begin
            assert ($onehot0(line_match_c))
                else $error("CSR: line_match_c not one-hot (%b)",
                            line_match_c);
        end
    end

    // ---- INFO counters (sim-only, 2026-08-23): how often the E20 elder
    // patch is live, and the line-found miss population (a read miss on a
    // line that IS allocated - its refill goes to miss_way_c, the victim,
    // not the matching way; see the E22 investigation).
    int info_reqs, info_e_alloc_live, info_e_write_live, info_e_word_fwd;
    int info_miss_linefound, info_miss_alloc, info_hits, info_e_changed_hit;
    logic hit_unpatched_c;
    always_comb begin
        hit_unpatched_c = 1'b0;
        for (int i = 0; i < ASSOC; i++) begin
            if (way_allocated[i] && (way_tag[i] == in_tag) &&
                (in_write || way_word_valid[i][in_word_id]))
                hit_unpatched_c = 1'b1;
        end
    end
    initial begin
            info_reqs = 0; info_e_alloc_live = 0; info_e_write_live = 0; info_e_word_fwd = 0;
            info_miss_linefound = 0; info_miss_alloc = 0; info_hits = 0; info_e_changed_hit = 0;
    end
    always @(posedge clk) begin
        if (!rst && in_valid) begin
            info_reqs++;
            if (|e_alloc_c) info_e_alloc_live++;
            if (|e_write_c) info_e_write_live++;
            if ((|e_write_c) && e_same_word_c) info_e_word_fwd++;
            if (hit_c) info_hits++;
            if (miss_c && line_found_c) info_miss_linefound++;
            if (miss_c && !line_found_c) info_miss_alloc++;
            if (hit_c != hit_unpatched_c) info_e_changed_hit++;
        end
    end
    final begin
        $display("CSR INFO %m: reqs=%0d hits=%0d miss-alloc=%0d miss-line-found=%0d | E patch live: alloc=%0d write=%0d word-fwd=%0d hit-decision-changed=%0d",
                 info_reqs, info_hits, info_miss_alloc, info_miss_linefound,
                 info_e_alloc_live, info_e_write_live, info_e_word_fwd, info_e_changed_hit);
    end
`endif

endmodule
