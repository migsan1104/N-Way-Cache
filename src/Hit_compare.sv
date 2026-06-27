// ============================================================
// Hit_Compare
//
// Phase 2: Compare / Select
//   Inputs:
//     - registered decoded request from Address_Decode
//     - array outputs from Data/Tag/Flag arrays
//
//   Hit rules:
//     line_match = allocated && tag_match
//     write_hit  = line_match
//     read_hit   = line_match && word_valid[word_id]
//
// Phase 3: Select / Miss_Select
//   Outputs are registered here.
//   Cache.sv uses these outputs directly for hit responses and miss allocation.
// ============================================================

module Hit_Compare #(
    parameter int ASSOC           = 4,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int TAG_WIDTH       = 24,
    parameter int ADDR_WIDTH      = 32,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int LINE_ADDR_WIDTH = 26,
    parameter int WORDS_PER_LINE  = 4,
    parameter int WAY_INDEX_W     = (ASSOC <= 1) ? 1 : $clog2(ASSOC)
)(
    input  logic clk,
    input  logic rst,

    input  logic                       in_valid,
    input  logic                       in_write,
    input  logic [ADDR_WIDTH-1:0]      in_addr,
    input  logic [DATA_WIDTH-1:0]      in_wdata,
    input  logic [CPU_ID_WIDTH-1:0]    in_cpu_req_id,
    input  logic [TAG_WIDTH-1:0]       in_tag,
    input  logic [SET_INDEX_W-1:0]     in_set_id,
    input  logic [WORD_OFFSET_W-1:0]   in_word_id,
    input  logic [LINE_ADDR_WIDTH-1:0] in_line_addr,

    input  logic [LINE_WIDTH-1:0]      way_line       [ASSOC],
    input  logic [TAG_WIDTH-1:0]       way_tag        [ASSOC],
    input  logic                       way_allocated  [ASSOC],
    input  logic                       way_dirty      [ASSOC],
    input  logic [WORDS_PER_LINE-1:0]  way_word_valid [ASSOC],

    output logic                       out_valid,
    output logic                       out_write,
    output logic                       out_hit,
    output logic                       out_miss,

    output logic [ADDR_WIDTH-1:0]      out_addr,
    output logic [DATA_WIDTH-1:0]      out_wdata,
    output logic [DATA_WIDTH-1:0]      out_rdata,
    output logic [CPU_ID_WIDTH-1:0]    out_cpu_req_id,
    output logic [TAG_WIDTH-1:0]       out_tag,
    output logic [SET_INDEX_W-1:0]     out_set_id,
    output logic [WORD_OFFSET_W-1:0]   out_word_id,
    output logic [LINE_ADDR_WIDTH-1:0] out_line_addr,

    output logic [WAY_INDEX_W-1:0]     out_hit_way,

    output logic [LINE_WIDTH-1:0]      out_way_line       [ASSOC],
    output logic [TAG_WIDTH-1:0]       out_way_tag        [ASSOC],
    output logic                       out_way_allocated  [ASSOC],
    output logic                       out_way_dirty      [ASSOC],
    output logic [WORDS_PER_LINE-1:0]  out_way_word_valid [ASSOC]
);

    logic [ASSOC-1:0]       line_match_c;
    logic [ASSOC-1:0]       way_hit_c;
    logic [DATA_WIDTH-1:0]  way_word_c [ASSOC];

    logic [WAY_INDEX_W-1:0] hit_way_c;
    logic [DATA_WIDTH-1:0]  selected_word_c;

    always_comb begin
        for (int i = 0; i < ASSOC; i++) begin
            way_word_c[i] =
                way_line[i][in_word_id * DATA_WIDTH +: DATA_WIDTH];

            line_match_c[i] =
                in_valid &&
                way_allocated[i] &&
                (way_tag[i] == in_tag);

            way_hit_c[i] =
                in_write
                    ? line_match_c[i]
                    : line_match_c[i] && way_word_valid[i][in_word_id];
        end
    end

    always_comb begin
        hit_way_c       = '0;
        selected_word_c = '0;

        for (int i = 0; i < ASSOC; i++) begin
            if (way_hit_c[i]) begin
                hit_way_c       = WAY_INDEX_W'(i);
                selected_word_c = way_word_c[i];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid      <= 1'b0;
            out_write      <= 1'b0;
            out_hit        <= 1'b0;
            out_miss       <= 1'b0;

            out_addr       <= '0;
            out_wdata      <= '0;
            out_rdata      <= '0;
            out_cpu_req_id <= '0;
            out_tag        <= '0;
            out_set_id     <= '0;
            out_word_id    <= '0;
            out_line_addr  <= '0;
            out_hit_way    <= '0;

            for (int i = 0; i < ASSOC; i++) begin
                out_way_line[i]       <= '0;
                out_way_tag[i]        <= '0;
                out_way_allocated[i]  <= 1'b0;
                out_way_dirty[i]      <= 1'b0;
                out_way_word_valid[i] <= '0;
            end
        end
        else begin
            out_valid      <= in_valid;
            out_write      <= in_write;
            out_hit        <= |way_hit_c;
            out_miss       <= in_valid && !(|way_hit_c);

            out_addr       <= in_addr;
            out_wdata      <= in_wdata;
            out_rdata      <= selected_word_c;
            out_cpu_req_id <= in_cpu_req_id;
            out_tag        <= in_tag;
            out_set_id     <= in_set_id;
            out_word_id    <= in_word_id;
            out_line_addr  <= in_line_addr;
            out_hit_way    <= hit_way_c;

            for (int i = 0; i < ASSOC; i++) begin
                out_way_line[i]       <= way_line[i];
                out_way_tag[i]        <= way_tag[i];
                out_way_allocated[i]  <= way_allocated[i];
                out_way_dirty[i]      <= way_dirty[i];
                out_way_word_valid[i] <= way_word_valid[i];
            end
        end
    end

endmodule