// ============================================================
// Compare_Select_Replace
// ============================================================

module Compare_Select_Replace #(
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

    input  logic [WAY_INDEX_W-1:0]     replacement_way,

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
    output logic [WAY_INDEX_W-1:0]     out_miss_way,

    output logic                       out_victim_valid,
    output logic                       out_victim_dirty,
    output logic [TAG_WIDTH-1:0]       out_victim_tag,
    output logic [LINE_WIDTH-1:0]      out_victim_line,

    output logic                       regular_found,
    output logic [WAY_INDEX_W-1:0]     regular_way,

    output logic [ASSOC-1:0]           alloc_wen,
    output logic [SET_INDEX_W-1:0]     alloc_waddr,
    output logic [TAG_WIDTH-1:0]       alloc_tag,

    output logic                       cpu_write_valid,
    output logic [ASSOC-1:0]           cpu_write_wen,
    output logic [ASSOC-1:0]           cpu_write_replace,
    output logic [WAY_INDEX_W-1:0]     cpu_write_way,
    output logic [SET_INDEX_W-1:0]     cpu_write_set_id,
    output logic [WORD_OFFSET_W-1:0]   cpu_write_word_id,
    output logic [DATA_WIDTH-1:0]      cpu_write_wdata,

    output logic                       replacement_update_valid,
    output logic [SET_INDEX_W-1:0]     replacement_update_set,
    output logic [WAY_INDEX_W-1:0]     replacement_update_way
);

    logic [ASSOC-1:0]      line_match_c;
    logic [ASSOC-1:0]      way_hit_c;
    logic [DATA_WIDTH-1:0] way_word_c [ASSOC];

    logic [WAY_INDEX_W-1:0] hit_way_c;
    logic [DATA_WIDTH-1:0]  selected_word_c;

    logic line_found_c;
    logic [WAY_INDEX_W-1:0] line_way_c;

    logic hit_c;
    logic miss_c;

    logic regular_found_c;
    logic [WAY_INDEX_W-1:0] regular_way_c;
    logic [WAY_INDEX_W-1:0] miss_way_c;

    logic cpu_write_valid_c;
    logic [WAY_INDEX_W-1:0] cpu_write_way_c;
    logic cpu_write_replace_c;

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

    always_comb begin
        line_found_c = 1'b0;
        line_way_c   = '0;

        for (int i = 0; i < ASSOC; i++) begin
            if (line_match_c[i]) begin
                line_found_c = 1'b1;
                line_way_c   = WAY_INDEX_W'(i);
            end
        end
    end

    assign hit_c  = |way_hit_c;
    assign miss_c = in_valid && !hit_c;

    always_comb begin
        regular_found_c = 1'b0;
        regular_way_c   = '0;

        for (int i = 0; i < ASSOC; i++) begin
            if (!way_allocated[i] && !regular_found_c) begin
                regular_found_c = 1'b1;
                regular_way_c   = WAY_INDEX_W'(i);
            end
        end
    end

    assign miss_way_c =
        line_found_c    ? line_way_c :
        regular_found_c ? regular_way_c :
                          replacement_way;

    always_comb begin
        alloc_wen           = '0;

        cpu_write_wen       = '0;
        cpu_write_replace   = '0;

        cpu_write_valid_c   = 1'b0;
        cpu_write_way_c     = '0;
        cpu_write_replace_c = 1'b0;

        if (in_valid && in_write && hit_c) begin
            cpu_write_valid_c = 1'b1;
            cpu_write_way_c   = hit_way_c;
        end
        else if (in_valid && miss_c) begin
            if (!line_found_c) begin
                alloc_wen[miss_way_c] = 1'b1;
            end

            if (in_write) begin
                cpu_write_valid_c   = 1'b1;
                cpu_write_way_c     = miss_way_c;
                cpu_write_replace_c = !line_found_c;
            end
        end

        if (cpu_write_valid_c) begin
            cpu_write_wen[cpu_write_way_c] = 1'b1;

            if (cpu_write_replace_c) begin
                cpu_write_replace[cpu_write_way_c] = 1'b1;
            end
        end
    end

    assign alloc_waddr       = in_set_id;
    assign alloc_tag         = in_tag;

    assign cpu_write_valid   = cpu_write_valid_c;
    assign cpu_write_way     = cpu_write_way_c;
    assign cpu_write_set_id  = in_set_id;
    assign cpu_write_word_id = in_word_id;
    assign cpu_write_wdata   = in_wdata;

    assign replacement_update_valid = in_valid;
    assign replacement_update_set   = in_set_id;
    assign replacement_update_way   = hit_c ? hit_way_c : miss_way_c;

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid        <= 1'b0;
            out_write        <= 1'b0;
            out_hit          <= 1'b0;
            out_miss         <= 1'b0;

            out_addr         <= '0;
            out_wdata        <= '0;
            out_rdata        <= '0;
            out_cpu_req_id   <= '0;
            out_tag          <= '0;
            out_set_id       <= '0;
            out_word_id      <= '0;
            out_line_addr    <= '0;

            out_hit_way      <= '0;
            out_miss_way     <= '0;

            out_victim_valid <= 1'b0;
            out_victim_dirty <= 1'b0;
            out_victim_tag   <= '0;
            out_victim_line  <= '0;

            regular_found    <= 1'b0;
            regular_way      <= '0;
        end
        else begin
            out_valid        <= in_valid;
            out_write        <= in_write;
            out_hit          <= hit_c;
            out_miss         <= miss_c;

            out_addr         <= in_addr;
            out_wdata        <= in_wdata;
            out_rdata        <= selected_word_c;
            out_cpu_req_id   <= in_cpu_req_id;
            out_tag          <= in_tag;
            out_set_id       <= in_set_id;
            out_word_id      <= in_word_id;
            out_line_addr    <= in_line_addr;

            out_hit_way      <= hit_way_c;
            out_miss_way     <= miss_way_c;

            out_victim_valid <= (!line_found_c) && way_allocated[miss_way_c];
            out_victim_dirty <= (!line_found_c) && way_dirty[miss_way_c];
            out_victim_tag   <= way_tag[miss_way_c];
            out_victim_line  <= way_line[miss_way_c];

            regular_found    <= regular_found_c;
            regular_way      <= regular_way_c;
        end
    end

endmodule