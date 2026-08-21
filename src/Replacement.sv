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

    // Same lookup, pre-register (Entry 10): the S0 write-grant
    // precompute needs the victim for the request currently in S0 -
    // exactly the value replacement_way will hold next cycle.
    output logic [WAY_INDEX_W-1:0] lookup_way_c,

    // PLRU state update
    input  logic                   update_valid,
    input  logic [SET_INDEX_W-1:0] update_set,
    input  logic [WAY_INDEX_W-1:0] update_way
);

    generate
        if (ASSOC == 1) begin : GEN_DIRECT_MAPPED

            assign lookup_way_c = '0;

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

            assign lookup_way_c = replacement_way_n;

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int i = 0; i < NUM_SETS; i++) begin
                        plru_bits[i] <= '0;
                    end

                    replacement_way <= '0;
                    update_valid_r  <= 1'b0;
                end else begin
                    update_valid_r <= update_valid;
                    update_set_r   <= update_set;
                    next_bits_r    <= next_bits;

                    if (update_valid_r) begin
                        plru_bits[update_set_r] <= next_bits_r;
                    end

                    replacement_way <= replacement_way_n;
                end
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

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int i = 0; i < NUM_SETS; i++) begin
                        shadow_plru[i]      <= '0;
                        shadow_plru_prev[i] <= '0;
                    end
                end else begin
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
                    assert (next_bits_r == shadow_plru[update_set_r])
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