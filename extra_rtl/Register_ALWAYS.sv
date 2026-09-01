module Register_ALWAYS #(
  parameter int DWIDTH = 8
)(
  input  logic                  clk,

  input  logic [DWIDTH-1:0]     d,
  output logic [DWIDTH-1:0]     q
);

  always_ff @(posedge clk) begin
    q <= d;
  end

endmodule
