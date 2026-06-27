// ============================================================
// Cache_timing
//
// Out-of-context timing wrapper for Cache.
// Registers DUT inputs and outputs.
// ============================================================

`timescale 1ns/1ps

module Cache_timing #(
    parameter int CACHE_BYTES = 1024,
    parameter int ASSOC       = 4
)(
    input  logic        clk,
    input  logic        rst,

    input  logic        cpu_req_valid,
    output logic        cpu_req_ready,
    input  logic        cpu_req_write,
    input  logic [31:0] cpu_req_addr,
    input  logic [31:0] cpu_req_wdata,
    input  logic [ 3:0] cpu_req_id,

    output logic        cpu_resp_valid,
    input  logic        cpu_resp_ready,
    output logic        cpu_resp_hit,
    output logic [31:0] cpu_resp_rdata,
    output logic [ 3:0] cpu_resp_id,

    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic        mem_req_write,
    output logic [31:0] mem_req_addr,
    output logic [31:0] mem_req_wdata,
    output logic [ 1:0] mem_req_id,

    input  logic        mem_resp_valid,
    output logic        mem_resp_ready,
    input  logic [ 1:0] mem_resp_id,
    input  logic [31:0] mem_resp_rdata
);

    logic        rst_r;

    logic        cpu_req_valid_r;
    logic        cpu_req_ready_s;
    logic        cpu_req_write_r;
    logic [31:0] cpu_req_addr_r;
    logic [31:0] cpu_req_wdata_r;
    logic [ 3:0] cpu_req_id_r;

    logic        cpu_resp_valid_s;
    logic        cpu_resp_ready_r;
    logic        cpu_resp_hit_s;
    logic [31:0] cpu_resp_rdata_s;
    logic [ 3:0] cpu_resp_id_s;

    logic        mem_req_valid_s;
    logic        mem_req_ready_r;
    logic        mem_req_write_s;
    logic [31:0] mem_req_addr_s;
    logic [31:0] mem_req_wdata_s;
    logic [ 1:0] mem_req_id_s;

    logic        mem_resp_valid_r;
    logic        mem_resp_ready_s;
    logic [ 1:0] mem_resp_id_r;
    logic [31:0] mem_resp_rdata_r;

    Cache #(
        .CACHE_BYTES (CACHE_BYTES),
        .ASSOC       (ASSOC)
    ) DUT (
        .clk            (clk),
        .rst            (rst_r),

        .cpu_req_valid  (cpu_req_valid_r),
        .cpu_req_ready  (cpu_req_ready_s),
        .cpu_req_write  (cpu_req_write_r),
        .cpu_req_addr   (cpu_req_addr_r),
        .cpu_req_wdata  (cpu_req_wdata_r),
        .cpu_req_id     (cpu_req_id_r),

        .cpu_resp_valid (cpu_resp_valid_s),
        .cpu_resp_ready (cpu_resp_ready_r),
        .cpu_resp_hit   (cpu_resp_hit_s),
        .cpu_resp_rdata (cpu_resp_rdata_s),
        .cpu_resp_id    (cpu_resp_id_s),

        .mem_req_valid  (mem_req_valid_s),
        .mem_req_ready  (mem_req_ready_r),
        .mem_req_write  (mem_req_write_s),
        .mem_req_addr   (mem_req_addr_s),
        .mem_req_wdata  (mem_req_wdata_s),
        .mem_req_id     (mem_req_id_s),

        .mem_resp_valid (mem_resp_valid_r),
        .mem_resp_ready (mem_resp_ready_s),
        .mem_resp_id    (mem_resp_id_r),
        .mem_resp_rdata (mem_resp_rdata_r)
    );

    always_ff @(posedge clk) begin
        rst_r <= rst;

        cpu_req_valid_r <= cpu_req_valid;
        cpu_req_write_r <= cpu_req_write;
        cpu_req_addr_r  <= cpu_req_addr;
        cpu_req_wdata_r <= cpu_req_wdata;
        cpu_req_id_r    <= cpu_req_id;

        cpu_resp_ready_r <= cpu_resp_ready;

        mem_req_ready_r <= mem_req_ready;

        mem_resp_valid_r <= mem_resp_valid;
        mem_resp_id_r    <= mem_resp_id;
        mem_resp_rdata_r <= mem_resp_rdata;

        cpu_req_ready  <= cpu_req_ready_s;

        cpu_resp_valid <= cpu_resp_valid_s;
        cpu_resp_hit   <= cpu_resp_hit_s;
        cpu_resp_rdata <= cpu_resp_rdata_s;
        cpu_resp_id    <= cpu_resp_id_s;

        mem_req_valid <= mem_req_valid_s;
        mem_req_write <= mem_req_write_s;
        mem_req_addr  <= mem_req_addr_s;
        mem_req_wdata <= mem_req_wdata_s;
        mem_req_id    <= mem_req_id_s;

        mem_resp_ready <= mem_resp_ready_s;
    end

endmodule
