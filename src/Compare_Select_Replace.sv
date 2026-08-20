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

    // ---- Tag compare (unchanged) ----------------------------------------
    // Parallel per way: ~6 levels from out_tag to way_hit_c. A write hits
    // on tag match alone; a read additionally needs its word_valid bit
    // (sub-line valid - the word may not have arrived yet).
    always_comb begin
        for (int i = 0; i < ASSOC; i++) begin
            way_word_c[i] =
                way_line[i][in_word_id * DATA_WIDTH +: DATA_WIDTH];

            line_match_c[i] =
                way_allocated[i] &&
                (way_tag[i] == in_tag);

            way_hit_c[i] =
                in_write
                    ? line_match_c[i]
                    : line_match_c[i] &&
                      way_word_valid[i][in_word_id];
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
            way_allocated_v[i] = way_allocated[i];
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

    // ---- Piece 2: array write enables, straight from the one-hots -------
    // This was the main event - the old encode->decode round trip:
    //   way_hit_c -> priority-encoded binary hit_way_c (~8 serial levels)
    //   -> 2:1 index mux vs miss_way_c
    //   -> dynamic-index decode back to ASSOC enable bits (~3 levels)
    // i.e. ~12 levels after way_hit_c, on the enables that fan out to
    // every data_bank write port in Flag_Tag_Data_Array - the dominant
    // critical cone on both meters (Genus out_tag->data_bank; 565/1000
    // FPGA worst post-route paths).
    // Now each way's enable comes from that way's OWN bits - no shared
    // index anywhere (~5 levels after way_hit_c: the miss_c OR-tree,
    // a 2:1 select, an AND):
    //   - a write lands in the hit way, or on a miss in the victim way
    //     (write-allocate: the word goes into the array immediately);
    //   - allocation fires only on a true line miss (!line_found_c),
    //     never on a partial-line read miss - which is exactly what
    //     preserves the one-hot invariant this file depends on.
    // in_write is valid-qualified upstream (Address_Decode registers
    // out_write <= accept && in_write), so no extra in_valid gate is
    // needed here - same reachable behavior as the old code.
    always_comb begin
        for (int i = 0; i < ASSOC; i++) begin
            cpu_write_wen[i] =
                in_write &&
                (miss_c ? miss_way_onehot[i] : way_hit_c[i]);

            alloc_wen[i] =
                miss_c && !line_found_c && miss_way_onehot[i];
        end
    end

    assign alloc_waddr = in_set_id;
    assign alloc_tag   = in_tag;

    assign cpu_write_set_id  = in_set_id;
    assign cpu_write_word_id = in_word_id;
    assign cpu_write_wdata   = in_wdata;

    assign replacement_update_valid = in_valid;
    assign replacement_update_set   = in_set_id;
    assign replacement_update_way   =
        hit_c ? hit_way_c : miss_way_c;

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_write <= 1'b0;
            out_hit   <= 1'b0;
            out_miss  <= 1'b0;
        end
        else begin
            out_valid <= in_valid;
            out_write <= in_write;
            out_hit   <= hit_c;
            out_miss  <= miss_c;
        end
    end

    always_ff @(posedge clk) begin
        out_wdata      <= in_wdata;
        out_rdata      <= selected_word_c;
        out_cpu_req_id <= in_cpu_req_id;
        out_tag        <= in_tag;
        out_set_id     <= in_set_id;
        out_word_id    <= in_word_id;

        out_miss_way <= miss_way_c;

        out_victim_dirty      <= way_dirty[miss_way_c];
        out_victim_tag        <= way_tag[miss_way_c];
        out_victim_line       <= way_line[miss_way_c];
        out_victim_word_valid <= way_word_valid[miss_way_c];
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
`endif

endmodule
