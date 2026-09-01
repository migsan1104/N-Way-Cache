module Register #(
  parameter int DWIDTH = 8
)(
  input  logic                  clk,
  input  logic                  rst,

  input  logic [DWIDTH-1:0]     d,
  output logic [DWIDTH-1:0]     q
);

  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      q <= '0;
    else
      q <= d;
  end

endmodule
