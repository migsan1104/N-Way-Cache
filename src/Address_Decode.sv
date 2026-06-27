// ============================================================
// Address_Decode
//
// CPU address is WORD-addressed.
//   in_addr[WORD_OFFSET_W-1:0] = word offset inside cache line
//
// Phase 0: Request / Decode
//   - Decode is combinational from cpu_req_addr.
//   - array_raddr is combinational so arrays see the set immediately.
//   - Request metadata is registered when in_valid && in_ready.
//
// Phase 1: Array Read
//   - Arrays read using array_raddr.
//   - Registered decode outputs align with returned array data.
// ============================================================

module Address_Decode #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int CACHE_BYTES  = 1024,
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

    parameter int TAG_WIDTH       = ADDR_WIDTH - WORD_OFFSET_W - SET_INDEX_BITS,
    parameter int LINE_ADDR_WIDTH = ADDR_WIDTH - WORD_OFFSET_W
)(
    input  logic clk,
    input  logic rst,

    input  logic                    in_valid,
    input  logic                    in_ready,
    input  logic                    in_write,
    input  logic [ADDR_WIDTH-1:0]   in_addr,
    input  logic [DATA_WIDTH-1:0]   in_wdata,
    input  logic [CPU_ID_WIDTH-1:0] in_cpu_req_id,

    output logic [SET_INDEX_W-1:0]  array_raddr,

    output logic                    out_valid,
    output logic                    out_write,
    output logic [ADDR_WIDTH-1:0]   out_addr,
    output logic [DATA_WIDTH-1:0]   out_wdata,
    output logic [CPU_ID_WIDTH-1:0] out_cpu_req_id,
    output logic [TAG_WIDTH-1:0]    out_tag,
    output logic [SET_INDEX_W-1:0]  out_set_id,
    output logic [WORD_OFFSET_W-1:0] out_word_id,
    output logic [LINE_ADDR_WIDTH-1:0] out_line_addr
);

    logic accept;

    logic [TAG_WIDTH-1:0]           tag_c;
    logic [SET_INDEX_W-1:0]         set_id_c;
    logic [WORD_OFFSET_W-1:0]       word_id_c;
    logic [LINE_ADDR_WIDTH-1:0]     line_addr_c;

    assign accept = in_valid && in_ready;

    assign word_id_c   = in_addr[WORD_OFFSET_W-1:0];
    assign line_addr_c = in_addr[ADDR_WIDTH-1:WORD_OFFSET_W];

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

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid      <= 1'b0;
            out_write      <= 1'b0;
            out_addr       <= '0;
            out_wdata      <= '0;
            out_cpu_req_id <= '0;
            out_tag        <= '0;
            out_set_id     <= '0;
            out_word_id    <= '0;
            out_line_addr  <= '0;
        end
        else begin
            out_valid      <= accept;
            out_write      <= accept && in_write;
            out_addr       <= in_addr;
            out_wdata      <= in_wdata;
            out_cpu_req_id <= in_cpu_req_id;
            out_tag        <= tag_c;
            out_set_id     <= set_id_c;
            out_word_id    <= word_id_c;
            out_line_addr  <= line_addr_c;
        end
    end

endmodule