// ============================================================
// Registered MSHR request arbiter
// Locks onto one MSHR and drains its request stream before
// switching to another MSHR.
//
// This makes requests come out as contiguous per-MSHR bundles
// when each MSHR keeps req_valid high until all beats issue.
// ============================================================

module MSHR_Request_Arbiter #(
    parameter int MSHR_COUNT    = 4,
    parameter int ADDR_WIDTH    = 32,
    parameter int DATA_WIDTH    = 32,
    parameter int MSHR_ID_WIDTH = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic [MSHR_COUNT-1:0]            req_valid,
    input  logic [MSHR_COUNT-1:0]            req_write,
    input  logic [ADDR_WIDTH-1:0]            req_addr  [MSHR_COUNT],
    input  logic [DATA_WIDTH-1:0]            req_wdata [MSHR_COUNT],
    input  logic [MSHR_ID_WIDTH-1:0]         req_id    [MSHR_COUNT],

    output logic [MSHR_COUNT-1:0]            issued,

    output logic                             mem_req_valid,
    input  logic                             mem_req_ready,
    output logic                             mem_req_write,
    output logic [ADDR_WIDTH-1:0]            mem_req_addr,
    output logic [DATA_WIDTH-1:0]            mem_req_wdata,
    output logic [MSHR_ID_WIDTH-1:0]         mem_req_id
);

    logic                         out_valid_r;
    logic                         out_write_r;
    logic [ADDR_WIDTH-1:0]        out_addr_r;
    logic [DATA_WIDTH-1:0]        out_wdata_r;
    logic [MSHR_ID_WIDTH-1:0]     out_id_r;

    logic                         lock_valid_r;
    logic [MSHR_ID_WIDTH-1:0]     lock_id_r;

    logic                         found_req;
    logic                         load_new;
    logic [MSHR_COUNT-1:0]        selected_onehot;
    logic                         selected_write;
    logic [ADDR_WIDTH-1:0]        selected_addr;
    logic [DATA_WIDTH-1:0]        selected_wdata;
    logic [MSHR_ID_WIDTH-1:0]     selected_id;

    assign mem_req_valid = out_valid_r;
    assign mem_req_write = out_write_r;
    assign mem_req_addr  = out_addr_r;
    assign mem_req_wdata = out_wdata_r;
    assign mem_req_id    = out_id_r;

    assign load_new = !out_valid_r || mem_req_ready;

    assign issued = (load_new && found_req) ? selected_onehot : '0;

    always_comb begin
        found_req        = 1'b0;
        selected_onehot  = '0;
        selected_write   = 1'b0;
        selected_addr    = '0;
        selected_wdata   = '0;
        selected_id      = '0;

        // If locked MSHR still has work, keep issuing it.
        if (lock_valid_r && req_valid[lock_id_r]) begin
            found_req                   = 1'b1;
            selected_onehot[lock_id_r]  = 1'b1;
            selected_write              = req_write[lock_id_r];
            selected_addr               = req_addr [lock_id_r];
            selected_wdata              = req_wdata[lock_id_r];
            selected_id                 = req_id   [lock_id_r];
        end
        else begin
            // Otherwise choose a new MSHR by fixed priority.
            for (int i = 0; i < MSHR_COUNT; i++) begin
                if (req_valid[i] && !found_req) begin
                    found_req          = 1'b1;
                    selected_onehot[i] = 1'b1;
                    selected_write     = req_write[i];
                    selected_addr      = req_addr[i];
                    selected_wdata     = req_wdata[i];
                    selected_id        = req_id[i];
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid_r  <= 1'b0;
            out_write_r  <= 1'b0;
            out_addr_r   <= '0;
            out_wdata_r  <= '0;
            out_id_r     <= '0;
            lock_valid_r <= 1'b0;
            lock_id_r    <= '0;
        end
        else begin
            if (load_new) begin
                if (found_req) begin
                    out_valid_r  <= 1'b1;
                    out_write_r  <= selected_write;
                    out_addr_r   <= selected_addr;
                    out_wdata_r  <= selected_wdata;
                    out_id_r     <= selected_id;

                    lock_valid_r <= 1'b1;
                    lock_id_r    <= selected_id;
                end
                else begin
                    out_valid_r  <= 1'b0;
                    out_write_r  <= 1'b0;
                    out_addr_r   <= '0;
                    out_wdata_r  <= '0;
                    out_id_r     <= '0;

                    lock_valid_r <= 1'b0;
                    lock_id_r    <= '0;
                end
            end

            // Drop lock once selected MSHR no longer has a request.
            if (lock_valid_r && !req_valid[lock_id_r]) begin
                lock_valid_r <= 1'b0;
            end
        end
    end

endmodule