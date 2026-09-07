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
            `GLS_NETLIST_MODULE u (.*);
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
