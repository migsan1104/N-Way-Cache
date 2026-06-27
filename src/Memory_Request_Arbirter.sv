// ============================================================
// Downstream memory request arbiter
// Priority: dirty writeback requests before read refill requests
// Assumption: mem_req_ready means downstream accepts next cycle
// ============================================================

module Memory_Request_Arbiter #(
    parameter int ADDR_WIDTH = 32,
    parameter int LINE_WIDTH = 128,
    parameter int ID_WIDTH   = 2
)(
    // ============================================================
    // WRITEBACK REQUEST SOURCE
    // ============================================================

    input  logic                  wb_req_valid,
    output logic                  wb_req_ready,
    input  logic [ADDR_WIDTH-1:0] wb_req_addr,
    input  logic [LINE_WIDTH-1:0] wb_req_wdata,

    // ============================================================
    // READ REFILL REQUEST SOURCE
    // ============================================================

    input  logic                  refill_req_valid,
    output logic                  refill_req_ready,
    input  logic [ADDR_WIDTH-1:0] refill_req_addr,
    input  logic [ID_WIDTH-1:0]   refill_req_id,

    // ============================================================
    // DOWNSTREAM MEMORY REQUEST
    // ============================================================

    output logic                  mem_req_valid,
    input  logic                  mem_req_ready,

    output logic                  mem_req_write,
    output logic [ADDR_WIDTH-1:0] mem_req_addr,
    output logic [LINE_WIDTH-1:0] mem_req_wdata,
    output logic [ID_WIDTH-1:0]   mem_req_id
);

    always_comb begin
        wb_req_ready     = 1'b0;
        refill_req_ready = 1'b0;

        mem_req_valid = 1'b0;
        mem_req_write = 1'b0;
        mem_req_addr  = '0;
        mem_req_wdata = '0;
        mem_req_id    = '0;

        // Writebacks have priority so the eviction FIFO does not fill up.
        if (wb_req_valid) begin
            mem_req_valid = 1'b1;
            mem_req_write = 1'b1;
            mem_req_addr  = wb_req_addr;
            mem_req_wdata = wb_req_wdata;
            mem_req_id    = '0;

            wb_req_ready = mem_req_ready;
        end

        else if (refill_req_valid) begin
            mem_req_valid = 1'b1;
            mem_req_write = 1'b0;
            mem_req_addr  = refill_req_addr;
            mem_req_wdata = '0;
            mem_req_id    = refill_req_id;

            refill_req_ready = mem_req_ready;
        end
    end

endmodule