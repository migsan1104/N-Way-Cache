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
    parameter bit EN_SRAM_MACRO = 1'b0,

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
   
    logic [SET_INDEX_W-1:0]       cpu_write_set_id;
    logic [WORD_OFFSET_W-1:0]     cpu_write_word_id;
    logic [DATA_WIDTH-1:0]        cpu_write_wdata;

    // S0 write-grant precompute nets (Entry 10)
    logic [TAG_WIDTH-1:0]         array_rtag;
    logic [ASSOC-1:0]             way_s0_line_match;
    logic [ASSOC-1:0]             way_s0_allocated;
    logic [WAY_INDEX_W-1:0]       plru_lookup_way;

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

    // A request is ACCEPTED only when valid and ready are both high
    // (Contract A-loose: the producer may hold, replace, or retract an
    // un-accepted offer; payload is sampled only at acceptance). The
    // pipeline must consume cpu_req_fire, never raw cpu_req_valid: a
    // compliant CPU holds valid through !ready cycles, and an ungated
    // pipe re-processes that held request every cycle (ghost merges
    // overflow the RS waiter list, duplicate responses corrupt ordering).
    // This path was latent-broken: cpu_req_ready never deasserts under
    // current traffic (RS occupancy peaks at 8 vs the AF=3 threshold of
    // 13; the hit FIFO never fills), so no regression exercised it until
    // the 2026-08-21 MSHR_AF=11 probe failed on every RTL generation
    // back to the pre-campaign baseline. Full story: optimizations.md,
    // "The handshake bug".
    logic cpu_req_fire;
    assign cpu_req_fire = cpu_req_valid && cpu_req_ready;

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

        .in_valid       (cpu_req_fire),
        .in_write       (cpu_req_write),
        .in_addr        (cpu_req_addr),
        .in_wdata       (cpu_req_wdata),
        .in_cpu_req_id  (cpu_req_id),

        .array_raddr    (array_rindex),
        .array_rtag     (array_rtag),

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
                .WORD_OFFSET_W  (WORD_OFFSET_W),
                .EN_SRAM_MACRO  (EN_SRAM_MACRO)
            ) FLAG_TAG_DATA_ARRAY (
                .clk             (clk),
                .rst             (rst),

                .raddr           (array_rindex),

                .s0_tag          (array_rtag),
                .s0_line_match   (way_s0_line_match[way_gen]),
                .s0_allocated    (way_s0_allocated[way_gen]),

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

        // PLRU is a lookahead: victim computed combinationally from
        // lookup_set, registered, consumed the NEXT cycle. Feed it the S0
        // index (same wire the arrays read with) so the registered victim
        // corresponds to the request that reaches S1 when it is consumed.
        // (Was dec_set_id - the S1 set - which delivered the PREVIOUS
        // request's set's victim to the compare stage: policy-only bug,
        // measured as the 16KB associativity-miss inversion.)
        .lookup_set      (array_rindex),
        .replacement_way (replacement_way),
        .lookup_way_c    (plru_lookup_way),

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

        // S0 write-grant precompute (Entry 10). s0_write mirrors
        // Address_Decode's out_write register (accept && in_write).
        .s0_valid                 (cpu_req_fire),
        .s0_write                 (cpu_req_fire && cpu_req_write),
        .s0_tag                   (array_rtag),
        .s0_set_id                (array_rindex),
        .s0_line_match            (way_s0_line_match),
        .s0_allocated             (way_s0_allocated),
        .s0_replacement_way       (plru_lookup_way),

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
        // RS depth 8 is PAIRED to MSHR_COUNT=4 (adopted 2026-08-21):
        // measured occupancy ceiling is 8 at any depth, so 16 paid CAM/
        // vbuf/fanout in the WNS-owning cone for slots never used. At
        // depth 8 the almost-full brake engages routinely, so every
        // regression now exercises the cpu_req_fire backpressure path.
        // AF=3 keeps one spare slot (pipe carries 2 after ready falls;
        // measured high-water 7/8). Revisit if MSHR_COUNT scales
        // (plausible rule: MISSQ_DEPTH = 2 x MSHR_COUNT).
        .MISSQ_DEPTH      (8),
        .MSHR_AF          (3),
        .MAX_WAITERS      (WORDS_PER_LINE)
    ) MSHR_FILE (
        .clk                  (clk),
        .rst                  (rst),

        .alloc_valid          (miss_select_valid),
        .alloc_ready          (mshr_alloc_ready),

        .alloc_line_addr      (miss_select_line_addr),

        // Entry 11: the compare-stage request's line address, one cycle
        // ahead of miss_select_line_addr - same {tag, set} construction.
        .pre_line_addr        ({dec_tag, dec_set_id}),

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
