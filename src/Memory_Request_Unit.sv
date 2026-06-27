// ============================================================
// Memory request unit
// Combines dirty eviction writebacks and read miss refill requests
// ============================================================

module Memory_Request_Unit #(
    parameter int ADDR_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int LINE_ADDR_WIDTH = 28,
    parameter int LINE_BYTES      = 16,
    parameter int ID_WIDTH        = 2,
    parameter int WB_DEPTH        = 8,
    parameter int MISS_DEPTH      = 8
)(
    input  logic                         clk,
    input  logic                         rst,

    // ============================================================
    // DIRTY EVICTION INPUT
    // ============================================================

    input  logic                         evict_valid,
    output logic                         evict_ready,
    input  logic [ADDR_WIDTH-1:0]        evict_addr,
    input  logic [LINE_WIDTH-1:0]        evict_line_data,

    // ============================================================
    // READ MISS INPUT
    // ============================================================

    input  logic                         miss_valid,
    output logic                         miss_ready,
    input  logic [LINE_ADDR_WIDTH-1:0]   miss_line_addr,
    input  logic [ID_WIDTH-1:0]          miss_id,

    // ============================================================
    // DOWNSTREAM MEMORY REQUEST
    // ============================================================

    output logic                         mem_req_valid,
    input  logic                         mem_req_ready,

    output logic                         mem_req_write,
    output logic [ADDR_WIDTH-1:0]        mem_req_addr,
    output logic [LINE_WIDTH-1:0]        mem_req_wdata,
    output logic [ID_WIDTH-1:0]          mem_req_id
);

    logic                  wb_req_valid;
    logic                  wb_req_ready;
    logic [ADDR_WIDTH-1:0] wb_req_addr;
    logic [LINE_WIDTH-1:0] wb_req_wdata;

    logic                  refill_req_valid;
    logic                  refill_req_ready;
    logic [ADDR_WIDTH-1:0] refill_req_addr;
    logic [ID_WIDTH-1:0]   refill_req_id;

    Eviction_Buffer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .DEPTH     (WB_DEPTH)
    ) EVICTION_BUFFER (
        .clk            (clk),
        .rst            (rst),

        .evict_valid    (evict_valid),
        .evict_ready    (evict_ready),
        .evict_addr     (evict_addr),
        .evict_line_data(evict_line_data),

        .mem_req_valid  (wb_req_valid),
        .mem_req_ready  (wb_req_ready),
        .mem_req_write  (),
        .mem_req_addr   (wb_req_addr),
        .mem_req_wdata  (wb_req_wdata)
    );

    Read_Miss_Queue #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
        .LINE_BYTES     (LINE_BYTES),
        .ID_WIDTH       (ID_WIDTH),
        .DEPTH          (MISS_DEPTH)
    ) READ_MISS_QUEUE (
        .clk          (clk),
        .rst          (rst),

        .miss_valid   (miss_valid),
        .miss_ready   (miss_ready),
        .miss_line_addr(miss_line_addr),
        .miss_id      (miss_id),

        .mem_req_valid(refill_req_valid),
        .mem_req_ready(refill_req_ready),
        .mem_req_write(),
        .mem_req_addr (refill_req_addr),
        .mem_req_id   (refill_req_id)
    );

    Memory_Request_Arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .ID_WIDTH  (ID_WIDTH)
    ) MEM_REQ_ARBITER (
        .wb_req_valid    (wb_req_valid),
        .wb_req_ready    (wb_req_ready),
        .wb_req_addr     (wb_req_addr),
        .wb_req_wdata    (wb_req_wdata),

        .refill_req_valid(refill_req_valid),
        .refill_req_ready(refill_req_ready),
        .refill_req_addr (refill_req_addr),
        .refill_req_id   (refill_req_id),

        .mem_req_valid   (mem_req_valid),
        .mem_req_ready   (mem_req_ready),
        .mem_req_write   (mem_req_write),
        .mem_req_addr    (mem_req_addr),
        .mem_req_wdata   (mem_req_wdata),
        .mem_req_id      (mem_req_id)
    );

endmodule