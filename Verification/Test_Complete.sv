`timescale 1ns/1ps

import Test_Complete_pkg::*;

// Single testbench: runs associativity-major, one active DUT/RAM set at a time.
module Test_Complete #(
    parameter int CACHE_BYTES = 4096,
    parameter int ASSOC       = 0,

    // Forward/backpressure knobs. Values are probabilities from 0.0 to 1.0.
    parameter real CPU_REQ_VALID_PROBABILITY  = 1.0,
    parameter real CPU_RESP_READY_PROBABILITY = 1.0,

    // Per-associativity debug gates.
    // ASSOC=0 runs every associativity; ASSOC=1/2/4/8/16 runs only that one.
    // 0 = suppress all debug prints for that associativity.
    // 1 = allow each debug print only if that test's respective PRINT_* bit is also 1.
    parameter bit TOGGLE_ASSOC_DEBUG_1  = 1'b1,
    parameter bit TOGGLE_ASSOC_DEBUG_2  = 1'b1,
    parameter bit TOGGLE_ASSOC_DEBUG_4  = 1'b1,
    parameter bit TOGGLE_ASSOC_DEBUG_8  = 1'b1,
    parameter bit TOGGLE_ASSOC_DEBUG_16 = 1'b1
);

    // Verification knobs.
    localparam int TEST1_NUM_WRITES  = 10000;
    localparam int TEST1_NUM_READS   = 10000;

    localparam int TEST2_NUM_WRITES  = 10000;
    localparam int TEST2_NUM_READS   = 10000;

    // Test3 sweeps burst lengths to measure miss rate under controlled locality.
    localparam int TEST3_ADDR_POOL_SIZE       = 500;
    localparam int TEST3_REQUESTS_PER_SWEEP   = 10000;
    localparam int TEST3_NUM_BURST_LENGTHS    = 10;
    localparam int TEST3_TOTAL_REQUESTS       = TEST3_REQUESTS_PER_SWEEP * TEST3_NUM_BURST_LENGTHS;
    localparam int TEST3_LOCAL_WINDOW_MAX     = 32;
    localparam int TEST3_BASE_SEED            = 32'h1234_5678;

    localparam int TEST4_NUM_READS1  = 500;
    localparam int TEST4_NUM_WRITES  = 500;
    localparam int TEST4_NUM_READS2  = 500;

    localparam int TEST5_REPEAT_COUNT = 100;
    localparam int TEST5_NUM_LINES    = 25;

    localparam int TEST6_REPEAT_COUNT = 100;
    localparam int TEST6_NUM_LINES    = 100;

    localparam int TEST7_NUM_CYCLES   = 1000;
    localparam int TEST8_NUM_CYCLES   = 1000;
    localparam int TEST9_NUM_CYCLES   = 1000;
    localparam int TEST10_NUM_CYCLES  = 1000;

    localparam bit TEST1_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST1_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST1_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST1_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST1_PRINT_CHECKS     = 1'b0;
    localparam bit TEST1_PRINT_REPORT     = 1'b1;

    localparam bit TEST2_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST2_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST2_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST2_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST2_PRINT_CHECKS     = 1'b0;
    localparam bit TEST2_PRINT_REPORT     = 1'b1;

    localparam bit TEST3_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST3_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST3_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST3_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST3_PRINT_CHECKS     = 1'b0;
    localparam bit TEST3_PRINT_REPORT     = 1'b1;

    localparam bit TEST4_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST4_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST4_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST4_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST4_PRINT_CHECKS     = 1'b0;
    localparam bit TEST4_PRINT_REPORT     = 1'b1;

    localparam bit TEST5_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST5_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST5_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST5_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST5_PRINT_CHECKS     = 1'b0;
    localparam bit TEST5_PRINT_REPORT     = 1'b1;

    localparam bit TEST6_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST6_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST6_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST6_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST6_PRINT_CHECKS     = 1'b0;
    localparam bit TEST6_PRINT_REPORT     = 1'b1;

    localparam bit TEST7_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST7_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST7_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST7_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST7_PRINT_CHECKS     = 1'b0;
    localparam bit TEST7_PRINT_REPORT     = 1'b1;

    localparam bit TEST8_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST8_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST8_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST8_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST8_PRINT_CHECKS     = 1'b0;
    localparam bit TEST8_PRINT_REPORT     = 1'b1;

    localparam bit TEST9_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST9_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST9_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST9_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST9_PRINT_CHECKS     = 1'b0;
    localparam bit TEST9_PRINT_REPORT     = 1'b1;

    localparam bit TEST10_PRINT_CPU_REQS  = 1'b0;
    localparam bit TEST10_PRINT_CPU_RESPS = 1'b0;
    localparam bit TEST10_PRINT_MEM_REQS  = 1'b0;
    localparam bit TEST10_PRINT_MEM_RESPS = 1'b0;
    localparam bit TEST10_PRINT_CHECKS    = 1'b0;
    localparam bit TEST10_PRINT_REPORT    = 1'b1;

    localparam int CACHE_LINES = CACHE_BYTES / LINE_BYTES;
    // Downstream address space is word-addressed. For the default 4KB cache,
    // 16x gives 64K addressable downstream words.
    localparam int RAM_DEPTH_WORDS = CACHE_BYTES * 16;

    string ram_init_file_path;

    logic clk;
    logic rst;

    logic                    cpu_req_valid;
    logic                    cpu_req_write;
    logic [ADDR_WIDTH-1:0]   cpu_req_addr;
    logic [DATA_WIDTH-1:0]   cpu_req_wdata;
    logic [CPU_ID_WIDTH-1:0] cpu_req_id;
    logic                    cpu_req_ready;

    logic                    cpu_resp_valid;
    logic                    cpu_resp_ready;
    logic                    cpu_resp_hit;
    logic [DATA_WIDTH-1:0]   cpu_resp_rdata;
    logic [CPU_ID_WIDTH-1:0] cpu_resp_id;

    logic                     mem_req_valid;
    logic                     mem_req_write;
    logic [ADDR_WIDTH-1:0]    mem_req_addr;
    logic [DATA_WIDTH-1:0]    mem_req_wdata;
    logic [MSHR_ID_WIDTH-1:0] mem_req_id;

    logic                     mem_resp_valid;
    logic                     mem_resp_ready;
    logic [DATA_WIDTH-1:0]    mem_resp_rdata;
    logic [MSHR_ID_WIDTH-1:0] mem_resp_id;

    logic in_read_phase;
    int   active_test;
    int   active_num_writes;
    int   active_num_reads;
    int   active_assoc_idx = 0;
    int   active_assoc_value = 1;

    bit test_pass_by_assoc [1:TEST_LAST][0:NUM_ASSOC_CONFIGS-1];
    int test_data_errors_by_assoc [1:TEST_LAST][0:NUM_ASSOC_CONFIGS-1];

    bit test1_pass;
    bit test2_pass;
    bit test3_pass;
    bit test4_pass;
    bit test5_pass;
    bit test6_pass;
    bit test7_pass;
    bit test8_pass;
    bit test9_pass;
    bit test10_pass;

    int total_requests_by_assoc [0:NUM_ASSOC_CONFIGS-1];
    int test3_requests_by_assoc [0:NUM_ASSOC_CONFIGS-1];
    int test3_misses_by_assoc   [0:NUM_ASSOC_CONFIGS-1];
    longint unsigned hit_read_latency_total_by_assoc [0:NUM_ASSOC_CONFIGS-1];
    int              hit_read_latency_count_by_assoc [0:NUM_ASSOC_CONFIGS-1];

    int test3_write_count;
    int test3_read_count;
    int test3_addr_pool [0:TEST3_ADDR_POOL_SIZE-1];
    bit test3_phase_addr_used [0:RAM_DEPTH_WORDS-1];

    int total_cpu_requests_sent;
    int total_cpu_responses;
    int total_write_responses;
    int total_read_responses;

    int hit_count;
    int miss_count;
    int write_miss_count;
    int read_miss_count;
    longint unsigned hit_read_latency_total;
    int              hit_read_latency_count;

    int mem_req_valid_cycles;
    int mem_read_req_cycles;
    int mem_write_req_cycles;
    int mem_resp_count;

    int mem_req_valid_pulses;
    logic mem_req_valid_d;

    int write_phase_mem_write_req_cycles;
    int read_phase_mem_write_req_cycles;
    int write_phase_mem_read_req_cycles;
    int read_phase_mem_read_req_cycles;

    logic [DATA_WIDTH-1:0] golden_mem [0:RAM_DEPTH_WORDS-1];

    // Indexed by full request sequence, not by the 3-bit CPU slot.
    logic [DATA_WIDTH-1:0] expected_by_seq       [];
    logic                  expected_valid_by_seq [];
    logic                  read_done_by_seq      [];
    int                    expected_addr_by_seq  [];

    logic                  expected_is_read_by_seq  [];
    logic                  expected_is_write_by_seq [];
    longint unsigned       request_issue_cycle_by_seq [];
    logic                  request_issue_cycle_valid_by_seq [];

    int data_check_count;
    int data_error_count;
    int duplicate_resp_errors;
    int unexpected_resp_errors;
    int missing_resp_errors;

    int cpu_resp_count_by_seq [];

    // Slot state:
    // cpu_req_id/cpu_resp_id are only slot IDs.
    // slot_seq maps a live slot back to the full request sequence.
    bit slot_busy [0:CPU_SLOT_COUNT-1];
    int slot_seq  [0:CPU_SLOT_COUNT-1];
    int slot_addr [0:CPU_SLOT_COUNT-1];
    bit outstanding_addr_busy [0:RAM_DEPTH_WORDS-1];

    int expected_total_line_allocations;
    int expected_replacements_after_full;
    int expected_refill_transactions;

    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_cpu_req_valid;
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_cpu_req_write;
    logic [ADDR_WIDTH-1:0]                           dut_cpu_req_addr  [0:NUM_ASSOC_CONFIGS-1];
    logic [DATA_WIDTH-1:0]                           dut_cpu_req_wdata [0:NUM_ASSOC_CONFIGS-1];
    logic [CPU_ID_WIDTH-1:0]                         dut_cpu_req_id    [0:NUM_ASSOC_CONFIGS-1];
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_cpu_req_ready;

    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_cpu_resp_valid;
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_cpu_resp_ready;
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_cpu_resp_hit;
    logic [DATA_WIDTH-1:0]                           dut_cpu_resp_rdata [0:NUM_ASSOC_CONFIGS-1];
    logic [CPU_ID_WIDTH-1:0]                         dut_cpu_resp_id    [0:NUM_ASSOC_CONFIGS-1];

    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_mem_req_valid;
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_mem_req_write;
    logic [ADDR_WIDTH-1:0]                           dut_mem_req_addr  [0:NUM_ASSOC_CONFIGS-1];
    logic [DATA_WIDTH-1:0]                           dut_mem_req_wdata [0:NUM_ASSOC_CONFIGS-1];
    logic [MSHR_ID_WIDTH-1:0]                        dut_mem_req_id    [0:NUM_ASSOC_CONFIGS-1];

    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_mem_resp_valid;
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_mem_resp_ready;
    logic [DATA_WIDTH-1:0]                           dut_mem_resp_rdata [0:NUM_ASSOC_CONFIGS-1];
    logic [MSHR_ID_WIDTH-1:0]                        dut_mem_resp_id    [0:NUM_ASSOC_CONFIGS-1];

    function automatic bit chance(input real p);
        begin
            if ((p < 0.0) || (p > 1.0))
                $fatal(1, "Invalid probability in chance(): %0.3f", p);

            if (p >= 1.0)
                chance = 1'b1;
            else if (p <= 0.0)
                chance = 1'b0;
            else
                chance = ($urandom < (p * (2.0 ** 32)));
        end
    endfunction

    task automatic init_golden_mem;
        begin
            for (int i = 0; i < RAM_DEPTH_WORDS; i++) begin
                golden_mem[i] = DATA_WIDTH'(32'h1000_0000 + i);
            end

            $readmemh(ram_init_file_path, golden_mem);
        end
    endtask


    initial begin
        clk = 1'b0;
        ram_init_file_path = resolve_ram_init_file();
        $display("Test_Complete loading init file: %s", ram_init_file_path);
        init_golden_mem();
    end

    always #5 clk = ~clk;

    genvar assoc_gen;

    generate
        for (assoc_gen = 0; assoc_gen < NUM_ASSOC_CONFIGS; assoc_gen++) begin : GEN_ASSOC_SET
            localparam int THIS_ASSOC = (assoc_gen == ASSOC_IDX_1)  ? 1  :
                                        (assoc_gen == ASSOC_IDX_2)  ? 2  :
                                        (assoc_gen == ASSOC_IDX_4)  ? 4  :
                                        (assoc_gen == ASSOC_IDX_8)  ? 8  : 16;

            Cache #(
                .CACHE_BYTES (CACHE_BYTES),
                .ASSOC       (THIS_ASSOC)
            ) DUT (
                .clk            (clk),
                .rst            (rst),

                .cpu_req_valid  (dut_cpu_req_valid[assoc_gen]),
                .cpu_req_ready  (dut_cpu_req_ready[assoc_gen]),
                .cpu_req_write  (dut_cpu_req_write[assoc_gen]),
                .cpu_req_addr   (dut_cpu_req_addr[assoc_gen]),
                .cpu_req_wdata  (dut_cpu_req_wdata[assoc_gen]),
                .cpu_req_id     (dut_cpu_req_id[assoc_gen]),

                .cpu_resp_valid (dut_cpu_resp_valid[assoc_gen]),
                .cpu_resp_ready (dut_cpu_resp_ready[assoc_gen]),
                .cpu_resp_hit   (dut_cpu_resp_hit[assoc_gen]),
                .cpu_resp_rdata (dut_cpu_resp_rdata[assoc_gen]),
                .cpu_resp_id    (dut_cpu_resp_id[assoc_gen]),

                .mem_req_valid  (dut_mem_req_valid[assoc_gen]),
                .mem_req_write  (dut_mem_req_write[assoc_gen]),
                .mem_req_addr   (dut_mem_req_addr[assoc_gen]),
                .mem_req_wdata  (dut_mem_req_wdata[assoc_gen]),
                .mem_req_id     (dut_mem_req_id[assoc_gen]),

                .mem_resp_valid (dut_mem_resp_valid[assoc_gen]),
                .mem_resp_ready (dut_mem_resp_ready[assoc_gen]),
                .mem_resp_id    (dut_mem_resp_id[assoc_gen]),
                .mem_resp_rdata (dut_mem_resp_rdata[assoc_gen])
            );

            RAM_ID #(
                .ADDR_WIDTH   (ADDR_WIDTH),
                .D_WIDTH      (DATA_WIDTH),
                .DEPTH        (RAM_DEPTH_WORDS),
                .ID_WIDTH     (MSHR_ID_WIDTH),
                .READ_LATENCY (RAM_READ_LATENCY),
                .INIT_FILE    (RAM_INIT_FILE)
            ) MEM (
                .clk          (clk),
                .rst          (rst),

                .req_valid    (dut_mem_req_valid[assoc_gen]),
                .req_write    (dut_mem_req_write[assoc_gen]),
                .req_addr     (dut_mem_req_addr[assoc_gen]),
                .req_wdata    (dut_mem_req_wdata[assoc_gen]),
                .req_id       (dut_mem_req_id[assoc_gen]),

                .resp_valid   (dut_mem_resp_valid[assoc_gen]),
                .resp_ready   (dut_mem_resp_ready[assoc_gen]),
                .resp_rdata   (dut_mem_resp_rdata[assoc_gen]),
                .resp_id      (dut_mem_resp_id[assoc_gen])
            );
        end
    endgenerate

    always_comb begin
        for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
            dut_cpu_req_valid[a]  = 1'b0;
            dut_cpu_req_write[a]  = 1'b0;
            dut_cpu_req_addr[a]   = '0;
            dut_cpu_req_wdata[a]  = '0;
            dut_cpu_req_id[a]     = '0;

            // Keep every DUT response path drained. Only the active DUT is
            // monitored by the scoreboard, but inactive DUTs should never be
            // artificially backpressured by the sweep mux.
            dut_cpu_resp_ready[a] = 1'b1;
        end

        dut_cpu_req_valid[active_assoc_idx]  = cpu_req_valid;
        dut_cpu_req_write[active_assoc_idx]  = cpu_req_write;
        dut_cpu_req_addr[active_assoc_idx]   = cpu_req_addr;
        dut_cpu_req_wdata[active_assoc_idx]  = cpu_req_wdata;
        dut_cpu_req_id[active_assoc_idx]     = cpu_req_id;
        dut_cpu_resp_ready[active_assoc_idx] = cpu_resp_ready;

        cpu_req_ready  = dut_cpu_req_ready[active_assoc_idx];
        cpu_resp_valid = dut_cpu_resp_valid[active_assoc_idx];
        cpu_resp_hit   = dut_cpu_resp_hit[active_assoc_idx];
        cpu_resp_rdata = dut_cpu_resp_rdata[active_assoc_idx];
        cpu_resp_id    = dut_cpu_resp_id[active_assoc_idx];

        mem_req_valid  = dut_mem_req_valid[active_assoc_idx];
        mem_req_write  = dut_mem_req_write[active_assoc_idx];
        mem_req_addr   = dut_mem_req_addr[active_assoc_idx];
        mem_req_wdata  = dut_mem_req_wdata[active_assoc_idx];
        mem_req_id     = dut_mem_req_id[active_assoc_idx];

        mem_resp_valid = dut_mem_resp_valid[active_assoc_idx];
        mem_resp_ready = dut_mem_resp_ready[active_assoc_idx];
        mem_resp_rdata = dut_mem_resp_rdata[active_assoc_idx];
        mem_resp_id    = dut_mem_resp_id[active_assoc_idx];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cpu_resp_ready <= 1'b1;
        end
        else begin
            cpu_resp_ready <= chance(CPU_RESP_READY_PROBABILITY);
        end
    end


    `include "Test_Complete_helpers.svh"
    `include "Test_Complete_monitors.svh"
    `include "Test_Complete_runner.svh"

endmodule
