// ============================================================
// Tree-based pseudo-LRU replacement policy
// ASSOC = 1 returns way 0
// ASSOC > 1 uses ASSOC-1 PLRU bits per set
//
// Fully sequential lookup:
//   replacement_way is registered.
//   Output corresponds to previous cycle's lookup_set.
//
// This module is PLRU only.
// It does NOT check valid bits.
// Invalid-way priority is handled outside this module.
// ============================================================

module Replacement #(
    parameter int ASSOC       = 4,
    parameter int NUM_SETS    = 64,

    parameter int WAY_INDEX_W = (ASSOC <= 1) ? 1 : $clog2(ASSOC),
    parameter int SET_INDEX_W = (NUM_SETS <= 1) ? 1 : $clog2(NUM_SETS)
)(
    input  logic clk,
    input  logic rst,

    // PLRU victim lookup
    input  logic [SET_INDEX_W-1:0] lookup_set,
    output logic [WAY_INDEX_W-1:0] replacement_way,

    // PLRU state update
    input  logic                   update_valid,
    input  logic [SET_INDEX_W-1:0] update_set,
    input  logic [WAY_INDEX_W-1:0] update_way
);

    generate
        if (ASSOC == 1) begin : GEN_DIRECT_MAPPED

            always_ff @(posedge clk) begin
                if (rst) begin
                    replacement_way <= '0;
                end else begin
                    replacement_way <= '0;
                end
            end

        end else begin : GEN_TREE_PLRU

            localparam int PLRU_BITS = ASSOC - 1;
            localparam int LEVELS    = $clog2(ASSOC);

            logic [PLRU_BITS-1:0]    plru_bits [NUM_SETS-1:0];
            logic [PLRU_BITS-1:0]    curr_bits;
            logic [PLRU_BITS-1:0]    next_bits;
            logic [WAY_INDEX_W-1:0]  replacement_way_n;

            // Entry 12: the array write is deferred one cycle. update_way
            // is born late (tag compare -> hit-way encode), and next_bits
            // used to broadcast it to every set's D pins in that same
            // cycle. Now {valid, set, next_bits} REGISTER first (~12
            // flops), and the wide write fires the following cycle from
            // flops. update_set_r / next_bits_r load every cycle so that
            // update_valid_r means exactly "a write lands at the next
            // edge" - the bypass below can never see a stale pending set.
            logic                   update_valid_r;
            logic [SET_INDEX_W-1:0] update_set_r;
            logic [PLRU_BITS-1:0]   next_bits_r;
            logic                   bypass_c;

            // Tree walk and tree update as functions: one source of truth
            // for the hardware and the sim-only shadow model below.
            function automatic logic [WAY_INDEX_W-1:0] plru_lookup
                (input logic [PLRU_BITS-1:0] bits);
                logic [WAY_INDEX_W-1:0] way;
                int node;
                way  = '0;
                node = 0;
                for (int level = 0; level < LEVELS; level++) begin
                    if (bits[node] == 1'b0) begin
                        way[LEVELS-1-level] = 1'b0;
                        node = (2 * node) + 1;
                    end else begin
                        way[LEVELS-1-level] = 1'b1;
                        node = (2 * node) + 2;
                    end
                end
                return way;
            endfunction

            function automatic logic [PLRU_BITS-1:0] plru_update_f
                (input logic [PLRU_BITS-1:0]   bits,
                 input logic [WAY_INDEX_W-1:0] way);
                logic [PLRU_BITS-1:0] nb;
                int node;
                nb   = bits;
                node = 0;
                for (int level = 0; level < LEVELS; level++) begin
                    if (way[LEVELS-1-level] == 1'b0) begin
                        nb[node] = 1'b1;
                        node = (2 * node) + 1;
                    end else begin
                        nb[node] = 1'b0;
                        node = (2 * node) + 2;
                    end
                end
                return nb;
            endfunction

            // RMW bypass: back-to-back updates to the same set would read
            // array state that has not absorbed the pending write yet -
            // last-write-wins would silently drop the older update. Seed
            // from the pending registers instead. Both select inputs are
            // flops, so the bypass adds nothing to the late cone.
            assign bypass_c  = update_valid_r && (update_set == update_set_r);
            assign curr_bits = bypass_c ? next_bits_r : plru_bits[update_set];

            assign next_bits = plru_update_f(curr_bits, update_way);

            // ====================================================
            // PLRU victim select for current lookup_set
            // Registered into replacement_way on clk edge.
            // ====================================================

            assign replacement_way_n = plru_lookup(plru_bits[lookup_set]);

            // Entry 29(k) (2026-08-25): the PLRU array is RESET-FREE.
            // Rejected on 2026-08-24 when the price was cell mapping
            // (all dfxtp_1 already, not on any cone); re-opened when the
            // rst BUFFER TREE was measured as a failing class (-197 ps
            // into allocated_mem, ~1000 ps of buffers) - these NUM_SETS x
            // (ASSOC-1) flops were ~40% of what remained on it.
            //
            // WHY IT IS SOUND, not X-luck: a PLRU bit is consulted only
            // when its set is FULL - Compare_Select_Replace picks the
            // first free way while one exists and reads replacement_way
            // only under !has_free. A set becomes full by allocating
            // every way, each alloc updates the tree along its leaf's
            // path, and the leaves' paths together cover every node - so
            // by the first cycle a bit can be read, every bit has been
            // written, and plru_update_f writes a node to a value that
            // does not depend on the old bits. The victim sequence is
            // therefore identical to the reset-to-zero one (the
            // regression must come out digit-identical, and does). The
            // same holds across the TB's between-test resets: the state
            // a set carries in is overwritten by its fill.
            //
            // Sim consequence: replacement_way is X until a set has been
            // filled once; every consumer muxes it behind has_free, so
            // the X never reaches state. The E12 shadow model below is
            // made X-exact (unreset, compared with ===) so it tracks the
            // same X positions instead of failing on them.
            always_ff @(posedge clk) begin
                if (update_valid_r) begin
                    plru_bits[update_set_r] <= next_bits_r;
                end
            end

            // Entry 29(e) (2026-08-25): replacement_way and update_valid_r
            // lose their reset and join the free-running pipeline
            // registers. update_valid is CSR's in_valid (dec_valid),
            // defined 0 from e2, so update_valid_r is 0 from e3 - the
            // plru write it enables cannot fire during the flush cycles.
            // replacement_way is a pure read of plru_bits; since Entry
            // 29(k) that array is reset-free too, and replacement_way is
            // consumed only behind has_free (see the 29(k) note above).
            // Measured reason: replacement_way_reg is a -754 endpoint
            // (128:1 read of plru_bits from rindex_rep_r) - the wall.
            always_ff @(posedge clk) begin
                update_valid_r  <= update_valid;
                update_set_r    <= update_set;
                next_bits_r     <= next_bits;
                replacement_way <= replacement_way_n;
            end

`ifndef SYNTHESIS
            // Entry 12 shadow model (sim-only; every synthesis flow
            // defines SYNTHESIS). shadow_plru applies updates with the
            // OLD timing - immediately, no deferral, no bypass. The
            // deferred machinery is correct iff the real array replays
            // the shadow's history exactly one cycle late; the per-write
            // assert checks each landing value against the shadow, so a
            // lost, reordered, or misdirected update names its cycle.
            // The counters quantify the two behavioral questions instead
            // of guessing: how often the bypass path is actually
            // exercised, and how often the (one-cycle-staler) lookup
            // recommends a different victim than the old timing would
            // have - the number that predicts any miss-rate movement.
            logic [PLRU_BITS-1:0] shadow_plru      [NUM_SETS-1:0];
            logic [PLRU_BITS-1:0] shadow_plru_prev [NUM_SETS-1:0];

            // Counters accumulate across the WHOLE sim and are never
            // cleared: the TB resets between tests, and clearing on rst
            // would wipe every window but the last one. No initializer -
            // Xcelium flags that as a second driver on an always_ff
            // variable (MULAXX); longint is 2-state, so it starts at 0.
            longint unsigned e12_bypass_count;
            longint unsigned e12_sample_count;
            longint unsigned e12_diverge_count;

            // Entry 29(k): the shadow is unreset too, so its X pattern is
            // the real array's (same start, same update function); the
            // per-write assert below compares with === for that reason.
            always_ff @(posedge clk) begin
                if (!rst) begin
                    if (update_valid) begin
                        shadow_plru[update_set] <=
                            plru_update_f(shadow_plru[update_set], update_way);
                    end
                    shadow_plru_prev <= shadow_plru;

                    if (update_valid && bypass_c) begin
                        e12_bypass_count <= e12_bypass_count + 1;
                    end
                    e12_sample_count <= e12_sample_count + 1;
                    if (plru_lookup(shadow_plru[lookup_set]) !=
                        plru_lookup(plru_bits[lookup_set])) begin
                        e12_diverge_count <= e12_diverge_count + 1;
                    end
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && update_valid_r) begin
                    assert (next_bits_r === shadow_plru[update_set_r])
                        else $error("PLRU E12: deferred write %b != shadow %b (set %0d)",
                                    next_bits_r, shadow_plru[update_set_r],
                                    update_set_r);
                end
            end

            final begin
                automatic int mismatches = 0;
                for (int i = 0; i < NUM_SETS; i++) begin
                    if (plru_bits[i] !== shadow_plru_prev[i]) begin
                        mismatches++;
                    end
                end
                $display("PLRU E12 [ASSOC=%0d, %0d sets]: bypass fires=%0d, victim divergence=%0d/%0d cycles, final-state mismatches=%0d",
                         ASSOC, NUM_SETS, e12_bypass_count,
                         e12_diverge_count, e12_sample_count, mismatches);
            end
`endif

        end
    endgenerate

endmodule