module RAM #(
    parameter int D_WIDTH = 32,
    parameter int DEPTH   = 256
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     wen,
    input  logic [$clog2(DEPTH)-1:0] waddr,
    input  logic [D_WIDTH-1:0]       wdata,

    input  logic [$clog2(DEPTH)-1:0] raddr,
    output logic [D_WIDTH-1:0]       rdata
);

    logic [D_WIDTH-1:0] mem [DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
            rdata <= '0;
        end
        else begin
            rdata <= mem[raddr];

            if (wen) begin
                mem[waddr] <= wdata;
            end
        end
    end

endmodule