// ============================================================
// Simple parameterized RAM with two write ports and one read port
// Port A has priority if both ports write the same address
// CPU side should connect to port A
// Refill side should connect to port B
// One-cycle synchronous read latency
// ============================================================

module RAM_2W1R #(
    parameter int D_WIDTH = 32,
    parameter int DEPTH   = 256
)(
    input  logic                         clk,


    // Port A: CPU
    input  logic                         wen_a,
    input  logic [$clog2(DEPTH)-1:0]     waddr_a,
    input  logic [D_WIDTH-1:0]           wdata_a,

    // Port B: Refill
    input  logic                         wen_b,
    input  logic [$clog2(DEPTH)-1:0]     waddr_b,
    input  logic [D_WIDTH-1:0]           wdata_b,

    // Read
    input  logic [$clog2(DEPTH)-1:0]     raddr,
    output logic [D_WIDTH-1:0]           rdata
);

    logic [D_WIDTH-1:0] mem [DEPTH-1:0];

    always_ff @(posedge clk) begin
    
            // One-cycle synchronous read
            rdata <= mem[raddr];

            // Port B write
            if (wen_b) begin
                mem[waddr_b] <= wdata_b;
            end

            // Port A write has priority if same address
            if (wen_a) begin
                mem[waddr_a] <= wdata_a;
            end
        
    end

endmodule