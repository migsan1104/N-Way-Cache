// GLS copy of the OpenRAM simulation model (xcelium/GLS.md step 0, 2026-09-07).
// The synthesis/P&R netlists instantiate the macro with a 4-bit wmask1 port
// (present in the .lib the flow binds, tied to 4'b0; absent from the OpenRAM
// LEF/GDS and from this behavioural model). Added here as an ignored input so
// the netlists elaborate. Everything else is the extra_rtl model verbatim.
// Quiet copy of the OpenRAM simulation model (vendored 2026-08-20 from
// the sky130A PDK). Functionally identical; the per-operation
// "Reading"/"Writing" $display statements are stubbed to null statements
// (they printed once per macro per cycle and produced multi-GB
// transcripts). The same-address collision WARNING is kept. Used by the
// VERIFICATION file lists only; synthesis binds the PDK .lib instead.
// OpenRAM SRAM model
// Words: 256
// Word size: 32
// Write size: 8

module sram_1rw1r_32_256_8_sky130(
// Port 0: RW
    clk0,csb0,web0,wmask0,addr0,din0,dout0,
// Port 1: R
    clk1,csb1,addr1,dout1,wmask1
  );

  parameter NUM_WMASKS = 4 ;
  parameter DATA_WIDTH = 32 ;
  parameter ADDR_WIDTH = 8 ;
  parameter RAM_DEPTH = 1 << ADDR_WIDTH;
  // FIXME: This delay is arbitrary.
  parameter DELAY = 0.3 ;

  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [NUM_WMASKS-1:0]   wmask0; // write mask
  input [3:0]              wmask1; // GLS shim: unused (write mask of the read-only port)
  input [ADDR_WIDTH-1:0]  addr0;
  input [DATA_WIDTH-1:0]  din0;
  output [DATA_WIDTH-1:0] dout0;
  input  clk1; // clock
  input   csb1; // active low chip select
  input [ADDR_WIDTH-1:0]  addr1;

  output [DATA_WIDTH-1:0] dout1;

  reg  csb0_reg;
  reg  web0_reg;
  reg [NUM_WMASKS-1:0]   wmask0_reg;
  reg [ADDR_WIDTH-1:0]  addr0_reg;
  reg [DATA_WIDTH-1:0]  din0_reg;
  reg [DATA_WIDTH-1:0]  dout0;

  // All inputs are registers
  always @(posedge clk0)
  begin
    csb0_reg = csb0;
    web0_reg = web0;
    wmask0_reg = wmask0;
    addr0_reg = addr0;
    din0_reg = din0;
    // nox: hold dout0 when deselected
    if ( !csb0_reg && web0_reg ) 
      ; // quiet: per-op display stubbed
    if ( !csb0_reg && !web0_reg )
      ; // quiet: per-op display stubbed
  end

  reg  csb1_reg;
  reg [ADDR_WIDTH-1:0]  addr1_reg;
  reg [DATA_WIDTH-1:0]  dout1;

  // All inputs are registers
  always @(posedge clk1)
  begin
    csb1_reg = csb1;
    addr1_reg = addr1;
    if (!csb0 && !web0 && !csb1 && (addr0 == addr1))
         $display($time," WARNING: Writing and reading addr0=%b and addr1=%b simultaneously!",addr0,addr1);
    // nox: hold dout1 when deselected
    if ( !csb1_reg ) 
      ; // quiet: per-op display stubbed
  end

reg [DATA_WIDTH-1:0]    mem [0:RAM_DEPTH-1];
  integer nox_i; initial begin for (nox_i=0; nox_i<RAM_DEPTH; nox_i=nox_i+1) mem[nox_i] = {DATA_WIDTH{1'b0}}; dout0 = 0; dout1 = 0; end

  // Memory Write Block Port 0
  // Write Operation : When web0 = 0, csb0 = 0
  always @ (negedge clk0)
  begin : MEM_WRITE0
    if ( !csb0_reg && !web0_reg ) begin
        if (wmask0_reg[0])
                mem[addr0_reg][7:0] = din0_reg[7:0];
        if (wmask0_reg[1])
                mem[addr0_reg][15:8] = din0_reg[15:8];
        if (wmask0_reg[2])
                mem[addr0_reg][23:16] = din0_reg[23:16];
        if (wmask0_reg[3])
                mem[addr0_reg][31:24] = din0_reg[31:24];
    end
  end

  // Memory Read Block Port 0
  // Read Operation : When web0 = 1, csb0 = 0
  always @ (negedge clk0)
  begin : MEM_READ0
    if (!csb0_reg && web0_reg)
       dout0 <= #(DELAY) mem[addr0_reg];
  end

  // Memory Read Block Port 1
  // Read Operation : When web1 = 1, csb1 = 0
  always @ (negedge clk1)
  begin : MEM_READ1
    if (!csb1_reg)
       dout1 <= #(DELAY) mem[addr1_reg];
  end

endmodule
