// Cache_gls_wrap.sv - gate-level-simulation shim (2026-09-07).
// Test_Complete instantiates `TC_DUT_MODULE (see Test_Complete.sv); under
// +define+GLS that is this wrapper, which drops the P&R netlist of the
// 16KB / ASSOC=4 / SRAM-macro configuration in for that one DUT and keeps
// the RTL for the other four associativities. No hierarchical references
// into DUT exist in the testbench, so the extra level (DUT.u) is harmless.
// The netlist module name is Innovus's RUN_TAG; override with
// +define+GLS_NETLIST_MODULE=<name> if a different export is simulated.
`ifndef GLS_NETLIST_MODULE
  `define GLS_NETLIST_MODULE Cache_CACHE_BYTES16384_ASSOC4_EN_SRAM_MACRO1
`endif
module Cache_gls_wrap #(
    parameter int CACHE_BYTES     = 4096,
    parameter int ASSOC           = 4,
    parameter bit EN_SRAM_MACRO   = 1'b0,
    parameter bit TAG_READ_ONEHOT = 1'b0
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        cpu_req_valid,
    output logic        cpu_req_ready,
    input  logic        cpu_req_write,
    input  logic [31:0] cpu_req_addr,
    input  logic [31:0] cpu_req_wdata,
    input  logic [3:0]  cpu_req_id,
    output logic        cpu_resp_valid,
    input  logic        cpu_resp_ready,
    output logic        cpu_resp_hit,
    output logic [31:0] cpu_resp_rdata,
    output logic [3:0]  cpu_resp_id,
    output logic        mem_req_valid,
    output logic        mem_req_write,
    output logic [31:0] mem_req_addr,
    output logic [31:0] mem_req_wdata,
    output logic [1:0]  mem_req_id,
    input  logic        mem_resp_valid,
    output logic        mem_resp_ready,
    input  logic [1:0]  mem_resp_id,
    input  logic [31:0] mem_resp_rdata
);
    generate
        if (CACHE_BYTES == 16384 && ASSOC == 4 && EN_SRAM_MACRO) begin : g_gate
`ifdef GLS_IN_DELAY
            // Input-delay contract (2026-09-09). The testbench drives DUT inputs
            // at its clock edge with no delay. With GLS_IO_LATENCY equal to the
            // clock-tree insertion delay that edge lands 7 ps BEFORE the I/O
            // registers' clock (ref pin 3.607, io_regs group 3.637-3.864 on
            // iter26b), so those flops capture each request a cycle early:
            // hit latency read 2.93 cycles against 4.15 in RTL. The signoff SDC
            // promises inputs 0.700 ns after the reference-pin edge; this
            // transport delay applies that promise to every input but clk.
            logic        rst_d, cpu_req_valid_d, cpu_req_write_d, cpu_resp_ready_d, mem_resp_valid_d;
            logic [31:0] cpu_req_addr_d, cpu_req_wdata_d, mem_resp_rdata_d;
            logic [3:0]  cpu_req_id_d;
            logic [1:0]  mem_resp_id_d;
            always @* begin
                rst_d            <= #(`GLS_IN_DELAY) rst;
                cpu_req_valid_d  <= #(`GLS_IN_DELAY) cpu_req_valid;
                cpu_req_write_d  <= #(`GLS_IN_DELAY) cpu_req_write;
                cpu_req_addr_d   <= #(`GLS_IN_DELAY) cpu_req_addr;
                cpu_req_wdata_d  <= #(`GLS_IN_DELAY) cpu_req_wdata;
                cpu_req_id_d     <= #(`GLS_IN_DELAY) cpu_req_id;
                cpu_resp_ready_d <= #(`GLS_IN_DELAY) cpu_resp_ready;
                mem_resp_valid_d <= #(`GLS_IN_DELAY) mem_resp_valid;
                mem_resp_id_d    <= #(`GLS_IN_DELAY) mem_resp_id;
                mem_resp_rdata_d <= #(`GLS_IN_DELAY) mem_resp_rdata;
            end
            `GLS_NETLIST_MODULE u (
                .rst(rst_d), .cpu_req_valid(cpu_req_valid_d), .cpu_req_write(cpu_req_write_d),
                .cpu_req_addr(cpu_req_addr_d), .cpu_req_wdata(cpu_req_wdata_d), .cpu_req_id(cpu_req_id_d),
                .cpu_resp_ready(cpu_resp_ready_d), .mem_resp_valid(mem_resp_valid_d),
                .mem_resp_id(mem_resp_id_d), .mem_resp_rdata(mem_resp_rdata_d), .*);
`else
            `GLS_NETLIST_MODULE u (.*);
`endif
            // Post-layout: annotate the SDF on this instance directly. An
            // xrun -sdf_cmd file needs the scope as a string, and the
            // generate-block path (GEN_ASSOC_SET[2].DUT.g_gate.u) was not
            // accepted (SDFSNF, 2026-09-07); $sdf_annotate resolves `u` itself.
            // GLS_SDF_FILE / GLS_SDF_MTM are quoted-string defines from
            // xcelium/run_gls.sh; without GLS_SDF_FILE nothing is annotated.
`ifdef GLS_SDF_FILE
            initial begin
                $display("GLS: annotating %s (MTM %s) on %m.u", `GLS_SDF_FILE, `GLS_SDF_MTM);
                $sdf_annotate(`GLS_SDF_FILE, u, , "logs/gls_sdf_annotate.log", `GLS_SDF_MTM);
            end
`endif
        end else begin : g_rtl
            Cache #(
                .CACHE_BYTES     (CACHE_BYTES),
                .ASSOC           (ASSOC),
                .EN_SRAM_MACRO   (EN_SRAM_MACRO),
                .TAG_READ_ONEHOT (TAG_READ_ONEHOT)
            ) u (.*);
        end
    endgenerate
endmodule
