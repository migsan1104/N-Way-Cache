`timescale 1ns/1ps

// Single testbench: runs associativity-major, one active DUT/RAM set at a time.
module Test_Complete #(
    // Per-associativity debug gates.
    // Tests always run for every associativity.
    // 0 = suppress all debug prints for that associativity.
    // 1 = allow each debug print only if that test's respective PRINT_* bit is also 1.
    parameter bit TOGGLE_ASSOC_DEBUG_1  = 1'b0,
    parameter bit TOGGLE_ASSOC_DEBUG_2  = 1'b0,
    parameter bit TOGGLE_ASSOC_DEBUG_4  = 1'b0,
    parameter bit TOGGLE_ASSOC_DEBUG_8  = 1'b0,
    parameter bit TOGGLE_ASSOC_DEBUG_16 = 1'b1
);

    localparam int ADDR_WIDTH        = 32;
    localparam int DATA_WIDTH        = 32;
    localparam int MAX_TEST_REQUESTS = 1000;

    // CPU-visible IDs are slots, not unique request numbers.
    // Only 8 requests may be in flight at once, but total requests may be much larger.
    localparam int CPU_ID_WIDTH      = 3;
    localparam int CPU_SLOT_COUNT    = (1 << CPU_ID_WIDTH);

    localparam int MSHR_ID_WIDTH     = 2;

    localparam int CACHE_BYTES       = 1024;
    localparam int LINE_BYTES        = 16;
    localparam int NUM_ASSOC_CONFIGS  = 5;

    localparam int ASSOC_IDX_1        = 0;
    localparam int ASSOC_IDX_2        = 1;
    localparam int ASSOC_IDX_4        = 2;
    localparam int ASSOC_IDX_8        = 3;
    localparam int ASSOC_IDX_16       = 4;

    localparam int WORDS_PER_LINE    = LINE_BYTES / (DATA_WIDTH / 8);
    localparam int CACHE_LINES       = CACHE_BYTES / LINE_BYTES;

    localparam int RAM_DEPTH_WORDS   = 1024;
    localparam int RAM_READ_LATENCY  = 20;

    localparam string RAM_INIT_FILE  = "downstream_init.hex";

    localparam int TEST1_NUM_WRITES  = 300;
    localparam int TEST1_NUM_READS   = 300;

    localparam int TEST2_NUM_WRITES  = 200;
    localparam int TEST2_NUM_READS   = 200;

    // Test3 is burst based. Only TEST3_BURSTS is meant to be changed.
    // Each burst sends exactly burst size random read/write requests, then reseeds.
    localparam int TEST3_BURSTS      = 10;
    localparam int TEST3_BURST_SIZE  = 8;
    localparam int TEST3_BASE_SEED   = 32'h1234_5678;

    localparam int TEST4_NUM_READS1  = 100;
    localparam int TEST4_NUM_WRITES  = 100;
    localparam int TEST4_NUM_READS2  = 100;

    localparam int TEST5_REPEAT_COUNT = 20;
    localparam int TEST5_NUM_LINES    = 20;

    localparam int TEST6_REPEAT_COUNT = 10;
    localparam int TEST6_NUM_LINES    = 10;

    localparam int TEST1 = 1;
    localparam int TEST2 = 2;
    localparam int TEST3 = 3;
    localparam int TEST4 = 4;
    localparam int TEST5 = 5;
    localparam int TEST6 = 6;

    localparam bit TEST1_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST1_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST1_PRINT_MEM_REQS   = 1'b0;
    localparam bit TEST1_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST1_PRINT_CHECKS     = 1'b0;
    localparam bit TEST1_PRINT_REPORT     = 1'b1;

    localparam bit TEST2_PRINT_CPU_REQS   = 1'b0;
    localparam bit TEST2_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST2_PRINT_MEM_REQS   = 1'b1;
    localparam bit TEST2_PRINT_MEM_RESPS  = 1'b0;
    localparam bit TEST2_PRINT_CHECKS     = 1'b0;
    localparam bit TEST2_PRINT_REPORT     = 1'b1;

    localparam bit TEST3_PRINT_CPU_REQS   = 1'b1;
    localparam bit TEST3_PRINT_CPU_RESPS  = 1'b0;
    localparam bit TEST3_PRINT_MEM_REQS   = 1'b1;
    localparam bit TEST3_PRINT_MEM_RESPS  = 1'b1;
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
    logic                     mem_req_ready;
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

    bit test_pass_by_assoc [1:6][0:NUM_ASSOC_CONFIGS-1];
    int test_data_errors_by_assoc [1:6][0:NUM_ASSOC_CONFIGS-1];

    bit test1_pass;
    bit test2_pass;
    bit test3_pass;
    bit test4_pass;
    bit test5_pass;
    bit test6_pass;

    int test3_write_count;
    int test3_read_count;

    int total_cpu_requests_sent;
    int total_cpu_responses;
    int total_write_responses;
    int total_read_responses;

    int hit_count;
    int miss_count;
    int write_miss_count;
    int read_miss_count;

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
    logic [DATA_WIDTH-1:0] expected_by_seq       [0:MAX_TEST_REQUESTS-1];
    logic                  expected_valid_by_seq [0:MAX_TEST_REQUESTS-1];
    logic                  read_done_by_seq      [0:MAX_TEST_REQUESTS-1];
    int                    expected_addr_by_seq  [0:MAX_TEST_REQUESTS-1];

    logic                  expected_is_read_by_seq  [0:MAX_TEST_REQUESTS-1];
    logic                  expected_is_write_by_seq [0:MAX_TEST_REQUESTS-1];

    int data_check_count;
    int data_error_count;
    int duplicate_resp_errors;
    int unexpected_resp_errors;
    int missing_resp_errors;

    int cpu_resp_count_by_seq [0:MAX_TEST_REQUESTS-1];

    // Slot state:
    // cpu_req_id/cpu_resp_id are only slot IDs.
    // slot_seq maps a live slot back to the full request sequence.
    bit slot_busy [0:CPU_SLOT_COUNT-1];
    int slot_seq  [0:CPU_SLOT_COUNT-1];

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
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_mem_req_ready;
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_mem_req_write;
    logic [ADDR_WIDTH-1:0]                           dut_mem_req_addr  [0:NUM_ASSOC_CONFIGS-1];
    logic [DATA_WIDTH-1:0]                           dut_mem_req_wdata [0:NUM_ASSOC_CONFIGS-1];
    logic [MSHR_ID_WIDTH-1:0]                        dut_mem_req_id    [0:NUM_ASSOC_CONFIGS-1];

    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_mem_resp_valid;
    logic [NUM_ASSOC_CONFIGS-1:0]                    dut_mem_resp_ready;
    logic [DATA_WIDTH-1:0]                           dut_mem_resp_rdata [0:NUM_ASSOC_CONFIGS-1];
    logic [MSHR_ID_WIDTH-1:0]                        dut_mem_resp_id    [0:NUM_ASSOC_CONFIGS-1];

    initial begin
        clk = 1'b0;
        $readmemh(RAM_INIT_FILE, golden_mem);
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
                .mem_req_ready  (dut_mem_req_ready[assoc_gen]),
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
                .req_ready    (dut_mem_req_ready[assoc_gen]),
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
        mem_req_ready  = dut_mem_req_ready[active_assoc_idx];
        mem_req_write  = dut_mem_req_write[active_assoc_idx];
        mem_req_addr   = dut_mem_req_addr[active_assoc_idx];
        mem_req_wdata  = dut_mem_req_wdata[active_assoc_idx];
        mem_req_id     = dut_mem_req_id[active_assoc_idx];

        mem_resp_valid = dut_mem_resp_valid[active_assoc_idx];
        mem_resp_ready = dut_mem_resp_ready[active_assoc_idx];
        mem_resp_rdata = dut_mem_resp_rdata[active_assoc_idx];
        mem_resp_id    = dut_mem_resp_id[active_assoc_idx];
    end

    assign cpu_resp_ready = 1'b1;

    function automatic int assoc_value_from_idx(input int assoc_idx);
        begin
            if (assoc_idx == ASSOC_IDX_1)
                assoc_value_from_idx = 1;
            else if (assoc_idx == ASSOC_IDX_2)
                assoc_value_from_idx = 2;
            else if (assoc_idx == ASSOC_IDX_4)
                assoc_value_from_idx = 4;
            else if (assoc_idx == ASSOC_IDX_8)
                assoc_value_from_idx = 8;
            else
                assoc_value_from_idx = 16;
        end
    endfunction

    function automatic bit assoc_debug_enabled(input int assoc_idx);
        begin
            if (assoc_idx == ASSOC_IDX_1)
                assoc_debug_enabled = TOGGLE_ASSOC_DEBUG_1;
            else if (assoc_idx == ASSOC_IDX_2)
                assoc_debug_enabled = TOGGLE_ASSOC_DEBUG_2;
            else if (assoc_idx == ASSOC_IDX_4)
                assoc_debug_enabled = TOGGLE_ASSOC_DEBUG_4;
            else if (assoc_idx == ASSOC_IDX_8)
                assoc_debug_enabled = TOGGLE_ASSOC_DEBUG_8;
            else
                assoc_debug_enabled = TOGGLE_ASSOC_DEBUG_16;
        end
    endfunction


    task automatic record_assoc_result(input int test_id, input bit pass, input int errors);
        begin
            test_pass_by_assoc[test_id][active_assoc_idx] = pass;
            test_data_errors_by_assoc[test_id][active_assoc_idx] = errors;
        end
    endtask

    function automatic string pass_fail(input bit pass);
        begin
            pass_fail = pass ? "PASSED" : "FAILED";
        end
    endfunction

    function automatic string test_status_line(input int test_id, input int assoc_idx);
        begin
            if (test_pass_by_assoc[test_id][assoc_idx])
                test_status_line = $sformatf("Associativity %0d %s PASSED data errors 0",
                                             assoc_value_from_idx(assoc_idx),
                                             test_name(test_id));
            else
                test_status_line = $sformatf("Associativity %0d %s FAILED data errors %0d",
                                             assoc_value_from_idx(assoc_idx),
                                             test_name(test_id),
                                             test_data_errors_by_assoc[test_id][assoc_idx]);
        end
    endfunction

    function automatic string test_name(input int test_id);
        begin
            if (test_id == TEST1)
                test_name = "Test1";
            else if (test_id == TEST2)
                test_name = "Test2";
            else if (test_id == TEST3)
                test_name = "Test3";
            else if (test_id == TEST4)
                test_name = "Test4";
            else if (test_id == TEST5)
                test_name = "Test5";
            else
                test_name = "Test6";
        end
    endfunction

    function automatic bit print_cpu_reqs(input int test_id);
        begin
            if (test_id == TEST1)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST1_PRINT_CPU_REQS;
            else if (test_id == TEST2)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST2_PRINT_CPU_REQS;
            else if (test_id == TEST3)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST3_PRINT_CPU_REQS;
            else if (test_id == TEST4)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST4_PRINT_CPU_REQS;
            else if (test_id == TEST5)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST5_PRINT_CPU_REQS;
            else
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_CPU_REQS;
        end
    endfunction

    function automatic bit print_cpu_resps(input int test_id);
        begin
            if (test_id == TEST1)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST1_PRINT_CPU_RESPS;
            else if (test_id == TEST2)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST2_PRINT_CPU_RESPS;
            else if (test_id == TEST3)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST3_PRINT_CPU_RESPS;
            else if (test_id == TEST4)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST4_PRINT_CPU_RESPS;
            else if (test_id == TEST5)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST5_PRINT_CPU_RESPS;
            else
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_CPU_RESPS;
        end
    endfunction

    function automatic bit print_mem_reqs(input int test_id);
        begin
            if (test_id == TEST1)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST1_PRINT_MEM_REQS;
            else if (test_id == TEST2)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST2_PRINT_MEM_REQS;
            else if (test_id == TEST3)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST3_PRINT_MEM_REQS;
            else if (test_id == TEST4)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST4_PRINT_MEM_REQS;
            else if (test_id == TEST5)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST5_PRINT_MEM_REQS;
            else
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_MEM_REQS;
        end
    endfunction

    function automatic bit print_mem_resps(input int test_id);
        begin
            if (test_id == TEST1)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST1_PRINT_MEM_RESPS;
            else if (test_id == TEST2)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST2_PRINT_MEM_RESPS;
            else if (test_id == TEST3)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST3_PRINT_MEM_RESPS;
            else if (test_id == TEST4)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST4_PRINT_MEM_RESPS;
            else if (test_id == TEST5)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST5_PRINT_MEM_RESPS;
            else
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_MEM_RESPS;
        end
    endfunction

    function automatic bit print_checks(input int test_id);
        begin
            if (test_id == TEST1)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST1_PRINT_CHECKS;
            else if (test_id == TEST2)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST2_PRINT_CHECKS;
            else if (test_id == TEST3)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST3_PRINT_CHECKS;
            else if (test_id == TEST4)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST4_PRINT_CHECKS;
            else if (test_id == TEST5)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST5_PRINT_CHECKS;
            else
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_CHECKS;
        end
    endfunction

    function automatic bit print_report_en(input int test_id);
        begin
            if (test_id == TEST1)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST1_PRINT_REPORT;
            else if (test_id == TEST2)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST2_PRINT_REPORT;
            else if (test_id == TEST3)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST3_PRINT_REPORT;
            else if (test_id == TEST4)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST4_PRINT_REPORT;
            else if (test_id == TEST5)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST5_PRINT_REPORT;
            else
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_REPORT;
        end
    endfunction

    // CPU address is WORD-addressed.
    // cpu_addr[1:0] is the word offset inside the 4-word line.
    function automatic [ADDR_WIDTH-1:0] make_addr(input int test_id, input int i);
        begin
            if ((test_id == TEST1) || (test_id == TEST4)) begin
                make_addr = ADDR_WIDTH'(i);
            end
            else if (test_id == TEST5) begin
                make_addr = ADDR_WIDTH'(i * WORDS_PER_LINE);
            end
            else if (test_id == TEST6) begin
                make_addr = ADDR_WIDTH'(i);
            end
            else begin
                make_addr = ADDR_WIDTH'((i * WORDS_PER_LINE) + 2);
            end
        end
    endfunction

    function automatic [DATA_WIDTH-1:0] make_wdata(input int test_id, input int i);
        begin
            if ((test_id == TEST1) || (test_id == TEST4))
                make_wdata = DATA_WIDTH'(i + 1);
            else if (test_id == TEST5)
                make_wdata = DATA_WIDTH'(32'h5000_0000 + i);
            else if (test_id == TEST6)
                make_wdata = DATA_WIDTH'(32'h6000_0000 + i);
            else
                make_wdata = DATA_WIDTH'(32'hA000_0000 + i);
        end
    endfunction

    function automatic int find_free_slot;
        begin
            find_free_slot = -1;

            for (int s = 0; s < CPU_SLOT_COUNT; s++) begin
                if (!slot_busy[s] && (find_free_slot == -1))
                    find_free_slot = s;
            end
        end
    endfunction

    task automatic drive_idle;
        begin
            cpu_req_valid <= 1'b0;
            cpu_req_write <= 1'b0;
            cpu_req_addr  <= '0;
            cpu_req_wdata <= '0;
            cpu_req_id    <= '0;
        end
    endtask

    task automatic clear_scoreboard;
        begin
            total_cpu_requests_sent = 0;
            total_cpu_responses     = 0;
            total_write_responses   = 0;
            total_read_responses    = 0;

            hit_count               = 0;
            miss_count              = 0;
            write_miss_count        = 0;
            read_miss_count         = 0;

            data_check_count        = 0;
            data_error_count        = 0;
            duplicate_resp_errors   = 0;
            unexpected_resp_errors  = 0;
            missing_resp_errors     = 0;

            mem_req_valid_cycles             = 0;
            mem_read_req_cycles              = 0;
            mem_write_req_cycles             = 0;
            write_phase_mem_write_req_cycles = 0;
            read_phase_mem_write_req_cycles  = 0;
            write_phase_mem_read_req_cycles  = 0;
            read_phase_mem_read_req_cycles   = 0;
            mem_req_valid_pulses             = 0;
            mem_req_valid_d                  = 1'b0;
            mem_resp_count                   = 0;

            for (int i = 0; i < MAX_TEST_REQUESTS; i++) begin
                expected_by_seq[i]          = '0;
                expected_valid_by_seq[i]    = 1'b0;
                expected_addr_by_seq[i]     = 0;
                expected_is_read_by_seq[i]  = 1'b0;
                expected_is_write_by_seq[i] = 1'b0;
                read_done_by_seq[i]         = 1'b0;
                cpu_resp_count_by_seq[i]    = 0;
            end

            for (int s = 0; s < CPU_SLOT_COUNT; s++) begin
                slot_busy[s] = 1'b0;
                slot_seq[s]  = 0;
            end
        end
    endtask

    task automatic reset_dut_and_scoreboard(input int test_id,
                                            input int num_writes,
                                            input int num_reads);
        begin
            active_test        <= test_id;
            active_assoc_value <= assoc_value_from_idx(active_assoc_idx);
            active_num_writes  <= num_writes;
            active_num_reads  <= num_reads;
            in_read_phase     <= 1'b0;

            $readmemh(RAM_INIT_FILE, golden_mem);
            clear_scoreboard();
            drive_idle();

            rst <= 1'b1;
            repeat (5) @(posedge clk);
            rst <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic issue_one_request(input int test_id,
                                     input int req_seq,
                                     input bit write_req,
                                     input logic [ADDR_WIDTH-1:0] addr,
                                     input logic [DATA_WIDTH-1:0] wdata);
        int slot;
        bit accepted;
        begin
            accepted = 1'b0;

            if (req_seq >= MAX_TEST_REQUESTS) begin
                $error("%s request sequence exceeds scoreboard size. req_seq=%0d max=%0d",
                       test_name(test_id),
                       req_seq,
                       MAX_TEST_REQUESTS);
            end

            while (!accepted) begin
                slot = find_free_slot();

                if (slot < 0) begin
                    drive_idle();
                    @(posedge clk);
                end
                else begin
                    cpu_req_valid <= 1'b1;
                    cpu_req_write <= write_req;
                    cpu_req_addr  <= addr;
                    cpu_req_wdata <= wdata;
                    cpu_req_id    <= CPU_ID_WIDTH'(slot);

                    @(posedge clk);

                    if (cpu_req_ready) begin
                        accepted = 1'b1;

                        // Mark slot busy after the accepted clock edge.
                        // Response monitor frees slots when cpu_resp_valid arrives.
                        slot_busy[slot] = 1'b1;
                        slot_seq[slot]  = req_seq;

                        total_cpu_requests_sent = total_cpu_requests_sent + 1;

                        if (write_req) begin
                            golden_mem[addr] = wdata;

                            expected_is_write_by_seq[req_seq] = 1'b1;
                            expected_is_read_by_seq[req_seq]  = 1'b0;
                        end
                        else begin
                            expected_by_seq[req_seq]       = golden_mem[addr];
                            expected_valid_by_seq[req_seq] = 1'b1;
                            expected_addr_by_seq[req_seq]  = int'(addr);

                            expected_is_read_by_seq[req_seq]  = 1'b1;
                            expected_is_write_by_seq[req_seq] = 1'b0;
                        end

                        if (print_cpu_reqs(active_test)) begin
                            $display("[%0t] CPU_REQ_SEND: test=%s phase=%s req_seq=%0d slot=%0d write=%0b addr=%h word_addr=%0d wdata=%h total_now=%0d",
                                     $time,
                                     test_name(active_test),
                                     (active_test == TEST3) ? "MIXED_PHASE" : (in_read_phase ? "READ_PHASE" : "WRITE_PHASE"),
                                     req_seq,
                                     slot,
                                     write_req,
                                     addr,
                                     addr,
                                     wdata,
                                     total_cpu_requests_sent);
                        end
                    end
                end
            end

            drive_idle();
        end
    endtask

    task automatic send_writes_back_to_back_base(input int test_id,
                                                 input int num_writes,
                                                 input int seq_base);
        begin
            for (int i = 0; i < num_writes; i++) begin
                issue_one_request(test_id,
                                  seq_base + i,
                                  1'b1,
                                  make_addr(test_id, i),
                                  make_wdata(test_id, i));
            end
        end
    endtask

    task automatic send_writes_back_to_back(input int test_id,
                                            input int num_writes);
        begin
            send_writes_back_to_back_base(test_id, num_writes, 0);
        end
    endtask

    task automatic send_reads_back_to_back_base(input int test_id,
                                                input int num_reads,
                                                input int seq_base);
        begin
            for (int i = 0; i < num_reads; i++) begin
                issue_one_request(test_id,
                                  seq_base + i,
                                  1'b0,
                                  make_addr(test_id, i),
                                  '0);
            end
        end
    endtask

    task automatic send_reads_back_to_back(input int test_id,
                                           input int num_writes,
                                           input int num_reads);
        begin
            send_reads_back_to_back_base(test_id, num_reads, num_writes);
        end
    endtask

    task automatic send_random_requests(input int num_bursts);
        bit rand_write;
        int rand_word_addr;
        logic [DATA_WIDTH-1:0] rand_wdata;
        int req_seq;
        begin
            test3_write_count = 0;
            test3_read_count  = 0;
            req_seq           = 0;

            for (int burst = 0; burst < num_bursts; burst++) begin
                // Change the random seed between bursts. This keeps each burst
                // reproducible, and every associativity sees the same burst stream.
                void'($urandom(TEST3_BASE_SEED + burst));

                if (assoc_debug_enabled(active_assoc_idx)) begin
                    $display("[%0t] TEST3 BURST START: assoc=%0d burst=%0d seed=%h req_seq_base=%0d burst_size=%0d",
                             $time,
                             active_assoc_value,
                             burst,
                             TEST3_BASE_SEED + burst,
                             req_seq,
                             TEST3_BURST_SIZE);
                end

                for (int i = 0; i < TEST3_BURST_SIZE; i++) begin
                    rand_write     = bit'($urandom_range(0, 1));
                    rand_word_addr = $urandom_range(0, RAM_DEPTH_WORDS - 1);
                    rand_wdata     = DATA_WIDTH'($urandom);

                    issue_one_request(TEST3,
                                      req_seq,
                                      rand_write,
                                      ADDR_WIDTH'(rand_word_addr),
                                      rand_wdata);

                    if (rand_write)
                        test3_write_count++;
                    else
                        test3_read_count++;

                    req_seq++;
                end
            end
        end
    endtask

    task automatic send_test5_reads_same_addr(input int line_idx,
                                              input int repeat_count,
                                              input int seq_base);
        logic [ADDR_WIDTH-1:0] same_addr;
        begin
            same_addr = ADDR_WIDTH'(line_idx * WORDS_PER_LINE);

            for (int i = 0; i < repeat_count; i++) begin
                issue_one_request(TEST5,
                                  seq_base + i,
                                  1'b0,
                                  same_addr,
                                  '0);
            end
        end
    endtask

    task automatic send_test5_writes_same_addr(input int line_idx,
                                               input int repeat_count,
                                               input int seq_base);
        logic [ADDR_WIDTH-1:0] same_addr;
        begin
            same_addr = ADDR_WIDTH'(line_idx * WORDS_PER_LINE);

            for (int i = 0; i < repeat_count; i++) begin
                issue_one_request(TEST5,
                                  seq_base + i,
                                  1'b1,
                                  same_addr,
                                  make_wdata(TEST5, seq_base + i));
            end
        end
    endtask

    task automatic send_test6_repeated_addr(input bit write_req,
                                            input int line_idx,
                                            input int word_offset,
                                            input int repeat_count,
                                            input int seq_base);
        logic [ADDR_WIDTH-1:0] same_line_addr;
        begin
            same_line_addr = ADDR_WIDTH'((line_idx * WORDS_PER_LINE) + word_offset);

            for (int i = 0; i < repeat_count; i++) begin
                issue_one_request(TEST6,
                                  seq_base + i,
                                  write_req,
                                  same_line_addr,
                                  write_req ? make_wdata(TEST6, seq_base + i) : '0);
            end
        end
    endtask

    task automatic wait_for_responses(input int expected_responses,
                                      input string name);
        int timeout_cycles;
        begin
            timeout_cycles = 0;

            while ((total_cpu_responses < expected_responses) &&
                   (timeout_cycles < 200000)) begin
                @(posedge clk);
                timeout_cycles++;
            end

            if (total_cpu_responses < expected_responses) begin
                $error("%s timed out waiting for responses. Expected=%0d got=%0d",
                       name,
                       expected_responses,
                       total_cpu_responses);
            end
        end
    endtask

    task automatic calculate_expected_mem_counts;
        begin
            expected_total_line_allocations = write_miss_count + read_miss_count;

            expected_replacements_after_full = expected_total_line_allocations - CACHE_LINES;
            if (expected_replacements_after_full < 0)
                expected_replacements_after_full = 0;

            expected_refill_transactions = (write_miss_count * (WORDS_PER_LINE - 1)) +
                                           (read_miss_count  * WORDS_PER_LINE);
        end
    endtask

    task automatic print_report(input int test_id);
        begin
            calculate_expected_mem_counts();

            if (print_report_en(test_id)) begin
                $display("==================================================");
                $display("%s Simulation Report", test_name(test_id));
                $display("Associativity                       = %0d", active_assoc_value);
                $display("Total CPU requests sent              = %0d", total_cpu_requests_sent);
                $display("CPU visible ID width                 = %0d", CPU_ID_WIDTH);
                $display("CPU reusable slots                   = %0d", CPU_SLOT_COUNT);
                $display("Total CPU responses                  = %0d", total_cpu_responses);
                $display("Write responses                      = %0d", total_write_responses);
                $display("Read responses                       = %0d", total_read_responses);
                $display("CPU hit responses                    = %0d", hit_count);
                $display("CPU miss responses                   = %0d", miss_count);
                $display("Write miss responses                 = %0d", write_miss_count);
                $display("Read miss responses                  = %0d", read_miss_count);
                $display("Data checks performed                = %0d", data_check_count);
                $display("Data errors                          = %0d", data_error_count);
                $display("Duplicate response errors            = %0d", duplicate_resp_errors);
                $display("Unexpected response errors           = %0d", unexpected_resp_errors);
                $display("Missing response errors              = %0d", missing_resp_errors);
                $display("Cache lines                          = %0d", CACHE_LINES);
                $display("Words per line                       = %0d", WORDS_PER_LINE);
                $display("Expected line allocations            = %0d", expected_total_line_allocations);
                $display("Expected replacements after full     = %0d", expected_replacements_after_full);
                $display("Expected refill transactions         = %0d", expected_refill_transactions);
                $display("mem_req_valid accepted cycles        = %0d", mem_req_valid_cycles);
                $display("mem read request cycles              = %0d", mem_read_req_cycles);
                $display("mem writeback request cycles         = %0d", mem_write_req_cycles);
                $display("write-phase read request cycles      = %0d", write_phase_mem_read_req_cycles);
                $display("read-phase read request cycles       = %0d", read_phase_mem_read_req_cycles);
                $display("write-phase writeback cycles         = %0d", write_phase_mem_write_req_cycles);
                $display("read-phase writeback cycles          = %0d", read_phase_mem_write_req_cycles);
                $display("write-phase dirty evictions observed = %0d", write_phase_mem_write_req_cycles / WORDS_PER_LINE);
                $display("read-phase dirty evictions observed  = %0d", read_phase_mem_write_req_cycles / WORDS_PER_LINE);
                $display("total dirty evictions observed       = %0d", mem_write_req_cycles / WORDS_PER_LINE);
                $display("mem_resp_valid accepted cycles       = %0d", mem_resp_count);
                $display("mem_req_valid pulse count            = %0d", mem_req_valid_pulses);
                $display("==================================================");
            end
        end
    endtask

    task automatic check_results(input int test_id,
                                 input int num_writes,
                                 input int num_reads,
                                 output bit pass);
        int expected_total;
        begin
            expected_total = num_writes + num_reads;
            pass = 1'b1;
            missing_resp_errors = 0;

            if (expected_total > MAX_TEST_REQUESTS) begin
                pass = 1'b0;
                $error("%s has too many requests. Max=%0d requested=%0d",
                       test_name(test_id),
                       MAX_TEST_REQUESTS,
                       expected_total);
            end

            if (total_cpu_requests_sent !== expected_total) begin
                pass = 1'b0;
                $error("%s expected %0d CPU requests sent, got %0d",
                       test_name(test_id), expected_total, total_cpu_requests_sent);
            end

            if (total_cpu_responses !== expected_total) begin
                pass = 1'b0;
                $error("%s expected %0d total CPU responses, got %0d",
                       test_name(test_id), expected_total, total_cpu_responses);
            end

            if (total_write_responses !== num_writes) begin
                pass = 1'b0;
                $error("%s expected %0d write responses, got %0d",
                       test_name(test_id), num_writes, total_write_responses);
            end

            if (total_read_responses !== num_reads) begin
                pass = 1'b0;
                $error("%s expected %0d read responses, got %0d",
                       test_name(test_id), num_reads, total_read_responses);
            end

            if (data_check_count !== num_reads) begin
                pass = 1'b0;
                $error("%s expected %0d data checks, got %0d",
                       test_name(test_id), num_reads, data_check_count);
            end

            if (data_error_count !== 0) begin
                pass = 1'b0;
                $error("%s failed with %0d data mismatches",
                       test_name(test_id), data_error_count);
            end

            if (duplicate_resp_errors !== 0) begin
                pass = 1'b0;
                $error("%s failed with %0d duplicate response errors",
                       test_name(test_id), duplicate_resp_errors);
            end

            if (unexpected_resp_errors !== 0) begin
                pass = 1'b0;
                $error("%s failed with %0d unexpected response errors",
                       test_name(test_id), unexpected_resp_errors);
            end

            for (int i = 0; i < MAX_TEST_REQUESTS; i++) begin
                if (expected_is_read_by_seq[i] &&
                    expected_valid_by_seq[i] &&
                    !read_done_by_seq[i]) begin
                    pass = 1'b0;
                    missing_resp_errors++;
                    $error("%s missing read response for req_seq=%0d addr_word=%0d expected=%h",
                           test_name(test_id),
                           i,
                           expected_addr_by_seq[i],
                           expected_by_seq[i]);
                end
            end

            for (int s = 0; s < CPU_SLOT_COUNT; s++) begin
                if (slot_busy[s]) begin
                    pass = 1'b0;
                    $error("%s ended with busy CPU slot=%0d mapped_req_seq=%0d",
                           test_name(test_id),
                           s,
                           slot_seq[s]);
                end
            end
        end
    endtask

    task automatic run_one_test(input int test_id,
                                input int num_writes,
                                input int num_reads);
        bit pass;
        begin
            reset_dut_and_scoreboard(test_id, num_writes, num_reads);

            $display("==================================================");
            $display("Starting %s", test_name(test_id));

            if (test_id == TEST1) begin
                $display("Test1: sequential word addresses 0..%0d", num_writes - 1);
            end
            else if (test_id == TEST2) begin
                $display("Test2: overflow cache with %0d unique lines", num_writes);
                $display("Test2: accesses word offset 2 of each line: word addresses 2, 6, 10, ...");
            end

            $display("%s: CPU uses %0d reusable request ID slots", test_name(test_id), CPU_SLOT_COUNT);
            $display("==================================================");

            in_read_phase <= 1'b0;
            $display("%s: Starting %0d writes", test_name(test_id), num_writes);
            send_writes_back_to_back(test_id, num_writes);

            wait_for_responses(num_writes, test_name(test_id));
            repeat (10) @(posedge clk);

            in_read_phase <= 1'b1;
            $display("%s: Starting %0d reads", test_name(test_id), num_reads);
            send_reads_back_to_back(test_id, num_writes, num_reads);

            wait_for_responses(num_writes + num_reads, test_name(test_id));
            repeat (300) @(posedge clk);

            check_results(test_id, num_writes, num_reads, pass);
            print_report(test_id);
            record_assoc_result(test_id, pass, data_error_count);

            if (test_id == TEST1)
                test1_pass = pass;
            else if (test_id == TEST2)
                test2_pass = pass;

            if (pass)
                $display("%s PASSED: all %0d reads returned correct data.", test_name(test_id), num_reads);
            else
                $display("%s FAILED.", test_name(test_id));

            $display("%s complete.", test_name(test_id));
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    task automatic run_test3(input int num_bursts);
        bit pass;
        int total_random_reqs;
        begin
            total_random_reqs = num_bursts * TEST3_BURST_SIZE;

            reset_dut_and_scoreboard(TEST3, 0, 0);

            $display("==================================================");
            $display("Starting Test3");
            $display("Test3: burst random mixed read/write requests");
            $display("Test3: bursts=%0d requests_per_burst=%0d total_requests=%0d",
                     num_bursts,
                     TEST3_BURST_SIZE,
                     total_random_reqs);
            $display("Test3: base_seed=%h, seed changes to base_seed + burst", TEST3_BASE_SEED);
            $display("Test3: CPU uses %0d reusable request ID slots", CPU_SLOT_COUNT);
            $display("==================================================");

            in_read_phase <= 1'b0;
            send_random_requests(num_bursts);

            wait_for_responses(total_random_reqs, "Test3");
            repeat (300) @(posedge clk);

            check_results(TEST3, test3_write_count, test3_read_count, pass);
            print_report(TEST3);
            record_assoc_result(TEST3, pass, data_error_count);

            test3_pass = pass;

            if (pass)
                $display("Test3 PASSED: all %0d reads returned correct data.", test3_read_count);
            else
                $display("Test3 FAILED.");

            $display("Test3 complete.");
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    task automatic run_test4(input int num_reads1,
                             input int num_writes,
                             input int num_reads2);
        bit pass;
        int expected_total;
        begin
            expected_total = num_reads1 + num_writes + num_reads2;

            reset_dut_and_scoreboard(TEST4, num_writes, num_reads1 + num_reads2);

            $display("==================================================");
            $display("Starting Test4");
            $display("Test4: read addresses first, then write same addresses, then read again");
            $display("Test4: sequential word addresses 0..%0d", num_writes - 1);
            $display("Test4: CPU uses %0d reusable request ID slots", CPU_SLOT_COUNT);
            $display("==================================================");

            in_read_phase <= 1'b1;
            $display("Test4: Starting first %0d reads", num_reads1);
            send_reads_back_to_back_base(TEST4, num_reads1, 0);

           
            repeat (10) @(posedge clk);

            in_read_phase <= 1'b0;
            $display("Test4: Starting %0d writes", num_writes);
            send_writes_back_to_back_base(TEST4, num_writes, num_reads1);

         
            repeat (10) @(posedge clk);

            in_read_phase <= 1'b1;
            $display("Test4: Starting second %0d reads", num_reads2);
            send_reads_back_to_back_base(TEST4, num_reads2, num_reads1 + num_writes);

            repeat (300) @(posedge clk);

            check_results(TEST4, num_writes, num_reads1 + num_reads2, pass);
            print_report(TEST4);
            record_assoc_result(TEST4, pass, data_error_count);

            test4_pass = pass;

            if (pass)
                $display("Test4 PASSED: first reads returned old data and second reads returned written data.");
            else
                $display("Test4 FAILED.");

            $display("Test4 complete.");
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    task automatic run_test5(input int repeat_count,
                             input int num_lines);
        bit pass;
        int seq_next;
        int expected_reads;
        int expected_writes;
        int expected_total;
        begin
            expected_reads  = repeat_count * num_lines;
            expected_writes = repeat_count * num_lines;
            expected_total  = expected_reads + expected_writes;

            reset_dut_and_scoreboard(TEST5, expected_writes, expected_reads);

            $display("==================================================");
            $display("Starting Test5");
            $display("Test5: for each unique line, read same address X times then write same address X times");
            $display("Test5: X=%0d repeats, Y=%0d unique lines, total requests=%0d",
                     repeat_count,
                     num_lines,
                     expected_total);
            $display("Test5: CPU uses %0d reusable request ID slots", CPU_SLOT_COUNT);
            $display("Test5: line addresses are word addresses 0, %0d, %0d, ...",
                     WORDS_PER_LINE,
                     2 * WORDS_PER_LINE);
            $display("==================================================");

            seq_next = 0;

            for (int line_idx = 0; line_idx < num_lines; line_idx++) begin
                in_read_phase <= 1'b1;
                $display("Test5: line_idx=%0d addr_word=%0d starting %0d repeated reads",
                         line_idx,
                         line_idx * WORDS_PER_LINE,
                         repeat_count);
                send_test5_reads_same_addr(line_idx, repeat_count, seq_next);
                seq_next += repeat_count;

               
                repeat (10) @(posedge clk);

                in_read_phase <= 1'b0;
                $display("Test5: line_idx=%0d addr_word=%0d starting %0d repeated writes",
                         line_idx,
                         line_idx * WORDS_PER_LINE,
                         repeat_count);
                send_test5_writes_same_addr(line_idx, repeat_count, seq_next);
                seq_next += repeat_count;


                repeat (10) @(posedge clk);
            end

            repeat (300) @(posedge clk);

            check_results(TEST5, expected_writes, expected_reads, pass);
            print_report(TEST5);
            record_assoc_result(TEST5, pass, data_error_count);

            test5_pass = pass;

            if (pass)
                $display("Test5 PASSED: repeated reads to each same-line address returned correct data.");
            else
                $display("Test5 FAILED.");

            $display("Test5 complete.");
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    task automatic run_test6(input int repeat_count,
                             input int num_lines);
        bit pass;
        int seq_next;
        int expected_reads;
        int expected_writes;
        int expected_total;
        begin
            expected_reads  = repeat_count * num_lines * 2;
            expected_writes = repeat_count * num_lines * 2;
            expected_total  = expected_reads + expected_writes;

            reset_dut_and_scoreboard(TEST6, expected_writes, expected_reads);

            $display("==================================================");
            $display("Starting Test6");
            $display("Test6: same cache line, read addr0 X times, read addr1 X times, then write addr0 X times and write addr1 X times");
            $display("Test6: X=%0d repeats, Y=%0d unique lines, total requests=%0d",
                     repeat_count,
                     num_lines,
                     expected_total);
            $display("Test6: CPU uses %0d reusable request ID slots", CPU_SLOT_COUNT);
            $display("Test6: first line uses word addresses 0 and 1; next line uses %0d and %0d",
                     WORDS_PER_LINE,
                     WORDS_PER_LINE + 1);
            $display("==================================================");

            seq_next = 0;

            for (int line_idx = 0; line_idx < num_lines; line_idx++) begin
                in_read_phase <= 1'b1;
                $display("Test6: line_idx=%0d addr_word=%0d starting %0d repeated reads",
                         line_idx,
                         line_idx * WORDS_PER_LINE,
                         repeat_count);
                send_test6_repeated_addr(1'b0, line_idx, 0, repeat_count, seq_next);
                seq_next += repeat_count;

                
                repeat (10) @(posedge clk);

                in_read_phase <= 1'b1;
                $display("Test6: line_idx=%0d addr_word=%0d starting %0d repeated reads",
                         line_idx,
                         (line_idx * WORDS_PER_LINE) + 1,
                         repeat_count);
                send_test6_repeated_addr(1'b0, line_idx, 1, repeat_count, seq_next);
                seq_next += repeat_count;


                repeat (10) @(posedge clk);

                in_read_phase <= 1'b0;
                $display("Test6: line_idx=%0d addr_word=%0d starting %0d repeated writes",
                         line_idx,
                         line_idx * WORDS_PER_LINE,
                         repeat_count);
                send_test6_repeated_addr(1'b1, line_idx, 0, repeat_count, seq_next);
                seq_next += repeat_count;

               
                repeat (10) @(posedge clk);

                in_read_phase <= 1'b0;
                $display("Test6: line_idx=%0d addr_word=%0d starting %0d repeated writes",
                         line_idx,
                         (line_idx * WORDS_PER_LINE) + 1,
                         repeat_count);
                send_test6_repeated_addr(1'b1, line_idx, 1, repeat_count, seq_next);
                seq_next += repeat_count;


                repeat (10) @(posedge clk);
            end

            repeat (300) @(posedge clk);

            check_results(TEST6, expected_writes, expected_reads, pass);
            print_report(TEST6);
            record_assoc_result(TEST6, pass, data_error_count);

            test6_pass = pass;

            if (pass)
                $display("Test6 PASSED: repeated reads to addr0/addr1 in each same line returned correct data.");
            else
                $display("Test6 FAILED.");

            $display("Test6 complete.");
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    // Use plain always, not always_ff, because the test driver task also updates
    // slot_busy/slot_seq when a request is accepted. This avoids always_ff
    // single-driver compile errors in Questa.
    always @(posedge clk) begin
        int resp_slot;
        int resp_seq;

        if (rst) begin
            total_cpu_responses    = 0;
            total_write_responses  = 0;
            total_read_responses   = 0;
            hit_count              = 0;
            miss_count             = 0;
            write_miss_count       = 0;
            read_miss_count        = 0;
            data_check_count       = 0;
            data_error_count       = 0;
            duplicate_resp_errors  = 0;
            unexpected_resp_errors = 0;

            for (int i = 0; i < MAX_TEST_REQUESTS; i++) begin
                cpu_resp_count_by_seq[i] = 0;
                read_done_by_seq[i]      = 1'b0;
            end

            for (int s = 0; s < CPU_SLOT_COUNT; s++) begin
                slot_busy[s] = 1'b0;
                slot_seq[s]  = 0;
            end
        end
        else if (cpu_resp_valid && cpu_resp_ready) begin
            resp_slot = int'(cpu_resp_id);
            resp_seq  = slot_seq[resp_slot];

            total_cpu_responses = total_cpu_responses + 1;

            if (!slot_busy[resp_slot]) begin
                unexpected_resp_errors = unexpected_resp_errors + 1;

                $error("UNEXPECTED CPU RESPONSE TO FREE SLOT: test=%s slot=%0d hit=%0b rdata=%h",
                       test_name(active_test),
                       resp_slot,
                       cpu_resp_hit,
                       cpu_resp_rdata);
            end
            else begin
                slot_busy[resp_slot] = 1'b0;

                cpu_resp_count_by_seq[resp_seq] = cpu_resp_count_by_seq[resp_seq] + 1;

                if (cpu_resp_count_by_seq[resp_seq] != 1) begin
                    duplicate_resp_errors = duplicate_resp_errors + 1;
                    $error("DUPLICATE CPU RESPONSE: test=%s req_seq=%0d slot=%0d count_now=%0d",
                           test_name(active_test),
                           resp_seq,
                           resp_slot,
                           cpu_resp_count_by_seq[resp_seq]);
                end

                if (cpu_resp_hit)
                    hit_count = hit_count + 1;
                else
                    miss_count = miss_count + 1;

                if (print_cpu_resps(active_test)) begin
                    $display("[%0t] CPU_RESP: test=%s phase=%s req_seq=%0d slot=%0d hit=%0b rdata=%h total_now=%0d",
                             $time,
                             test_name(active_test),
                             (active_test == TEST3) ? "MIXED_PHASE" : (in_read_phase ? "READ_PHASE" : "WRITE_PHASE"),
                             resp_seq,
                             resp_slot,
                             cpu_resp_hit,
                             cpu_resp_rdata,
                             total_cpu_responses);
                end

                if (expected_is_read_by_seq[resp_seq]) begin
                    total_read_responses = total_read_responses + 1;

                    if (!cpu_resp_hit)
                        read_miss_count = read_miss_count + 1;

                    if (!expected_valid_by_seq[resp_seq] || read_done_by_seq[resp_seq]) begin
                        unexpected_resp_errors = unexpected_resp_errors + 1;
                        $error("UNEXPECTED READ RESPONSE: test=%s req_seq=%0d slot=%0d rdata=%h expected_valid=%0b read_done=%0b",
                               test_name(active_test),
                               resp_seq,
                               resp_slot,
                               cpu_resp_rdata,
                               expected_valid_by_seq[resp_seq],
                               read_done_by_seq[resp_seq]);
                    end
                    else begin
                        data_check_count = data_check_count + 1;

                        if (cpu_resp_rdata !== expected_by_seq[resp_seq]) begin
                            data_error_count = data_error_count + 1;
                            $error("DATA MISMATCH: test=%s req_seq=%0d slot=%0d addr_word=%0d expected=%h got=%h hit=%0b",
                                   test_name(active_test),
                                   resp_seq,
                                   resp_slot,
                                   expected_addr_by_seq[resp_seq],
                                   expected_by_seq[resp_seq],
                                   cpu_resp_rdata,
                                   cpu_resp_hit);
                        end
                        else if (print_checks(active_test)) begin
                            $display("[%0t] DATA CHECK PASS: test=%s req_seq=%0d slot=%0d addr_word=%0d expected=%h got=%h hit=%0b",
                                     $time,
                                     test_name(active_test),
                                     resp_seq,
                                     resp_slot,
                                     expected_addr_by_seq[resp_seq],
                                     expected_by_seq[resp_seq],
                                     cpu_resp_rdata,
                                     cpu_resp_hit);
                        end

                        read_done_by_seq[resp_seq] = 1'b1;
                    end
                end
                else if (expected_is_write_by_seq[resp_seq]) begin
                    total_write_responses = total_write_responses + 1;

                    if (!cpu_resp_hit)
                        write_miss_count = write_miss_count + 1;
                end
                else begin
                    unexpected_resp_errors = unexpected_resp_errors + 1;
                    $error("UNEXPECTED CPU RESPONSE: test=%s req_seq=%0d slot=%0d hit=%0b rdata=%h",
                           test_name(active_test),
                           resp_seq,
                           resp_slot,
                           cpu_resp_hit,
                           cpu_resp_rdata);
                end
            end
        end
    end

    // Plain always avoids fighting with clear_scoreboard() in tasks.
    always @(posedge clk) begin
        if (rst) begin
            mem_req_valid_cycles             = 0;
            mem_read_req_cycles              = 0;
            mem_write_req_cycles             = 0;
            write_phase_mem_write_req_cycles = 0;
            read_phase_mem_write_req_cycles  = 0;
            write_phase_mem_read_req_cycles  = 0;
            read_phase_mem_read_req_cycles   = 0;
            mem_req_valid_pulses             = 0;
            mem_req_valid_d                  = 1'b0;
        end
        else begin
            mem_req_valid_d = mem_req_valid;

            if (mem_req_valid && mem_req_ready) begin
                mem_req_valid_cycles = mem_req_valid_cycles + 1;

                if (print_mem_reqs(active_test)) begin
                    $display("[%0t] MEM_REQ: test=%s phase=%s write=%0b addr=%h word_addr=%0d wdata=%h mshr_id=%0d count_now=%0d",
                             $time,
                             test_name(active_test),
                             (active_test == TEST3) ? "MIXED_PHASE" : (in_read_phase ? "READ_PHASE" : "WRITE_PHASE"),
                             mem_req_write,
                             mem_req_addr,
                             mem_req_addr,
                             mem_req_wdata,
                             mem_req_id,
                             mem_req_valid_cycles);
                end

                if (mem_req_write) begin
                    mem_write_req_cycles = mem_write_req_cycles + 1;

                    if (in_read_phase)
                        read_phase_mem_write_req_cycles = read_phase_mem_write_req_cycles + 1;
                    else
                        write_phase_mem_write_req_cycles = write_phase_mem_write_req_cycles + 1;
                end
                else begin
                    mem_read_req_cycles = mem_read_req_cycles + 1;

                    if (in_read_phase)
                        read_phase_mem_read_req_cycles = read_phase_mem_read_req_cycles + 1;
                    else
                        write_phase_mem_read_req_cycles = write_phase_mem_read_req_cycles + 1;
                end
            end

            if (mem_req_valid && !mem_req_valid_d)
                mem_req_valid_pulses = mem_req_valid_pulses + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            mem_resp_count = 0;
        end
        else if (mem_resp_valid && mem_resp_ready) begin
            mem_resp_count = mem_resp_count + 1;

            if (print_mem_resps(active_test)) begin
                $display("[%0t] MEM_RESP: test=%s phase=%s rdata=%h mshr_id=%0d count_now=%0d",
                         $time,
                         test_name(active_test),
                         (active_test == TEST3) ? "MIXED_PHASE" : (in_read_phase ? "READ_PHASE" : "WRITE_PHASE"),
                         mem_resp_rdata,
                         mem_resp_id,
                         mem_resp_count);
            end
        end
    end

    function automatic bit all_tests_passed;
        begin
            all_tests_passed = 1'b1;

            for (int t = TEST1; t <= TEST6; t++) begin
                for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
                    if (!test_pass_by_assoc[t][a])
                        all_tests_passed = 1'b0;
                end
            end
        end
    endfunction

    task automatic run_active_assoc_test(input int test_id);
        begin
            if (test_id == TEST1)
                run_one_test(TEST1, TEST1_NUM_WRITES, TEST1_NUM_READS);
            else if (test_id == TEST2)
                run_one_test(TEST2, TEST2_NUM_WRITES, TEST2_NUM_READS);
            else if (test_id == TEST3)
                run_test3(TEST3_BURSTS);
            else if (test_id == TEST4)
                run_test4(TEST4_NUM_READS1, TEST4_NUM_WRITES, TEST4_NUM_READS2);
            else if (test_id == TEST5)
                run_test5(TEST5_REPEAT_COUNT, TEST5_NUM_LINES);
            else
                run_test6(TEST6_REPEAT_COUNT, TEST6_NUM_LINES);
        end
    endtask

    initial begin
        rst                <= 1'b1;
        active_test        <= TEST1;
        active_assoc_idx   <= ASSOC_IDX_1;
        active_assoc_value <= 1;
        active_num_writes  <= TEST1_NUM_WRITES;
        active_num_reads   <= TEST1_NUM_READS;
        in_read_phase      <= 1'b0;

        test1_pass = 1'b0;
        test2_pass = 1'b0;
        test3_pass = 1'b0;
        test4_pass = 1'b0;
        test5_pass = 1'b0;
        test6_pass = 1'b0;

        for (int t = 1; t <= 6; t++) begin
            for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
                test_pass_by_assoc[t][a] = 1'b0;
                test_data_errors_by_assoc[t][a] = 0;
            end
        end

        clear_scoreboard();
        drive_idle();

        // Associativity-major order:
        //   assoc1:  Test1, Test2, Test3, Test4, Test5, Test6
        //   assoc2:  Test1, Test2, Test3, Test4, Test5, Test6
        //   assoc4:  Test1, Test2, Test3, Test4, Test5, Test6
        //   assoc8:  Test1, Test2, Test3, Test4, Test5, Test6
        //   assoc16: Test1, Test2, Test3, Test4, Test5, Test6
        // This is closer to running the original single-DUT testbench once per associativity.
        for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
            active_assoc_idx   = a;
            active_assoc_value = assoc_value_from_idx(a);
            drive_idle();
            @(posedge clk);

            $display("==================================================");
            $display("STARTING ASSOCIATIVITY %0d FULL TEST SUITE", assoc_value_from_idx(a));
            $display("Associativity %0d debug gate = %0b", assoc_value_from_idx(a), assoc_debug_enabled(a));
            $display("==================================================");

            for (int t = TEST1; t <= TEST6; t++) begin
                drive_idle();
                @(posedge clk);

                $display("==================================================");
                $display("RUNNING ASSOCIATIVITY %0d %s", assoc_value_from_idx(a), test_name(t));
                $display("==================================================");

                run_active_assoc_test(t);
            end

            drive_idle();
            repeat (50) @(posedge clk);
        end

        $display("==================================================");
        $display("FINAL ASSOCIATIVITY TEST SUMMARY");
        for (int t = TEST1; t <= TEST6; t++) begin
            for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
                $display("%s", test_status_line(t, a));
            end
        end

        if (all_tests_passed())
            $display("Congrats all associativity tests passed");
        else
            $display("One or more associativity tests failed");
        $display("==================================================");

        $finish;
    end

endmodule