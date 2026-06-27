// ============================================================
// Parameterized set-associative cache
// ============================================================

module Cache #(
    parameter int CACHE_BYTES   = 1024,
    parameter int ASSOC         = 4,

    localparam int ADDR_WIDTH    = 32,
    localparam int DATA_WIDTH    = 32,
    localparam int CPU_ID_WIDTH  = 4,
    localparam int MSHR_ID_WIDTH = 2,
    localparam logic DEBUG       = 1'b0
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
    input  logic                      mem_req_ready,

    output logic                      mem_req_write,
    output logic [ADDR_WIDTH-1:0]     mem_req_addr,
    output logic [DATA_WIDTH-1:0]     mem_req_wdata,
    output logic [MSHR_ID_WIDTH-1:0]  mem_req_id,

    input  logic                      mem_resp_valid,
    output logic                      mem_resp_ready,

    input  logic [MSHR_ID_WIDTH-1:0]  mem_resp_id,
    input  logic [DATA_WIDTH-1:0]     mem_resp_rdata
);

    localparam int WORD_BYTES      = 4;
    localparam int WORDS_PER_LINE  = 4;
    localparam int LINE_BYTES      = 16;
    localparam int LINE_WIDTH      = 128;

    localparam int NUM_LINES       = CACHE_BYTES / LINE_BYTES;
    localparam int NUM_SETS        = NUM_LINES / ASSOC;

    localparam int BYTE_OFFSET_W   = 2;
    localparam int WORD_OFFSET_W   = 2;

    localparam int SET_INDEX_BITS  = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS);
    localparam int SET_INDEX_W     = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS;

    localparam int TAG_WIDTH       = ADDR_WIDTH - BYTE_OFFSET_W - WORD_OFFSET_W - SET_INDEX_BITS;
    localparam int LINE_ADDR_WIDTH = ADDR_WIDTH - BYTE_OFFSET_W - WORD_OFFSET_W;

    localparam int WAY_INDEX_W     = (ASSOC <= 1) ? 1 : $clog2(ASSOC);
    localparam int MSHR_COUNT      = 4;

    logic [SET_INDEX_W-1:0]       array_rindex;

    logic                         dec_valid;
    logic                         dec_write;
    logic [ADDR_WIDTH-1:0]        dec_addr;
    logic [DATA_WIDTH-1:0]        dec_wdata;
    logic [CPU_ID_WIDTH-1:0]      dec_cpu_req_id;
    logic [TAG_WIDTH-1:0]         dec_tag;
    logic [SET_INDEX_W-1:0]       dec_set_id;
    logic [WORD_OFFSET_W-1:0]     dec_word_id;
    logic [LINE_ADDR_WIDTH-1:0]   dec_line_addr;

    logic [LINE_WIDTH-1:0]        way_line       [ASSOC];
    logic [TAG_WIDTH-1:0]         way_tag        [ASSOC];
    logic                         way_allocated  [ASSOC];
    logic                         way_dirty      [ASSOC];
    logic [WORDS_PER_LINE-1:0]    way_word_valid [ASSOC];

    logic                         cmp_valid;
    logic                         cmp_write;
    logic                         cmp_hit;
    logic                         cmp_miss;
    logic [ADDR_WIDTH-1:0]        cmp_addr;
    logic [DATA_WIDTH-1:0]        cmp_wdata;
    logic [DATA_WIDTH-1:0]        cmp_rdata;
    logic [CPU_ID_WIDTH-1:0]      cmp_cpu_req_id;
    logic [TAG_WIDTH-1:0]         cmp_tag;
    logic [SET_INDEX_W-1:0]       cmp_set_id;
    logic [WORD_OFFSET_W-1:0]     cmp_word_id;
    logic [LINE_ADDR_WIDTH-1:0]   cmp_line_addr;
    logic [WAY_INDEX_W-1:0]       cmp_hit_way;
    logic [WAY_INDEX_W-1:0]       cmp_miss_way;

    logic                         miss_select_valid;
    logic                         miss_select_write;
    logic [ADDR_WIDTH-1:0]        miss_select_addr;
    logic [DATA_WIDTH-1:0]        miss_select_wdata;
    logic [CPU_ID_WIDTH-1:0]      miss_select_cpu_req_id;
    logic [TAG_WIDTH-1:0]         miss_select_tag;
    logic [SET_INDEX_W-1:0]       miss_select_set_id;
    logic [WORD_OFFSET_W-1:0]     miss_select_word_id;
    logic [LINE_ADDR_WIDTH-1:0]   miss_select_line_addr;
    logic [WAY_INDEX_W-1:0]       miss_select_way;

    logic                         miss_select_victim_valid;
    logic                         miss_select_victim_dirty;
    logic [TAG_WIDTH-1:0]         miss_select_victim_tag;
    logic [LINE_WIDTH-1:0]        miss_select_victim_line;

    logic                         regular_found;
    logic [WAY_INDEX_W-1:0]       regular_way;

    logic [ASSOC-1:0]             alloc_wen;
    logic [SET_INDEX_W-1:0]       alloc_waddr;
    logic [TAG_WIDTH-1:0]         alloc_tag;

    logic                         cpu_write_valid;
    logic [ASSOC-1:0]             cpu_write_wen;
    logic [ASSOC-1:0]             cpu_write_replace;
    logic [WAY_INDEX_W-1:0]       cpu_write_way;
    logic [SET_INDEX_W-1:0]       cpu_write_set_id;
    logic [WORD_OFFSET_W-1:0]     cpu_write_word_id;
    logic [DATA_WIDTH-1:0]        cpu_write_wdata;

    logic [WAY_INDEX_W-1:0]       replacement_way;
    logic                         replacement_update_valid;
    logic [SET_INDEX_W-1:0]       replacement_update_set;
    logic [WAY_INDEX_W-1:0]       replacement_update_way;

    logic                         mshr_alloc_ready;
    logic [MSHR_ID_WIDTH-1:0]     mshr_alloc_id;
    logic                         mshr_full;
    logic                         mshr_empty;

    logic [MSHR_COUNT-1:0]        mshr_req_valid;
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
    logic                         refill_dirty;
    logic                         refill_eviction;
    logic [LINE_WIDTH-1:0]        refill_line;

    logic [ASSOC-1:0]             refill_way_wen;
    logic [ASSOC-1:0]             refill_tag_wen;

    logic                         hit_resp_valid;
    logic                         miss_resp_valid;
    logic                         hit_resp_ready;
    logic                         miss_resp_ready;

    logic                         dbg_mshr_alloc_fire;
    integer                       dbg_mshr_alloc_count;
    integer                       dbg_expected_eviction_count;
    integer                       dbg_dirty_eviction_count;
    integer                       dbg_clean_eviction_count;

    assign cpu_req_ready = hit_resp_ready && mshr_alloc_ready;
    assign dbg_mshr_alloc_fire = miss_select_valid && mshr_alloc_ready;

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
        .in_ready       (cpu_req_ready),
        .in_write       (cpu_req_write),
        .in_addr        (cpu_req_addr),
        .in_wdata       (cpu_req_wdata),
        .in_cpu_req_id  (cpu_req_id),

        .array_raddr    (array_rindex),

        .out_valid      (dec_valid),
        .out_write      (dec_write),
        .out_addr       (dec_addr),
        .out_wdata      (dec_wdata),
        .out_cpu_req_id (dec_cpu_req_id),
        .out_tag        (dec_tag),
        .out_set_id     (dec_set_id),
        .out_word_id    (dec_word_id),
        .out_line_addr  (dec_line_addr)
    );

    always_comb begin
        refill_way_wen = '0;
        refill_tag_wen = '0;

        if (refill_wen) begin
            refill_way_wen[refill_way] = 1'b1;
            refill_tag_wen[refill_way] = 1'b1;
        end
    end

    genvar way_gen;

    generate
        for (way_gen = 0; way_gen < ASSOC; way_gen++) begin : GEN_WAYS

            Flag_Data_Array #(
                .DATA_WIDTH     (DATA_WIDTH),
                .LINE_WIDTH     (LINE_WIDTH),
                .DEPTH          (NUM_SETS),
                .SET_INDEX_W    (SET_INDEX_W),
                .WORDS_PER_LINE (WORDS_PER_LINE),
                .WORD_OFFSET_W  (WORD_OFFSET_W)
            ) FLAG_DATA_ARRAY (
                .clk             (clk),
                .rst             (rst),

                .raddr           (array_rindex),

                .rline           (way_line[way_gen]),
                .allocated       (way_allocated[way_gen]),
                .dirty           (way_dirty[way_gen]),
                .word_valid      (way_word_valid[way_gen]),

                .refill_wen      (refill_way_wen[way_gen]),
                .refill_waddr    (refill_set_id),
                .refill_line     (refill_line),
                .refill_dirty    (refill_dirty),
                .refill_eviction (refill_eviction),

                .alloc_wen       (alloc_wen[way_gen]),
                .alloc_waddr     (alloc_waddr),

                .cpu_word_wen    (cpu_write_wen[way_gen]),
                .cpu_replace     (cpu_write_replace[way_gen]),
                .cpu_waddr       (cpu_write_set_id),
                .cpu_word_id     (cpu_write_word_id),
                .cpu_wdata       (cpu_write_wdata)
            );

            Tag_Array #(
                .TAG_WIDTH   (TAG_WIDTH),
                .DEPTH       (NUM_SETS),
                .SET_INDEX_W (SET_INDEX_W)
            ) TAG_ARRAY (
                .clk          (clk),
                .rst          (rst),

                .raddr        (array_rindex),
                .rdata        (way_tag[way_gen]),

                .early_wen    (alloc_wen[way_gen]),
                .early_waddr  (alloc_waddr),
                .early_wdata  (alloc_tag),

                .refill_wen   (refill_tag_wen[way_gen]),
                .refill_waddr (refill_set_id),
                .refill_wdata (refill_tag)
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
        .ADDR_WIDTH      (ADDR_WIDTH),
        .CPU_ID_WIDTH    (CPU_ID_WIDTH),
        .SET_INDEX_W     (SET_INDEX_W),
        .WORD_OFFSET_W   (WORD_OFFSET_W),
        .LINE_ADDR_WIDTH (LINE_ADDR_WIDTH),
        .WORDS_PER_LINE  (WORDS_PER_LINE),
        .WAY_INDEX_W     (WAY_INDEX_W)
    ) COMPARE_SELECT_REPLACE (
        .clk                      (clk),
        .rst                      (rst),

        .in_valid                 (dec_valid),
        .in_write                 (dec_write),
        .in_addr                  (dec_addr),
        .in_wdata                 (dec_wdata),
        .in_cpu_req_id            (dec_cpu_req_id),
        .in_tag                   (dec_tag),
        .in_set_id                (dec_set_id),
        .in_word_id               (dec_word_id),
        .in_line_addr             (dec_line_addr),

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

        .out_addr                 (cmp_addr),
        .out_wdata                (cmp_wdata),
        .out_rdata                (cmp_rdata),
        .out_cpu_req_id           (cmp_cpu_req_id),
        .out_tag                  (cmp_tag),
        .out_set_id               (cmp_set_id),
        .out_word_id              (cmp_word_id),
        .out_line_addr            (cmp_line_addr),

        .out_hit_way              (cmp_hit_way),
        .out_miss_way             (cmp_miss_way),

        .out_victim_valid         (miss_select_victim_valid),
        .out_victim_dirty         (miss_select_victim_dirty),
        .out_victim_tag           (miss_select_victim_tag),
        .out_victim_line          (miss_select_victim_line),

        .regular_found            (regular_found),
        .regular_way              (regular_way),

        .alloc_wen                (alloc_wen),
        .alloc_waddr              (alloc_waddr),
        .alloc_tag                (alloc_tag),

        .cpu_write_valid          (cpu_write_valid),
        .cpu_write_wen            (cpu_write_wen),
        .cpu_write_replace        (cpu_write_replace),
        .cpu_write_way            (cpu_write_way),
        .cpu_write_set_id         (cpu_write_set_id),
        .cpu_write_word_id        (cpu_write_word_id),
        .cpu_write_wdata          (cpu_write_wdata),

        .replacement_update_valid (replacement_update_valid),
        .replacement_update_set   (replacement_update_set),
        .replacement_update_way   (replacement_update_way)
    );

    assign miss_select_valid      = cmp_valid && cmp_miss;
    assign miss_select_write      = cmp_write;
    assign miss_select_addr       = cmp_addr;
    assign miss_select_wdata      = cmp_wdata;
    assign miss_select_cpu_req_id = cmp_cpu_req_id;
    assign miss_select_tag        = cmp_tag;
    assign miss_select_set_id     = cmp_set_id;
    assign miss_select_word_id    = cmp_word_id;
    assign miss_select_line_addr  = cmp_line_addr;
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
        .MISSQ_DEPTH      (32),
        .MSHR_AF          (8),
        .MAX_WAITERS      (WORDS_PER_LINE)
    ) MSHR_FILE (
        .clk                  (clk),
        .rst                  (rst),

        .alloc_valid          (miss_select_valid),
        .alloc_ready          (mshr_alloc_ready),

        .alloc_line_addr      (miss_select_line_addr),
        .alloc_set_id         (miss_select_set_id),
        .alloc_word_id        (miss_select_word_id),
        .alloc_tag            (miss_select_tag),
        .alloc_way            (miss_select_way),

        .alloc_write          (miss_select_write),
        .alloc_wdata          (miss_select_wdata),
        .alloc_cpu_req_id     (miss_select_cpu_req_id),

        .alloc_victim_valid   (miss_select_victim_valid),
        .alloc_victim_dirty   (miss_select_victim_dirty),
        .alloc_victim_tag     (miss_select_victim_tag),
        .alloc_victim_line    (miss_select_victim_line),

        .alloc_mshr_id        (mshr_alloc_id),

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
        .refill_dirty         (refill_dirty),
        .refill_eviction      (refill_eviction),
        .refill_line          (refill_line),

        .issue_pending        (),
        .issue_line_addr      (),
        .issue_word_id        (),

        .req_valid            (mshr_req_valid),
        .req_write            (mshr_req_write),
        .req_addr             (mshr_req_addr),
        .req_wdata            (mshr_req_wdata),
        .req_id               (mshr_req_id),

        .full                 (mshr_full),
        .empty                (mshr_empty)
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
        .req_write     (mshr_req_write),
        .req_addr      (mshr_req_addr),
        .req_wdata     (mshr_req_wdata),
        .req_id        (mshr_req_id),

        .issued        (mshr_issued),

        .mem_req_valid (mem_req_valid),
        .mem_req_ready (mem_req_ready),
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
        .FIFO_DEPTH   (128)
    ) RESPONSE_UNIT (
        .clk            (clk),
        .rst            (rst),

        .hit_valid      (hit_resp_valid),
        .hit_ready      (hit_resp_ready),
        .hit_data       (cmp_rdata),
        .hit_id         (cmp_cpu_req_id),

        .miss_valid     (miss_resp_valid),
        .miss_ready     (miss_resp_ready),
        .miss_data      (miss_cpu_resp_data),
        .miss_id        (miss_cpu_resp_id),

        .cpu_resp_valid (cpu_resp_valid),
        .cpu_resp_ready (cpu_resp_ready),
        .cpu_resp_hit   (cpu_resp_hit),
        .cpu_resp_rdata (cpu_resp_rdata),
        .cpu_resp_id    (cpu_resp_id)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            dbg_mshr_alloc_count        <= 0;
            dbg_expected_eviction_count <= 0;
            dbg_dirty_eviction_count    <= 0;
            dbg_clean_eviction_count    <= 0;
        end
        else begin
            if (DEBUG && refill_wen && cpu_write_valid &&
                (refill_set_id == cpu_write_set_id) &&
                (refill_way == cpu_write_way)) begin
                $display("[%0t] SAME_WAY_COLLISION: set=%0d way=%0d refill_tag=%h alloc_tag=%h refill_dirty=%0b refill_eviction=%0b cpu_replace=%0b refill_line=%h cpu_word=%0d cpu_wdata=%h",
                         $time,
                         refill_set_id,
                         refill_way,
                         refill_tag,
                         alloc_tag,
                         refill_dirty,
                         refill_eviction,
                         cpu_write_replace[cpu_write_way],
                         refill_line,
                         cpu_write_word_id,
                         cpu_write_wdata);
            end

            if (DEBUG && hit_resp_valid && hit_resp_ready) begin
                $display("[%0t] CACHE HIT PUSH: write=%0b id=%0d data=%h",
                         $time,
                         cmp_write,
                         cmp_cpu_req_id,
                         cmp_rdata);
            end

            if (DEBUG && miss_resp_valid) begin
                $display("[%0t] CACHE MISS PUSH: id=%0d data=%h delayed_data=%h",
                         $time,
                         miss_cpu_resp_id,
                         miss_cpu_resp_data,
                         delayed_miss_data);
            end

            if (DEBUG && (|alloc_wen)) begin
                $display("[%0t] CACHE ALLOC ARRAY: set=%0d tag=%h alloc_wen=%b",
                         $time,
                         alloc_waddr,
                         alloc_tag,
                         alloc_wen);
            end

            if (DEBUG && cpu_write_valid) begin
                $display("[%0t] CACHE CPU WRITE ARRAY: set=%0d way=%0d word=%0d data=%h replace=%0b",
                         $time,
                         cpu_write_set_id,
                         cpu_write_way,
                         cpu_write_word_id,
                         cpu_write_wdata,
                         cpu_write_replace[cpu_write_way]);
            end

            if (DEBUG && refill_wen) begin
                $display("[%0t] CACHE REFILL ARRAY: set=%0d way=%0d tag=%h dirty=%0b eviction=%0b",
                         $time,
                         refill_set_id,
                         refill_way,
                         refill_tag,
                         refill_dirty,
                         refill_eviction);
            end

            if (DEBUG && miss_select_valid) begin
                $display("[%0t] CACHE MISS TO MSHR: ready=%0b write=%0b set=%0d way=%0d tag=%h addr=%h victim_valid=%0b victim_dirty=%0b victim_tag=%h",
                         $time,
                         mshr_alloc_ready,
                         miss_select_write,
                         miss_select_set_id,
                         miss_select_way,
                         miss_select_tag,
                         miss_select_addr,
                         miss_select_victim_valid,
                         miss_select_victim_dirty,
                         miss_select_victim_tag);
            end

            if (DEBUG && dbg_mshr_alloc_fire) begin
                dbg_mshr_alloc_count <= dbg_mshr_alloc_count + 1;

                if (miss_select_victim_valid) begin
                    dbg_expected_eviction_count <= dbg_expected_eviction_count + 1;

                    if (miss_select_victim_dirty)
                        dbg_dirty_eviction_count <= dbg_dirty_eviction_count + 1;
                    else
                        dbg_clean_eviction_count <= dbg_clean_eviction_count + 1;
                end

                $display("[%0t] MSHR ALLOC DEBUG: alloc#=%0d mshr_id=%0d write=%0b cpu_id=%0d addr=%h line_addr=%h set=%0d word=%0d way=%0d new_tag=%h victim_valid=%0b victim_dirty=%0b victim_tag=%h victim_line=%h",
                         $time,
                         dbg_mshr_alloc_count + 1,
                         mshr_alloc_id,
                         miss_select_write,
                         miss_select_cpu_req_id,
                         miss_select_addr,
                         miss_select_line_addr,
                         miss_select_set_id,
                         miss_select_word_id,
                         miss_select_way,
                         miss_select_tag,
                         miss_select_victim_valid,
                         miss_select_victim_dirty,
                         miss_select_victim_tag,
                         miss_select_victim_line);
            end

            if (DEBUG && cpu_req_valid && !cpu_req_ready) begin
                $display("[%0t] CPU REQ BLOCKED: write=%0b addr=%h id=%0d hit_ready=%0b mshr_ready=%0b mshr_full=%0b",
                         $time,
                         cpu_req_write,
                         cpu_req_addr,
                         cpu_req_id,
                         hit_resp_ready,
                         mshr_alloc_ready,
                         mshr_full);
            end
        end
    end

endmodule