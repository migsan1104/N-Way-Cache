`timescale 1ns/1ps

module Basic_Test;

    localparam int ADDR_WIDTH       = 32;
    localparam int DATA_WIDTH       = 32;
    localparam int CPU_ID_WIDTH     = 8;
    localparam int MSHR_ID_WIDTH    = 2;

    localparam int CACHE_BYTES      = 4096;
    localparam int LINE_BYTES       = 16;
    localparam int ASSOC            = 4;

    localparam int WORDS_PER_LINE   = LINE_BYTES / (DATA_WIDTH / 8);
    localparam int CACHE_LINES      = CACHE_BYTES / LINE_BYTES;

    localparam int RAM_DEPTH_WORDS  = CACHE_BYTES * 16;
    localparam int RAM_READ_LATENCY = 20;

    localparam int NUM_WRITES       = 100;
    localparam int NUM_READS        = 100;

    localparam int EXPECTED_TOTAL_CPU_RESPONSES = NUM_WRITES + NUM_READS;

    // ============================================================
    // Debug print enables
    // ============================================================
    localparam bit PRINT_CPU_REQS   = 1'b1;
    localparam bit PRINT_CPU_RESPS  = 1'b1;
    localparam bit PRINT_MEM_REQS   = 1'b1;
    localparam bit PRINT_MEM_RESPS  = 1'b1;
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
    int cpu_resp_count [0:255];

    int hit_count;
    int miss_count;
    int read_miss_count;

    int mem_req_valid_cycles;
    int mem_read_req_cycles;
    int mem_write_req_cycles;

    int write_phase_mem_write_req_cycles;
    int read_phase_mem_write_req_cycles;

    int write_phase_mem_read_req_cycles;
    int read_phase_mem_read_req_cycles;

    int mem_resp_count;

    int mem_req_valid_pulses;
    logic mem_req_valid_d;

    logic in_read_phase;

    int expected_total_line_allocations;
    int expected_evictions;
    int expected_refill_transactions;
    int expected_eviction_transactions;
    int expected_mem_transactions;

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

    task automatic send_100_write_misses_back_to_back;
        int i;
        begin
            i = 0;

            while (i < NUM_WRITES) begin
                cpu_req_valid <= 1'b1;
                cpu_req_write <= 1'b1;
                cpu_req_addr  <= ADDR_WIDTH'(2 + (i * 4));
                cpu_req_wdata <= 32'hA000_0000 + i;
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

    task automatic send_100_read_requests_back_to_back;
        int i;
        begin
            i = 0;

            while (i < NUM_READS) begin
                cpu_req_valid <= 1'b1;
                cpu_req_write <= 1'b0;
                cpu_req_addr  <= ADDR_WIDTH'(2 + (i * 4));
                cpu_req_wdata <= '0;
                cpu_req_id    <= CPU_ID_WIDTH'(i + NUM_WRITES);

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
        end
        else if (cpu_req_valid && cpu_req_ready) begin
            total_cpu_requests_sent <= total_cpu_requests_sent + 1;

            if (PRINT_CPU_REQS) begin
                $display("[%0t] CPU_REQ_SEND: phase=%s write=%0b addr=%h wdata=%h cpu_id=%0d total_cpu_req_now=%0d",
                         $time,
                         in_read_phase ? "READ_PHASE" : "WRITE_PHASE",
                         cpu_req_write,
                         cpu_req_addr,
                         cpu_req_wdata,
                         cpu_req_id,
                         total_cpu_requests_sent + 1);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            total_cpu_responses <= 0;
            hit_count           <= 0;
            miss_count          <= 0;

            for (int i = 0; i < 256; i++) begin
                cpu_resp_count[i] <= 0;
            end
        end
        else if (cpu_resp_valid && cpu_resp_ready) begin
            total_cpu_responses <= total_cpu_responses + 1;
            cpu_resp_count[cpu_resp_id] <= cpu_resp_count[cpu_resp_id] + 1;

            if (cpu_resp_hit)
                hit_count <= hit_count + 1;
            else
                miss_count <= miss_count + 1;

            if (PRINT_CPU_RESPS) begin
                $display("[%0t] CPU RESP: phase=%s cpu_id=%0d count_now=%0d hit=%0b rdata=%h total_now=%0d hits_now=%0d misses_now=%0d",
                         $time,
                         in_read_phase ? "READ_PHASE" : "WRITE_PHASE",
                         cpu_resp_id,
                         cpu_resp_count[cpu_resp_id] + 1,
                         cpu_resp_hit,
                         cpu_resp_rdata,
                         total_cpu_responses + 1,
                         hit_count + (cpu_resp_hit ? 1 : 0),
                         miss_count + (!cpu_resp_hit ? 1 : 0));
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_req_valid_cycles              <= 0;
            mem_read_req_cycles               <= 0;
            mem_write_req_cycles              <= 0;
            write_phase_mem_write_req_cycles  <= 0;
            read_phase_mem_write_req_cycles   <= 0;
            write_phase_mem_read_req_cycles   <= 0;
            read_phase_mem_read_req_cycles    <= 0;
            mem_req_valid_pulses              <= 0;
            mem_req_valid_d                   <= 1'b0;
        end
        else begin
            mem_req_valid_d <= mem_req_valid;

            if (mem_req_valid) begin
                mem_req_valid_cycles <= mem_req_valid_cycles + 1;

                if (mem_req_write) begin
                    mem_write_req_cycles <= mem_write_req_cycles + 1;

                    if (in_read_phase)
                        read_phase_mem_write_req_cycles <= read_phase_mem_write_req_cycles + 1;
                    else
                        write_phase_mem_write_req_cycles <= write_phase_mem_write_req_cycles + 1;
                end
                else begin
                    mem_read_req_cycles <= mem_read_req_cycles + 1;

                    if (in_read_phase)
                        read_phase_mem_read_req_cycles <= read_phase_mem_read_req_cycles + 1;
                    else
                        write_phase_mem_read_req_cycles <= write_phase_mem_read_req_cycles + 1;
                end

                if (PRINT_MEM_REQS) begin
                    $display("[%0t] CACHE IS SENDING: phase=%s write=%0b addr=%h mshr_id=%0d wdata=%h total_mem_req_now=%0d read_req_now=%0d writeback_req_now=%0d write_phase_wb_now=%0d read_phase_wb_now=%0d",
                             $time,
                             in_read_phase ? "READ_PHASE" : "WRITE_PHASE",
                             mem_req_write,
                             mem_req_addr,
                             mem_req_id,
                             mem_req_wdata,
                             mem_req_valid_cycles + 1,
                             mem_read_req_cycles + (!mem_req_write ? 1 : 0),
                             mem_write_req_cycles + (mem_req_write ? 1 : 0),
                             write_phase_mem_write_req_cycles + ((!in_read_phase && mem_req_write) ? 1 : 0),
                             read_phase_mem_write_req_cycles  + (( in_read_phase && mem_req_write) ? 1 : 0));
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
                $display("[%0t] MEM RESP: phase=%s mshr_id=%0d rdata=%h total_mem_resp_now=%0d",
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
        $display("Starting 100 back-to-back write misses");
        $display("==================================================");

        in_read_phase <= 1'b0;
        send_100_write_misses_back_to_back();

        wait (total_cpu_responses >= NUM_WRITES);
        repeat (10) @(posedge clk);

        $display("==================================================");
        $display("Starting 100 back-to-back read requests");
        $display("==================================================");

        in_read_phase <= 1'b1;
        send_100_read_requests_back_to_back();

        wait (total_cpu_responses >= EXPECTED_TOTAL_CPU_RESPONSES);
        repeat (200) @(posedge clk);

        read_miss_count = miss_count - NUM_WRITES;

        if (read_miss_count < 0) begin
            read_miss_count = 0;
        end

        expected_total_line_allocations = NUM_WRITES + read_miss_count;

        expected_evictions = expected_total_line_allocations - CACHE_LINES;

        if (expected_evictions < 0) begin
            expected_evictions = 0;
        end

        expected_refill_transactions = (NUM_WRITES * (WORDS_PER_LINE - 1)) +
                                       (read_miss_count * WORDS_PER_LINE);

        expected_eviction_transactions = expected_evictions * WORDS_PER_LINE;

        expected_mem_transactions = expected_refill_transactions +
                                    expected_eviction_transactions;

        if (PRINT_REPORT) begin
            $display("==================================================");
            $display("Basic_Test Simulation Report");
            $display("Total CPU requests sent              = %0d", total_cpu_requests_sent);
            $display("Total CPU responses                  = %0d", total_cpu_responses);
            $display("CPU hit responses                    = %0d", hit_count);
            $display("CPU miss responses                   = %0d", miss_count);
            $display("Read miss responses                  = %0d", read_miss_count);
            $display("Cache lines                          = %0d", CACHE_LINES);
            $display("Words per line                       = %0d", WORDS_PER_LINE);
            $display("Expected line allocations            = %0d", expected_total_line_allocations);
            $display("Expected evictions                   = %0d", expected_evictions);
            $display("Expected refill transactions         = %0d", expected_refill_transactions);
            $display("Expected eviction transactions       = %0d", expected_eviction_transactions);
            $display("Expected mem transactions            = %0d", expected_mem_transactions);
            $display("mem_req_valid accepted cycles        = %0d", mem_req_valid_cycles);
            $display("mem read request cycles              = %0d", mem_read_req_cycles);
            $display("mem writeback request cycles         = %0d", mem_write_req_cycles);
            $display("write-phase read request cycles      = %0d", write_phase_mem_read_req_cycles);
            $display("read-phase read request cycles       = %0d", read_phase_mem_read_req_cycles);
            $display("write-phase writeback cycles         = %0d", write_phase_mem_write_req_cycles);
            $display("read-phase writeback cycles          = %0d", read_phase_mem_write_req_cycles);
            $display("write-phase dirty evictions          = %0d", write_phase_mem_write_req_cycles / WORDS_PER_LINE);
            $display("read-phase dirty evictions           = %0d", read_phase_mem_write_req_cycles / WORDS_PER_LINE);
            $display("total dirty evictions observed       = %0d", mem_write_req_cycles / WORDS_PER_LINE);
            $display("mem_resp_valid accepted cycles       = %0d", mem_resp_count);
            $display("mem_req_valid pulse count            = %0d", mem_req_valid_pulses);
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

        if (mem_req_valid_cycles !== expected_mem_transactions) begin
            $error("Expected %0d mem_req_valid accepted cycles, got %0d",
                   expected_mem_transactions,
                   mem_req_valid_cycles);
        end

        if (mem_read_req_cycles !== expected_refill_transactions) begin
            $error("Expected %0d memory read/refill request cycles, got %0d",
                   expected_refill_transactions,
                   mem_read_req_cycles);
        end

        if (mem_write_req_cycles !== expected_eviction_transactions) begin
            $error("Expected %0d memory writeback request cycles, got %0d",
                   expected_eviction_transactions,
                   mem_write_req_cycles);
        end

        if (mem_resp_count !== expected_refill_transactions) begin
            $error("Expected %0d mem responses, got %0d",
                   expected_refill_transactions,
                   mem_resp_count);
        end

        for (int i = 0; i < 256; i++) begin
            if (cpu_resp_count[i] > 1) begin
                $error("CPU id %0d received duplicate responses: %0d",
                       i,
                       cpu_resp_count[i]);
            end
        end

        $display("Basic_Test complete.");
        $finish;
    end

endmodule
