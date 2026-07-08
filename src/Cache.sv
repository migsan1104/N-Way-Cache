// ============================================================
// Parameterized set-associative cache
//
// Reduced metadata path:
//   - carry tag/set/word only
//   - removed dec_addr / cmp_addr / miss_select_addr
//   - removed dec_line_addr / cmp_line_addr / miss_select_line_addr
//   - reconstruct line_addr only at MSHR allocation
// ============================================================

module Cache #(
    parameter int CACHE_BYTES   = 4096,
    parameter int ASSOC         = 4,

    localparam int ADDR_WIDTH    = 32,
    localparam int DATA_WIDTH    = 32,
    localparam int CPU_ID_WIDTH  = 4,
    localparam int MSHR_ID_WIDTH = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic                      cpu_req_valid,
    output logic                      cpu_req_ready,

    input  logic                      cpu_req_write,
    input  logic [ADDR_WIDTH-1:0]     cpu_req_addr,
    input  logic [DATA_WIDTH-1:0]     cpu_req_wdata,
    input  logic [CPU_ID_WIDTH-1:0]   cpu_req_id,

    output logic                      cpu_resp_valid,
    input  logic                      cpu_resp_ready,

    output logic                      cpu_resp_hit,
    output logic [DATA_WIDTH-1:0]     cpu_resp_rdata,
    output logic [CPU_ID_WIDTH-1:0]   cpu_resp_id,

    output logic                      mem_req_valid,
    output logic                      mem_req_write,
    output logic [ADDR_WIDTH-1:0]     mem_req_addr,
    output logic [DATA_WIDTH-1:0]     mem_req_wdata,
    output logic [MSHR_ID_WIDTH-1:0]  mem_req_id,

    input  logic                      mem_resp_valid,
    output logic                      mem_resp_ready,

    input  logic [MSHR_ID_WIDTH-1:0]  mem_resp_id,
    input  logic [DATA_WIDTH-1:0]     mem_resp_rdata
);

    localparam int WORDS_PER_LINE  = 4;
    localparam int LINE_BYTES      = 16;
    localparam int LINE_WIDTH      = 128;

    localparam int NUM_LINES       = CACHE_BYTES / LINE_BYTES;
    localparam int NUM_SETS        = NUM_LINES / ASSOC;

    localparam int WORD_OFFSET_W   = 2;

    localparam int SET_INDEX_BITS  = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS);
    localparam int SET_INDEX_W     = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS;

    localparam int TAG_WIDTH       = ADDR_WIDTH - WORD_OFFSET_W - SET_INDEX_BITS;
    localparam int LINE_ADDR_WIDTH = ADDR_WIDTH - WORD_OFFSET_W;

    localparam int WAY_INDEX_W     = (ASSOC <= 1) ? 1 : $clog2(ASSOC);
    localparam int MSHR_COUNT      = 4;

    logic [SET_INDEX_W-1:0]       array_rindex;

    logic                         dec_valid;
    logic                         dec_write;
    logic [DATA_WIDTH-1:0]        dec_wdata;
    logic [CPU_ID_WIDTH-1:0]      dec_cpu_req_id;
    logic [TAG_WIDTH-1:0]         dec_tag;
    logic [SET_INDEX_W-1:0]       dec_set_id;
    logic [WORD_OFFSET_W-1:0]     dec_word_id;

    logic [LINE_WIDTH-1:0]        way_line       [ASSOC];
    logic [TAG_WIDTH-1:0]         way_tag        [ASSOC];
    logic                         way_allocated  [ASSOC];
    logic                         way_dirty      [ASSOC];
    logic [WORDS_PER_LINE-1:0]    way_word_valid [ASSOC];

    logic                         cmp_valid;
    logic                         cmp_write;
    logic                         cmp_hit;
    logic                         cmp_miss;
    logic [DATA_WIDTH-1:0]        cmp_wdata;
    logic [DATA_WIDTH-1:0]        cmp_rdata;
    logic [CPU_ID_WIDTH-1:0]      cmp_cpu_req_id;
    logic [TAG_WIDTH-1:0]         cmp_tag;
    logic [SET_INDEX_W-1:0]       cmp_set_id;
    logic [WORD_OFFSET_W-1:0]     cmp_word_id;

    logic [WAY_INDEX_W-1:0]       cmp_miss_way;

    logic                         miss_select_valid;
    logic                         miss_select_write;
    logic [DATA_WIDTH-1:0]        miss_select_wdata;
    logic [CPU_ID_WIDTH-1:0]      miss_select_cpu_req_id;
    logic [TAG_WIDTH-1:0]         miss_select_tag;
    logic [SET_INDEX_W-1:0]       miss_select_set_id;
    logic [WORD_OFFSET_W-1:0]     miss_select_word_id;
    logic [LINE_ADDR_WIDTH-1:0]   miss_select_line_addr;
    logic [WAY_INDEX_W-1:0]       miss_select_way;

    logic                         miss_select_victim_dirty;
    logic [TAG_WIDTH-1:0]         miss_select_victim_tag;
    logic [LINE_WIDTH-1:0]        miss_select_victim_line;
    logic [WORDS_PER_LINE-1:0]    miss_select_victim_word_valid;


    logic [ASSOC-1:0]             alloc_wen;
    logic [SET_INDEX_W-1:0]       alloc_waddr;
    logic [TAG_WIDTH-1:0]         alloc_tag;

  
    logic [ASSOC-1:0]             cpu_write_wen;
    logic [ASSOC-1:0]             cpu_write_replace;
   
    logic [SET_INDEX_W-1:0]       cpu_write_set_id;
    logic [WORD_OFFSET_W-1:0]     cpu_write_word_id;
    logic [DATA_WIDTH-1:0]        cpu_write_wdata;

    logic [WAY_INDEX_W-1:0]       replacement_way;
    logic                         replacement_update_valid;
    logic [SET_INDEX_W-1:0]       replacement_update_set;
    logic [WAY_INDEX_W-1:0]       replacement_update_way;

    logic                         mshr_alloc_ready;
    

    logic [MSHR_COUNT-1:0]        mshr_req_valid;
    logic [MSHR_COUNT-1:0]        mshr_req_pending;
    logic [MSHR_COUNT-1:0]        mshr_req_write;
    logic [ADDR_WIDTH-1:0]        mshr_req_addr  [MSHR_COUNT];
    logic [DATA_WIDTH-1:0]        mshr_req_wdata [MSHR_COUNT];
    logic [MSHR_ID_WIDTH-1:0]     mshr_req_id    [MSHR_COUNT];
    logic [MSHR_COUNT-1:0]        mshr_issued;

    logic                         miss_cpu_resp_valid;
    logic [CPU_ID_WIDTH-1:0]      miss_cpu_resp_id;
    logic [DATA_WIDTH-1:0]        miss_cpu_resp_data;
    logic [DATA_WIDTH-1:0]        delayed_miss_data;

    logic                         refill_wen;
    logic [SET_INDEX_W-1:0]       refill_set_id;
    logic [TAG_WIDTH-1:0]         refill_tag;
    logic [WAY_INDEX_W-1:0]       refill_way;
    logic [LINE_WIDTH-1:0]        refill_line;

    logic [ASSOC-1:0]             refill_way_wen;
    logic                         hit_resp_valid;
    logic                         miss_resp_valid;
    logic                         hit_resp_ready;
   

    assign cpu_req_ready = hit_resp_ready && mshr_alloc_ready;

    assign miss_select_line_addr = {miss_select_tag, miss_select_set_id};

    Address_Decode #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .CACHE_BYTES  (CACHE_BYTES),
        .LINE_BYTES   (LINE_BYTES),
        .ASSOC        (ASSOC),
        .CPU_ID_WIDTH (CPU_ID_WIDTH)
    ) ADDR_DECODE (
        .clk            (clk),
        .rst            (rst),

        .in_valid       (cpu_req_valid),
        .in_write       (cpu_req_write),
        .in_addr        (cpu_req_addr),
        .in_wdata       (cpu_req_wdata),
        .in_cpu_req_id  (cpu_req_id),

        .array_raddr    (array_rindex),

        .out_valid      (dec_valid),
        .out_write      (dec_write),
        .out_wdata      (dec_wdata),
        .out_cpu_req_id (dec_cpu_req_id),
        .out_tag        (dec_tag),
        .out_set_id     (dec_set_id),
        .out_word_id    (dec_word_id)
    );

    always_comb begin
        refill_way_wen = '0;

        if (refill_wen) begin
            refill_way_wen[refill_way] = 1'b1;
        end
    end

    genvar way_gen;

    generate
        for (way_gen = 0; way_gen < ASSOC; way_gen++) begin : GEN_WAYS

            Flag_Tag_Data_Array #(
                .DATA_WIDTH     (DATA_WIDTH),
                .LINE_WIDTH     (LINE_WIDTH),
                .TAG_WIDTH      (TAG_WIDTH),
                .DEPTH          (NUM_SETS),
                .SET_INDEX_W    (SET_INDEX_W),
                .WORDS_PER_LINE (WORDS_PER_LINE),
                .WORD_OFFSET_W  (WORD_OFFSET_W)
            ) FLAG_TAG_DATA_ARRAY (
                .clk             (clk),
                .rst             (rst),

                .raddr           (array_rindex),

                .rline           (way_line[way_gen]),
                .rtag            (way_tag[way_gen]),
                .allocated       (way_allocated[way_gen]),
                .dirty           (way_dirty[way_gen]),
                .word_valid      (way_word_valid[way_gen]),

                .refill_wen      (refill_way_wen[way_gen]),
                .refill_waddr    (refill_set_id),
                .refill_tag      (refill_tag),
                .refill_line     (refill_line),

                .alloc_wen       (alloc_wen[way_gen]),
                .alloc_waddr     (alloc_waddr),
                .alloc_tag       (alloc_tag),

                .cpu_word_wen    (cpu_write_wen[way_gen]),
                .cpu_replace     (cpu_write_replace[way_gen]),
                .cpu_waddr       (cpu_write_set_id),
                .cpu_word_id     (cpu_write_word_id),
                .cpu_wdata       (cpu_write_wdata)
            );

        end
    endgenerate

    Replacement #(
        .ASSOC       (ASSOC),
        .NUM_SETS    (NUM_SETS),
        .WAY_INDEX_W (WAY_INDEX_W),
        .SET_INDEX_W (SET_INDEX_W)
    ) REPLACEMENT (
        .clk             (clk),
        .rst             (rst),

        .lookup_set      (dec_set_id),
        .replacement_way (replacement_way),

        .update_valid    (replacement_update_valid),
        .update_set      (replacement_update_set),
        .update_way      (replacement_update_way)
    );

    Compare_Select_Replace #(
        .ASSOC           (ASSOC),
        .DATA_WIDTH      (DATA_WIDTH),
        .LINE_WIDTH      (LINE_WIDTH),
        .TAG_WIDTH       (TAG_WIDTH),
       
        .CPU_ID_WIDTH    (CPU_ID_WIDTH),
        .SET_INDEX_W     (SET_INDEX_W),
        .WORD_OFFSET_W   (WORD_OFFSET_W),
        
        .WORDS_PER_LINE  (WORDS_PER_LINE),
        .WAY_INDEX_W     (WAY_INDEX_W)
    ) COMPARE_SELECT_REPLACE (
        .clk                      (clk),
        .rst                      (rst),

        .in_valid                 (dec_valid),
        .in_write                 (dec_write),
        .in_wdata                 (dec_wdata),
        .in_cpu_req_id            (dec_cpu_req_id),
        .in_tag                   (dec_tag),
        .in_set_id                (dec_set_id),
        .in_word_id               (dec_word_id),

        .way_line                 (way_line),
        .way_tag                  (way_tag),
        .way_allocated            (way_allocated),
        .way_dirty                (way_dirty),
        .way_word_valid           (way_word_valid),

        .replacement_way          (replacement_way),

        .out_valid                (cmp_valid),
        .out_write                (cmp_write),
        .out_hit                  (cmp_hit),
        .out_miss                 (cmp_miss),

        .out_wdata                (cmp_wdata),
        .out_rdata                (cmp_rdata),
        .out_cpu_req_id           (cmp_cpu_req_id),
        .out_tag                  (cmp_tag),
        .out_set_id               (cmp_set_id),
        .out_word_id              (cmp_word_id),

        .out_miss_way             (cmp_miss_way),

        .out_victim_dirty         (miss_select_victim_dirty),
        .out_victim_tag           (miss_select_victim_tag),
        .out_victim_line          (miss_select_victim_line),
        .out_victim_word_valid    (miss_select_victim_word_valid),


        .alloc_wen                (alloc_wen),
        .alloc_waddr              (alloc_waddr),
        .alloc_tag                (alloc_tag),

     
        .cpu_write_wen            (cpu_write_wen),
        .cpu_write_replace        (cpu_write_replace),
        
        .cpu_write_set_id         (cpu_write_set_id),
        .cpu_write_word_id        (cpu_write_word_id),
        .cpu_write_wdata          (cpu_write_wdata),

        .replacement_update_valid (replacement_update_valid),
        .replacement_update_set   (replacement_update_set),
        .replacement_update_way   (replacement_update_way)
    );

    assign miss_select_valid      = cmp_valid && cmp_miss;
    assign miss_select_write      = cmp_write;
    assign miss_select_wdata      = cmp_wdata;
    assign miss_select_cpu_req_id = cmp_cpu_req_id;
    assign miss_select_tag        = cmp_tag;
    assign miss_select_set_id     = cmp_set_id;
    assign miss_select_word_id    = cmp_word_id;
    assign miss_select_way        = cmp_miss_way;

    Delay_r #(
        .D_WIDTH(DATA_WIDTH),
        .DELAY  (5)
    ) MISS_RESP_DATA_DELAY (
        .clk  (clk),
        .rst  (rst),
        .din  (mem_resp_rdata),
        .dout (delayed_miss_data)
    );

    MSHR_File #(
        .ADDR_WIDTH       (ADDR_WIDTH),
        .LINE_ADDR_WIDTH  (LINE_ADDR_WIDTH),
        .SET_INDEX_W      (SET_INDEX_W),
        .WORD_OFFSET_W    (WORD_OFFSET_W),
        .TAG_WIDTH        (TAG_WIDTH),
        .WAY_INDEX_W      (WAY_INDEX_W),
        .DATA_WIDTH       (DATA_WIDTH),
        .LINE_WIDTH       (LINE_WIDTH),
        .CPU_ID_WIDTH     (CPU_ID_WIDTH),
        .MSHR_ID_WIDTH    (MSHR_ID_WIDTH),
        .MISSQ_DEPTH      (16),
        .MSHR_AF          (3),
        .MAX_WAITERS      (WORDS_PER_LINE)
    ) MSHR_FILE (
        .clk                  (clk),
        .rst                  (rst),

        .alloc_valid          (miss_select_valid),
        .alloc_ready          (mshr_alloc_ready),

        .alloc_line_addr      (miss_select_line_addr),
        .alloc_word_id        (miss_select_word_id),
        .alloc_way            (miss_select_way),

        .alloc_write          (miss_select_write),
        .alloc_wdata          (miss_select_wdata),
        .alloc_cpu_req_id     (miss_select_cpu_req_id),

        .alloc_victim_dirty   (miss_select_victim_dirty),
        .alloc_victim_tag     (miss_select_victim_tag),
        .alloc_victim_line    (miss_select_victim_line),
        .alloc_victim_word_valid (miss_select_victim_word_valid),

    

        .issue_done           (mshr_issued),

        .mem_resp_valid       (mem_resp_valid),
        .mem_resp_id          (mem_resp_id),
        .mem_resp_rdata       (mem_resp_rdata),

        .delayed_miss_data    (delayed_miss_data),

        .miss_valid           (miss_cpu_resp_valid),
        .miss_data            (miss_cpu_resp_data),
        .miss_id              (miss_cpu_resp_id),

        .refill_wen           (refill_wen),
        .refill_set_id        (refill_set_id),
        .refill_tag           (refill_tag),
        .refill_way           (refill_way),
        .refill_line          (refill_line),

        .issue_pending        (mshr_req_pending),

        .req_valid            (mshr_req_valid),
        .req_write            (mshr_req_write),
        .req_addr             (mshr_req_addr),
        .req_wdata            (mshr_req_wdata),
        .req_id               (mshr_req_id)
    );

    MSHR_Request_Arbiter #(
        .MSHR_COUNT    (MSHR_COUNT),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .MSHR_ID_WIDTH (MSHR_ID_WIDTH)
    ) MSHR_REQ_ARBITER (
        .clk           (clk),
        .rst           (rst),

        .req_valid     (mshr_req_valid),
        .req_pending   (mshr_req_pending),
        .req_write     (mshr_req_write),
        .req_addr      (mshr_req_addr),
        .req_wdata     (mshr_req_wdata),
        .req_id        (mshr_req_id),

        .issued        (mshr_issued),

        .mem_req_valid (mem_req_valid),
        .mem_req_write (mem_req_write),
        .mem_req_addr  (mem_req_addr),
        .mem_req_wdata (mem_req_wdata),
        .mem_req_id    (mem_req_id)
    );

    assign mem_resp_ready = 1'b1;

    assign hit_resp_valid  = cmp_valid && cmp_hit;
    assign miss_resp_valid = miss_cpu_resp_valid;

    Response_Unit #(
        .DATA_WIDTH   (DATA_WIDTH),
        .CPU_ID_WIDTH (CPU_ID_WIDTH),
        .FIFO_DEPTH   (8),
        .FIFO_DEPTH_MISS(8)
    ) RESPONSE_UNIT (
        .clk            (clk),
        .rst            (rst),

        .hit_valid      (hit_resp_valid),
        .hit_ready      (hit_resp_ready),
        .hit_data       (cmp_rdata),
        .hit_id         (cmp_cpu_req_id),

        .miss_valid     (miss_resp_valid),

        .miss_data      (miss_cpu_resp_data),
        .miss_id        (miss_cpu_resp_id),

        .cpu_resp_valid (cpu_resp_valid),
        .cpu_resp_ready (cpu_resp_ready),
        .cpu_resp_hit   (cpu_resp_hit),
        .cpu_resp_rdata (cpu_resp_rdata),
        .cpu_resp_id    (cpu_resp_id)
    );

endmodule
