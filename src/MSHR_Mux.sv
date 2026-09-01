module MSHR_Mux #(
    parameter int MSHR_COUNT  = 4,
    parameter int SET_INDEX_W = 4,
    parameter int TAG_WIDTH   = 16,
    parameter int WAY_INDEX_W = 2,
    parameter int LINE_WIDTH  = 128
)(
    input  logic clk,
    input  logic rst,

    input  logic [MSHR_COUNT-1:0]  entry_refill_wen,
    input  logic [SET_INDEX_W-1:0] entry_set_id    [MSHR_COUNT],
    input  logic [TAG_WIDTH-1:0]   entry_tag       [MSHR_COUNT],
    input  logic [WAY_INDEX_W-1:0] entry_way       [MSHR_COUNT],
    input  logic [LINE_WIDTH-1:0]  entry_fill_line [MSHR_COUNT],

    output logic                   refill_wen,
    output logic [SET_INDEX_W-1:0] refill_set_id,
    output logic [TAG_WIDTH-1:0]   refill_tag,
    output logic [WAY_INDEX_W-1:0] refill_way,
    output logic [LINE_WIDTH-1:0]  refill_line
);

    logic found;
    logic [$clog2(MSHR_COUNT)-1:0] sel;

    always_comb begin
        found = 1'b0;
        sel   = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (entry_refill_wen[i] && !found) begin
                found = 1'b1;
                sel   = i[$clog2(MSHR_COUNT)-1:0];
            end
        end
    end

    // Entry 29(b) (2026-08-24): control and payload split.
    //
    // Entry 29(d) (2026-08-24): refill_wen's reset is REMOVED.
    // E29(b) kept it as "the VALID must read no-refill from cycle
    // one". That premise does not hold: `found` is a priority-OR of the
    // MSHR entries' refill_wen_r, every one of which keeps its own
    // reset, so `found` is a defined 0 at the FIRST clock edge - four
    // cycles before the TB deasserts rst (rst is held 5 edges).
    //
    // X-CONSUMER REVIEW, per the standing E29 caveat - NOT X-luck. The
    // only X window is time-0 to the first posedge, during which no
    // edge occurs, so nothing can capture it. Every path from here to
    // state is additionally gated by a register that KEEPS its reset:
    //   FTDA staging  -> refill_stage_v_r  (reset, forced 0 while rst)
    //   FTDA array wr -> refill_bank_pending_r -> refill_grant_c (same)
    //   Cache.sv      -> refill_way_wen is combinational off refill_wen,
    //                    and lands on FTDA's port gated by the two above
    // The staging registers it feeds are themselves already reset-free
    // (E29(a)), so an X there is not new exposure.
    //
    // Census context: refill_wen is the #1 startpoint, launching 388 of
    // the 1000 worst paths - but it already mapped to dfxtp_4 with NO
    // reset pin, so this is expected to be area/discipline, not Fmax.
    // Those 388 paths are a FANOUT problem, not a reset problem.
    always_ff @(posedge clk) begin
        refill_wen <= found;
    end

    // The payload is RESET-FREE and lives in its own block. Keeping it
    // in the guarded block's else put rst in the load-enable cone of
    // 150 flops (128b line + tag + set + way) for nothing - the same
    // pattern E29(a) fixed in Flag_Tag_Data_Array, and the last
    // instance of it in the design.
    //
    // Every consumer is gated by refill_wen, which keeps its reset:
    //   Flag_Tag_Data_Array : `if (refill_wen)` captures refill_line /
    //                         refill_tag / refill_waddr into its own
    //                         (already reset-free) staging registers
    //   Cache.sv            : `if (refill_wen) refill_way_wen[refill_way]`
    // So an X payload out of reset is never captured and never decoded.
    // FTDA already documents and guards the one place this is visible
    // in simulation (refill_set_idx_r starts X before the first
    // refill - see wv_drain_hide_r).
    always_ff @(posedge clk) begin
        refill_line   <= entry_fill_line[sel];
        refill_set_id <= entry_set_id[sel];
        refill_tag    <= entry_tag[sel];
        refill_way    <= entry_way[sel];
    end

endmodule
