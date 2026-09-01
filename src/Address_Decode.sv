// ============================================================
// Address_Decode
//
// CPU address is WORD-addressed.
//   in_addr[WORD_OFFSET_W-1:0] = word offset inside cache line
//
// Carries only:
//   tag, set_id, word_id
//
// Removed:
//   - out_addr
//   - out_line_addr
// ============================================================

module Address_Decode #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int CACHE_BYTES  = 4096,
    parameter int LINE_BYTES   = 16,
    parameter int ASSOC        = 4,
    parameter int CPU_ID_WIDTH = 4,

    parameter int WORD_BYTES     = DATA_WIDTH / 8,
    parameter int WORDS_PER_LINE = LINE_BYTES / WORD_BYTES,
    parameter int NUM_LINES      = CACHE_BYTES / LINE_BYTES,
    parameter int NUM_SETS       = NUM_LINES / ASSOC,

    parameter int WORD_OFFSET_W  = $clog2(WORDS_PER_LINE),

    parameter int SET_INDEX_BITS = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS),
    parameter int SET_INDEX_W    = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS,

    parameter int TAG_WIDTH       = ADDR_WIDTH - WORD_OFFSET_W - SET_INDEX_BITS
)(
    input  logic clk,
    input  logic rst,

    input  logic                    in_valid,
    input  logic                    in_write,
    input  logic [ADDR_WIDTH-1:0]   in_addr,
    input  logic [DATA_WIDTH-1:0]   in_wdata,
    input  logic [CPU_ID_WIDTH-1:0] in_cpu_req_id,

    output logic [SET_INDEX_W-1:0]  array_raddr,


    output logic                    out_valid,
    output logic                    out_write,
    output logic [DATA_WIDTH-1:0]   out_wdata,
    output logic [CPU_ID_WIDTH-1:0] out_cpu_req_id,
    output logic [TAG_WIDTH-1:0]    out_tag,
    output logic [SET_INDEX_W-1:0]  out_set_id,
    output logic [WORD_OFFSET_W-1:0] out_word_id,

    // Entry 25: the elder-patch compares, pre-computed one stage early
    // (Entry 11's pre_line_addr trick). At the edge that moves this
    // request S0->S1, compare it against the request moving S1->S2 -
    // the registered results ARE CSR's e_same_set_c / e_same_word_c /
    // e_tag_match_c, available at cycle start instead of after an
    // S1-side compare. The A8 dcp probe (2026-08-23) showed those
    // compares root a 5-LUT select cone fanning fo=168 into the victim
    // snapshot - the E22/E23-era FPGA A8 wall.
    output logic                    pre_same_set,
    output logic                    pre_same_word,
    output logic                    pre_tag_match
);

    logic accept;

    logic [TAG_WIDTH-1:0]       tag_c;
    logic [SET_INDEX_W-1:0]     set_id_c;
    logic [WORD_OFFSET_W-1:0]   word_id_c;

    assign accept = in_valid;

    assign word_id_c = in_addr[WORD_OFFSET_W-1:0];

    generate
        if (SET_INDEX_BITS == 0) begin : GEN_FULLY_ASSOC
            assign set_id_c = '0;
            assign tag_c    = in_addr[ADDR_WIDTH-1:WORD_OFFSET_W];
        end
        else begin : GEN_INDEXED
            assign set_id_c = in_addr[WORD_OFFSET_W +: SET_INDEX_BITS];
            assign tag_c    = in_addr[ADDR_WIDTH-1 -: TAG_WIDTH];
        end
    endgenerate

    assign array_raddr = set_id_c;

    // Entry 29(e) (2026-08-25): out_valid / out_write lose their reset.
    // "Reset only the roots": in_valid is Cache.inreg_valid_r, which KEEPS
    // its reset and reads 0 from the first reset edge (e1), so out_valid
    // is a defined 0 from e2 - and rst is held five edges. Nothing here
    // is X-luck: the value is forced by the upstream reset, not assumed.
    // Silicon: during the <=4 flush cycles a power-up-random out_valid can
    // only reach consumers whose own state is reset-held (CSR grants land
    // in reset-held arrays, the RS/FIFO pointers are reset-held). rst is
    // no longer read by this module; the port stays for interface
    // stability.
    always_ff @(posedge clk) begin
        out_valid <= accept;
        out_write <= accept && in_write;

        out_wdata      <= in_wdata;
        out_cpu_req_id <= in_cpu_req_id;
        out_tag        <= tag_c;
        out_set_id     <= set_id_c;
        out_word_id    <= word_id_c;

        // Entry 25: NBA reads of out_* on the RHS see the PRE-edge
        // values (the request currently in S1), so each compare is
        // (this request, entering S1) vs (elder, entering S2) -
        // exactly the pair CSR's live compares evaluated. Consumers
        // are gated by the elder's registered write grants, so the
        // dont-care values under bubbles/reset are never used.
        pre_same_set  <= (set_id_c  == out_set_id);
        pre_same_word <= (word_id_c == out_word_id);
        pre_tag_match <= (tag_c     == out_tag);
    end

endmodule

