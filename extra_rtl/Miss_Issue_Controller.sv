// ============================================================
// Miss issue controller
// Allocates one MSHR per miss and pushes dirty victim writeback
// Does not generate CWF read beats
// ============================================================

module Miss_Issue_Controller #(
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int MSHR_ID_WIDTH   = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic                       req_valid,
    input  logic                       req_miss,
    input  logic                       req_write,
    input  logic [DATA_WIDTH-1:0]      req_wdata,
    input  logic [CPU_ID_WIDTH-1:0]    req_cpu_req_id,
    input  logic [LINE_ADDR_WIDTH-1:0] req_line_addr,
    input  logic [SET_INDEX_W-1:0]     req_set_id,
    input  logic [WORD_OFFSET_W-1:0]   req_word_id,
    input  logic [TAG_WIDTH-1:0]       req_tag,

    input  logic [WAY_INDEX_W-1:0]     victim_way,
    input  logic                       victim_valid,
    input  logic                       victim_dirty,
    input  logic [LINE_ADDR_WIDTH-1:0] victim_line_addr,
    input  logic [LINE_WIDTH-1:0]      victim_line_data,

    output logic                       mshr_alloc_valid,
    input  logic                       mshr_alloc_ready,
    output logic [LINE_ADDR_WIDTH-1:0] mshr_alloc_line_addr,
    output logic [SET_INDEX_W-1:0]     mshr_alloc_set_id,
    output logic [WORD_OFFSET_W-1:0]   mshr_alloc_word_id,
    output logic [TAG_WIDTH-1:0]       mshr_alloc_tag,
    output logic [WAY_INDEX_W-1:0]     mshr_alloc_way,
    output logic                       mshr_alloc_write,
    output logic [DATA_WIDTH-1:0]      mshr_alloc_wdata,
    output logic [CPU_ID_WIDTH-1:0]    mshr_alloc_cpu_req_id,

    output logic                       evict_valid,
    input  logic                       evict_ready,
    output logic [LINE_ADDR_WIDTH-1:0] evict_line_addr,
    output logic [LINE_WIDTH-1:0]      evict_line_data,

    output logic                       issue_ready
);

    logic dirty_victim;
    logic issue_fire;

    assign dirty_victim = victim_valid && victim_dirty;

    assign issue_ready =
        mshr_alloc_ready &&
        (!dirty_victim || evict_ready);

    assign issue_fire = req_valid && req_miss && issue_ready;

    assign mshr_alloc_valid      = issue_fire;
    assign mshr_alloc_line_addr  = req_line_addr;
    assign mshr_alloc_set_id     = req_set_id;
    assign mshr_alloc_word_id    = req_word_id;
    assign mshr_alloc_tag        = req_tag;
    assign mshr_alloc_way        = victim_way;
    assign mshr_alloc_write      = req_write;
    assign mshr_alloc_wdata      = req_wdata;
    assign mshr_alloc_cpu_req_id = req_cpu_req_id;

    assign evict_valid           = issue_fire && dirty_victim;
    assign evict_line_addr       = victim_line_addr;
    assign evict_line_data       = victim_line_data;

endmodule