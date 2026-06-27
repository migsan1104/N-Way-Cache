`timescale 1ns/1ps

module Test_1;

    localparam int ADDR_WIDTH       = 32;
    localparam int DATA_WIDTH       = 32;
    localparam int CPU_ID_WIDTH     = 8;
    localparam int MSHR_ID_WIDTH    = 2;

    localparam int CACHE_BYTES      = 1024;
    localparam int LINE_BYTES       = 16;
    localparam int ASSOC            = 4;

    localparam int WORDS_PER_LINE   = LINE_BYTES / (DATA_WIDTH / 8);
    localparam int CACHE_LINES      = CACHE_BYTES / LINE_BYTES;

    localparam int RAM_DEPTH_WORDS  = 1024;
    localparam int RAM_READ_LATENCY = 20;

    localparam int NUM_WRITES       = 100;
    localparam int NUM_READS        = 100;

    localparam int EXPECTED_TOTAL_CPU_RESPONSES = NUM_WRITES + NUM_READS;

    localparam bit PRINT_CPU_REQS   = 1'b1;
    localparam bit PRINT_CPU_RESPS  = 1'b1;
    localparam bit PRINT_MEM_REQS   = 1'b0;
    localparam bit PRINT_MEM_RESPS  = 1'b0;
    localparam bit PRINT_CHECKS     = 1'b1;
    localparam bit PRINT_REPORT     = 1'b1;

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

    int total_cpu_requests_sent;
    int total_cpu_responses;
    int total_write_responses;
    int total_read_responses;

    int hit_count;
    int miss_count;

    int mem_req_valid_cycles;
    int mem_read_req_cycles;
    int mem_write_req_cycles;
    int mem_resp_count;

    int mem_req_valid_pulses;
    logic mem_req_valid_d;

    logic in_read_phase;

    logic [DATA_WIDTH-1:0] golden_mem [0:RAM_DEPTH_WORDS-1];

    logic [DATA_WIDTH-1:0] expected_by_id       [0:255];
    logic                  expected_valid_by_id [0:255];
    logic                  read_done_by_id      [0:255];
    int                    expected_addr_by_id  [0:255];

    int data_check_count;
    int data_error_count;
    int duplicate_resp_errors;
    int unexpected_resp_errors;

    int cpu_resp_count [0:255];

    initial clk = 1'b0;
    always #5 clk = ~clk;

    Cache #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .CACHE_BYTES   (CACHE_BYTES),
        .LINE_BYTES    (LINE_BYTES),
        .ASSOC         (ASSOC),
        .CPU_ID_WIDTH  (CPU_ID_WIDTH),
        .MSHR_ID_WIDTH (MSHR_ID_WIDTH)
    ) DUT (
        .clk            (clk),
        .rst            (rst),

        .cpu_req_valid  (cpu_req_valid),
        .cpu_req_ready  (cpu_req_ready),
        .cpu_req_write  (cpu_req_write),
        .cpu_req_addr   (cpu_req_addr),
        .cpu_req_wdata  (cpu_req_wdata),
        .cpu_req_id     (cpu_req_id),

        .cpu_resp_valid (cpu_resp_valid),
        .cpu_resp_ready (cpu_resp_ready),
        .cpu_resp_hit   (cpu_resp_hit),
        .cpu_resp_rdata (cpu_resp_rdata),
        .cpu_resp_id    (cpu_resp_id),

        .mem_req_valid  (mem_req_valid),
        .mem_req_ready  (mem_req_ready),
        .mem_req_write  (mem_req_write),
        .mem_req_addr   (mem_req_addr),
        .mem_req_wdata  (mem_req_wdata),
        .mem_req_id     (mem_req_id),

        .mem_resp_valid (mem_resp_valid),
        .mem_resp_ready (mem_resp_ready),
        .mem_resp_id    (mem_resp_id),
        .mem_resp_rdata (mem_resp_rdata)
    );

    RAM_ID #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .D_WIDTH      (DATA_WIDTH),
        .DEPTH        (RAM_DEPTH_WORDS),
        .ID_WIDTH     (MSHR_ID_WIDTH),
        .READ_LATENCY (RAM_READ_LATENCY),
        .INIT_FILE    ("downstream_init.hex")
    ) MEM (
        .clk          (clk),
        .rst          (rst),

        .req_valid    (mem_req_valid),
        .req_ready    (mem_req_ready),
        .req_write    (mem_req_write),
        .req_addr     (mem_req_addr),
        .req_wdata    (mem_req_wdata),
        .req_id       (mem_req_id),

        .resp_valid   (mem_resp_valid),
        .resp_ready   (mem_resp_ready),
        .resp_rdata   (mem_resp_rdata),
        .resp_id      (mem_resp_id)
    );

    assign cpu_resp_ready = 1'b1;

    task automatic send_100_writes_back_to_back;
        int i;
        begin
            i = 0;

            while (i < NUM_WRITES) begin
                cpu_req_valid <= 1'b1;
                cpu_req_write <= 1'b1;
                cpu_req_addr  <= ADDR_WIDTH'(i << 2);
                cpu_req_wdata <= DATA_WIDTH'(i + 1);
                cpu_req_id    <= CPU_ID_WIDTH'(i);

                @(posedge clk);

                if (cpu_req_ready) begin
                    i++;
                end
            end

            cpu_req_valid <= 1'b0;
            cpu_req_write <= 1'b0;
            cpu_req_addr  <= '0;
            cpu_req_wdata <= '0;
            cpu_req_id    <= '0;
        end
    endtask

    task automatic send_100_reads_back_to_back;
        int i;
        begin
            i = 0;

            while (i < NUM_READS) begin
                cpu_req_valid <= 1'b1;
                cpu_req_write <= 1'b0;
                cpu_req_addr  <= ADDR_WIDTH'(i << 2);
                cpu_req_wdata <= '0;
                cpu_req_id    <= CPU_ID_WIDTH'(NUM_WRITES + i);

                @(posedge clk);

                if (cpu_req_ready) begin
                    i++;
                end
            end

            cpu_req_valid <= 1'b0;
            cpu_req_write <= 1'b0;
            cpu_req_addr  <= '0;
            cpu_req_wdata <= '0;
            cpu_req_id    <= '0;
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            total_cpu_requests_sent <= 0;

            for (int i = 0; i < RAM_DEPTH_WORDS; i++) begin
                golden_mem[i] <= '0;
            end

            for (int i = 0; i < 256; i++) begin
                expected_by_id[i]       <= '0;
                expected_valid_by_id[i] <= 1'b0;
                expected_addr_by_id[i]  <= 0;
            end
        end
        else if (cpu_req_valid && cpu_req_ready) begin
            total_cpu_requests_sent <= total_cpu_requests_sent + 1;

            if (cpu_req_write) begin
                golden_mem[cpu_req_addr >> 2] <= cpu_req_wdata;
            end
            else begin
                expected_by_id[cpu_req_id]       <= golden_mem[cpu_req_addr >> 2];
                expected_valid_by_id[cpu_req_id] <= 1'b1;
                expected_addr_by_id[cpu_req_id]  <= int'(cpu_req_addr >> 2);
            end

            if (PRINT_CPU_REQS) begin
                $display("[%0t] CPU_REQ_SEND: phase=%s write=%0b addr=%h word_addr=%0d wdata=%h cpu_id=%0d total_now=%0d",
                         $time,
                         in_read_phase ? "READ_PHASE" : "WRITE_PHASE",
                         cpu_req_write,
                         cpu_req_addr,
                         cpu_req_addr >> 2,
                         cpu_req_wdata,
                         cpu_req_id,
                         total_cpu_requests_sent + 1);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            total_cpu_responses    <= 0;
            total_write_responses  <= 0;
            total_read_responses   <= 0;
            hit_count              <= 0;
            miss_count             <= 0;
            data_check_count       <= 0;
            data_error_count       <= 0;
            duplicate_resp_errors  <= 0;
            unexpected_resp_errors <= 0;

            for (int i = 0; i < 256; i++) begin
                cpu_resp_count[i] <= 0;
                read_done_by_id[i] <= 1'b0;
            end
        end
        else if (cpu_resp_valid && cpu_resp_ready) begin
            total_cpu_responses <= total_cpu_responses + 1;
            cpu_resp_count[cpu_resp_id] <= cpu_resp_count[cpu_resp_id] + 1;

            if (cpu_resp_count[cpu_resp_id] != 0) begin
                duplicate_resp_errors <= duplicate_resp_errors + 1;
                $error("DUPLICATE CPU RESPONSE: id=%0d count_before=%0d",
                       cpu_resp_id,
                       cpu_resp_count[cpu_resp_id]);
            end

            if (cpu_resp_hit)
                hit_count <= hit_count + 1;
            else
                miss_count <= miss_count + 1;

            if (cpu_resp_id >= NUM_WRITES) begin
                total_read_responses <= total_read_responses + 1;

                if (!expected_valid_by_id[cpu_resp_id] || read_done_by_id[cpu_resp_id]) begin
                    unexpected_resp_errors <= unexpected_resp_errors + 1;
                    $error("UNEXPECTED READ RESPONSE: id=%0d rdata=%h expected_valid=%0b read_done=%0b",
                           cpu_resp_id,
                           cpu_resp_rdata,
                           expected_valid_by_id[cpu_resp_id],
                           read_done_by_id[cpu_resp_id]);
                end
                else begin
                    data_check_count <= data_check_count + 1;

                    if (cpu_resp_rdata !== expected_by_id[cpu_resp_id]) begin
                        data_error_count <= data_error_count + 1;
                        $error("DATA MISMATCH: id=%0d addr_word=%0d expected=%h got=%h hit=%0b",
                               cpu_resp_id,
                               expected_addr_by_id[cpu_resp_id],
                               expected_by_id[cpu_resp_id],
                               cpu_resp_rdata,
                               cpu_resp_hit);
                    end
                    else if (PRINT_CHECKS) begin
                        $display("[%0t] DATA CHECK PASS: id=%0d addr_word=%0d expected=%h got=%h hit=%0b",
                                 $time,
                                 cpu_resp_id,
                                 expected_addr_by_id[cpu_resp_id],
                                 expected_by_id[cpu_resp_id],
                                 cpu_resp_rdata,
                                 cpu_resp_hit);
                    end

                    read_done_by_id[cpu_resp_id] <= 1'b1;
                end
            end
            else begin
                total_write_responses <= total_write_responses + 1;
            end

            if (PRINT_CPU_RESPS) begin
                $display("[%0t] CPU_RESP: phase=%s id=%0d hit=%0b rdata=%h total_now=%0d",
                         $time,
                         in_read_phase ? "READ_PHASE" : "WRITE_PHASE",
                         cpu_resp_id,
                         cpu_resp_hit,
                         cpu_resp_rdata,
                         total_cpu_responses + 1);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_req_valid_cycles <= 0;
            mem_read_req_cycles  <= 0;
            mem_write_req_cycles <= 0;
            mem_req_valid_pulses <= 0;
            mem_req_valid_d      <= 1'b0;
        end
        else begin
            mem_req_valid_d <= mem_req_valid;

            if (mem_req_valid && mem_req_ready) begin
                mem_req_valid_cycles <= mem_req_valid_cycles + 1;

                if (mem_req_write)
                    mem_write_req_cycles <= mem_write_req_cycles + 1;
                else
                    mem_read_req_cycles <= mem_read_req_cycles + 1;

                if (PRINT_MEM_REQS) begin
                    $display("[%0t] MEM_REQ: phase=%s write=%0b addr=%h word_addr=%0d wdata=%h mshr_id=%0d total_now=%0d",
                             $time,
                             in_read_phase ? "READ_PHASE" : "WRITE_PHASE",
                             mem_req_write,
                             mem_req_addr,
                             mem_req_addr >> 2,
                             mem_req_wdata,
                             mem_req_id,
                             mem_req_valid_cycles + 1);
                end
            end

            if (mem_req_valid && !mem_req_valid_d) begin
                mem_req_valid_pulses <= mem_req_valid_pulses + 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_resp_count <= 0;
        end
        else if (mem_resp_valid && mem_resp_ready) begin
            mem_resp_count <= mem_resp_count + 1;

            if (PRINT_MEM_RESPS) begin
                $display("[%0t] MEM_RESP: phase=%s mshr_id=%0d rdata=%h total_now=%0d",
                         $time,
                         in_read_phase ? "READ_PHASE" : "WRITE_PHASE",
                         mem_resp_id,
                         mem_resp_rdata,
                         mem_resp_count + 1);
            end
        end
    end

    initial begin
        rst           <= 1'b1;
        in_read_phase <= 1'b0;

        cpu_req_valid <= 1'b0;
        cpu_req_write <= 1'b0;
        cpu_req_addr  <= '0;
        cpu_req_wdata <= '0;
        cpu_req_id    <= '0;

        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);

        $display("==================================================");
        $display("Test_1: Starting 100 back-to-back writes");
        $display("Address word 0..99, data 1..100");
        $display("==================================================");

        in_read_phase <= 1'b0;
        send_100_writes_back_to_back();

        //wait (total_cpu_responses >= NUM_WRITES);
        //repeat (10) @(posedge clk);

        $display("==================================================");
        $display("Test_1: Starting 100 back-to-back reads");
        $display("Read address word 0..99, expect data 1..100");
        $display("==================================================");

        in_read_phase <= 1'b1;
        send_100_reads_back_to_back();

        wait (total_cpu_responses >= EXPECTED_TOTAL_CPU_RESPONSES-5);
        repeat (300) @(posedge clk);

        if (PRINT_REPORT) begin
            $display("==================================================");
            $display("Test_1 Simulation Report");
            $display("Total CPU requests sent        = %0d", total_cpu_requests_sent);
            $display("Total CPU responses            = %0d", total_cpu_responses);
            $display("Write responses                = %0d", total_write_responses);
            $display("Read responses                 = %0d", total_read_responses);
            $display("CPU hit responses              = %0d", hit_count);
            $display("CPU miss responses             = %0d", miss_count);
            $display("Data checks performed          = %0d", data_check_count);
            $display("Data errors                    = %0d", data_error_count);
            $display("Duplicate response errors      = %0d", duplicate_resp_errors);
            $display("Unexpected response errors     = %0d", unexpected_resp_errors);
            $display("Cache lines                    = %0d", CACHE_LINES);
            $display("Words per line                 = %0d", WORDS_PER_LINE);
            $display("mem_req_valid accepted cycles  = %0d", mem_req_valid_cycles);
            $display("mem read request cycles        = %0d", mem_read_req_cycles);
            $display("mem writeback request cycles   = %0d", mem_write_req_cycles);
            $display("mem_resp_valid accepted cycles = %0d", mem_resp_count);
            $display("mem_req_valid pulse count      = %0d", mem_req_valid_pulses);
            $display("==================================================");
        end

        if (total_cpu_requests_sent !== EXPECTED_TOTAL_CPU_RESPONSES) begin
            $error("Expected %0d CPU requests sent, got %0d",
                   EXPECTED_TOTAL_CPU_RESPONSES,
                   total_cpu_requests_sent);
        end

        if (total_cpu_responses !== EXPECTED_TOTAL_CPU_RESPONSES) begin
            $error("Expected %0d total CPU responses, got %0d",
                   EXPECTED_TOTAL_CPU_RESPONSES,
                   total_cpu_responses);
        end

        if (total_write_responses !== NUM_WRITES) begin
            $error("Expected %0d write responses, got %0d",
                   NUM_WRITES,
                   total_write_responses);
        end

        if (total_read_responses !== NUM_READS) begin
            $error("Expected %0d read responses, got %0d",
                   NUM_READS,
                   total_read_responses);
        end

        if (data_check_count !== NUM_READS) begin
            $error("Expected %0d data checks, got %0d",
                   NUM_READS,
                   data_check_count);
        end

        if (data_error_count !== 0) begin
            $error("Test_1 failed with %0d data mismatches",
                   data_error_count);
        end

        if (duplicate_resp_errors !== 0) begin
            $error("Test_1 failed with %0d duplicate response errors",
                   duplicate_resp_errors);
        end

        if (unexpected_resp_errors !== 0) begin
            $error("Test_1 failed with %0d unexpected response errors",
                   unexpected_resp_errors);
        end

        for (int i = 0; i < NUM_READS; i++) begin
            if (expected_valid_by_id[NUM_WRITES + i] &&
                !read_done_by_id[NUM_WRITES + i]) begin
                $error("Missing read response for id=%0d addr_word=%0d expected=%h",
                       NUM_WRITES + i,
                       expected_addr_by_id[NUM_WRITES + i],
                       expected_by_id[NUM_WRITES + i]);
            end
        end

        if ((data_error_count == 0) &&
            (duplicate_resp_errors == 0) &&
            (unexpected_resp_errors == 0) &&
            (data_check_count == NUM_READS)) begin
            $display("TEST_1 PASSED: all 100 reads returned correct data.");
        end
        else begin
            $display("TEST_1 FAILED.");
        end

        $display("Test_1 complete.");
        $finish;
    end

endmodule