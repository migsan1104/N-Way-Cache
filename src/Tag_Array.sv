module Tag_Array #(
    parameter int TAG_WIDTH   = 24,
    parameter int DEPTH       = 16,
    parameter int SET_INDEX_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    localparam bit DEBUG      = 1'b0
)(
    input  logic                   clk,
    input  logic                   rst,

    input  logic [SET_INDEX_W-1:0] raddr,
    output logic [TAG_WIDTH-1:0]   rdata,

    input  logic                   early_wen,
    input  logic [SET_INDEX_W-1:0] early_waddr,
    input  logic [TAG_WIDTH-1:0]   early_wdata,

    input  logic                   refill_wen,
    input  logic [SET_INDEX_W-1:0] refill_waddr,
    input  logic [TAG_WIDTH-1:0]   refill_wdata,

    output logic                   refill_current_match
);

    logic [TAG_WIDTH-1:0] mem [DEPTH];

    assign refill_current_match = (mem[refill_waddr] == refill_wdata);

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
            rdata <= '0;
        end
        else begin
            // Default registered read
            rdata <= mem[raddr];

            // Refill write happens first
            if (refill_wen && refill_current_match) begin
                if (DEBUG) begin
                    $display("[%0t] TAG_ARRAY REFILL_WRITE: set=%0d old_tag=%h new_tag=%h raddr=%0d",
                             $time, refill_waddr, mem[refill_waddr], refill_wdata, raddr);
                end

                mem[refill_waddr] <= refill_wdata;

                if (refill_waddr == raddr) begin
                    rdata <= refill_wdata;
                end
            end

            // Early CPU tag write has final priority, matching Flag_Data_Array
            if (early_wen) begin
                if (DEBUG) begin
                    $display("[%0t] TAG_ARRAY EARLY_WRITE: set=%0d old_tag=%h new_tag=%h raddr=%0d",
                             $time, early_waddr, mem[early_waddr], early_wdata, raddr);
                end

                mem[early_waddr] <= early_wdata;

                if (early_waddr == raddr) begin
                    rdata <= early_wdata;
                end
            end

            if (DEBUG && refill_wen && early_wen) begin
                $display("[%0t] TAG_ARRAY SAME_CYCLE_REFILL_EARLY: early has final priority. early set=%0d tag=%h refill set=%0d tag=%h",
                         $time,
                         early_waddr,
                         early_wdata,
                         refill_waddr,
                         refill_wdata);
            end
        end
    end

endmodule
