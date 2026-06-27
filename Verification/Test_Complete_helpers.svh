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

    function automatic bit assoc_selected(input int assoc_idx);
        begin
            assoc_selected = (ASSOC == 0) || (ASSOC == assoc_value_from_idx(assoc_idx));
        end
    endfunction


    task automatic record_assoc_result(input int test_id, input bit pass, input int errors);
        begin
            test_pass_by_assoc[test_id][active_assoc_idx] = pass;
            test_data_errors_by_assoc[test_id][active_assoc_idx] = errors;
            total_requests_by_assoc[active_assoc_idx] =
                total_requests_by_assoc[active_assoc_idx] + total_cpu_requests_sent;

            if (test_id == TEST3) begin
                test3_requests_by_assoc[active_assoc_idx] = total_cpu_requests_sent;
                test3_misses_by_assoc[active_assoc_idx]   = miss_count;
            end
        end
    endtask

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
            else if (test_id == TEST6)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_CPU_REQS;
            else if (test_id == TEST7)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST7_PRINT_CPU_REQS;
            else if (test_id == TEST8)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST8_PRINT_CPU_REQS;
            else if (test_id == TEST9)
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST9_PRINT_CPU_REQS;
            else
                print_cpu_reqs = assoc_debug_enabled(active_assoc_idx) && TEST10_PRINT_CPU_REQS;
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
            else if (test_id == TEST6)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_CPU_RESPS;
            else if (test_id == TEST7)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST7_PRINT_CPU_RESPS;
            else if (test_id == TEST8)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST8_PRINT_CPU_RESPS;
            else if (test_id == TEST9)
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST9_PRINT_CPU_RESPS;
            else
                print_cpu_resps = assoc_debug_enabled(active_assoc_idx) && TEST10_PRINT_CPU_RESPS;
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
            else if (test_id == TEST6)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_MEM_REQS;
            else if (test_id == TEST7)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST7_PRINT_MEM_REQS;
            else if (test_id == TEST8)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST8_PRINT_MEM_REQS;
            else if (test_id == TEST9)
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST9_PRINT_MEM_REQS;
            else
                print_mem_reqs = assoc_debug_enabled(active_assoc_idx) && TEST10_PRINT_MEM_REQS;
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
            else if (test_id == TEST6)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_MEM_RESPS;
            else if (test_id == TEST7)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST7_PRINT_MEM_RESPS;
            else if (test_id == TEST8)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST8_PRINT_MEM_RESPS;
            else if (test_id == TEST9)
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST9_PRINT_MEM_RESPS;
            else
                print_mem_resps = assoc_debug_enabled(active_assoc_idx) && TEST10_PRINT_MEM_RESPS;
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
            else if (test_id == TEST6)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_CHECKS;
            else if (test_id == TEST7)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST7_PRINT_CHECKS;
            else if (test_id == TEST8)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST8_PRINT_CHECKS;
            else if (test_id == TEST9)
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST9_PRINT_CHECKS;
            else
                print_checks = assoc_debug_enabled(active_assoc_idx) && TEST10_PRINT_CHECKS;
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
            else if (test_id == TEST6)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST6_PRINT_REPORT;
            else if (test_id == TEST7)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST7_PRINT_REPORT;
            else if (test_id == TEST8)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST8_PRINT_REPORT;
            else if (test_id == TEST9)
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST9_PRINT_REPORT;
            else
                print_report_en = assoc_debug_enabled(active_assoc_idx) && TEST10_PRINT_REPORT;
        end
    endfunction

    // CPU address is WORD-addressed.
    // cpu_addr[1:0] is the word offset inside the 4-word line.
function automatic [DATA_WIDTH-1:0] make_wdata(input int test_id, input int i);
        begin
            if ((test_id == TEST1) || (test_id == TEST4))
                make_wdata = DATA_WIDTH'(i + 1);
            else if (test_id == TEST5)
                make_wdata = DATA_WIDTH'(32'h5000_0000 + i);
            else if (test_id == TEST6)
                make_wdata = DATA_WIDTH'(32'h6000_0000 + i);
            else if (test_id == TEST7)
                make_wdata = DATA_WIDTH'(32'h7000_0000 + i);
            else if (test_id == TEST8)
                make_wdata = DATA_WIDTH'(32'h8000_0000 + i);
            else if (test_id == TEST9)
                make_wdata = DATA_WIDTH'(32'h9000_0000 + i);
            else if (test_id == TEST10)
                make_wdata = DATA_WIDTH'(32'hA100_0000 + i);
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

            $readmemh(ram_init_file_path, golden_mem);
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

            wait_for_responses(expected_total, "Test4");

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

            wait_for_responses(expected_total, "Test5");

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

            wait_for_responses(expected_total, "Test6");

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

    task automatic run_test7(input int num_cycles);
        bit pass;
        int seq_next;
        int expected_reads;
        int expected_writes;
        int expected_total;
        logic [ADDR_WIDTH-1:0] addr;
        begin
            expected_reads  = num_cycles * 2;
            expected_writes = num_cycles;
            expected_total  = expected_reads + expected_writes;

            reset_dut_and_scoreboard(TEST7, expected_writes, expected_reads);

            $display("==================================================");
            $display("Starting Test7");
            $display("Test7: for each address, issue read, write, read without waiting for responses");
            $display("Test7: cycles=%0d total requests=%0d", num_cycles, expected_total);
            $display("Test7: address sequence 0..%0d", num_cycles - 1);
            $display("Test7: CPU uses %0d reusable request ID slots", CPU_SLOT_COUNT);
            $display("==================================================");

            seq_next = 0;

            for (int i = 0; i < num_cycles; i++) begin
                addr = make_addr(TEST7, i);

                in_read_phase <= 1'b1;
                issue_one_request(TEST7, seq_next, 1'b0, addr, '0);
                seq_next++;

                in_read_phase <= 1'b0;
                issue_one_request(TEST7, seq_next, 1'b1, addr, make_wdata(TEST7, i));
                seq_next++;

                in_read_phase <= 1'b1;
                issue_one_request(TEST7, seq_next, 1'b0, addr, '0);
                seq_next++;
            end

            repeat (300) @(posedge clk);

            check_results(TEST7, expected_writes, expected_reads, pass);
            print_report(TEST7);
            record_assoc_result(TEST7, pass, data_error_count);

            test7_pass = pass;

            if (pass)
                $display("Test7 PASSED: read/write/read triples returned old then new data.");
            else
                $display("Test7 FAILED.");

            $display("Test7 complete.");
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    task automatic run_test8(input int num_cycles);
        bit pass;
        int seq_next;
        int expected_reads;
        int expected_writes;
        int expected_total;
        logic [ADDR_WIDTH-1:0] addr;
        begin
            expected_reads  = num_cycles * 2;
            expected_writes = num_cycles;
            expected_total  = expected_reads + expected_writes;

            reset_dut_and_scoreboard(TEST8, expected_writes, expected_reads);

            $display("==================================================");
            $display("Starting Test8");
            $display("Test8: for each cache line, issue read, write, read without waiting for responses");
            $display("Test8: cycles=%0d total requests=%0d", num_cycles, expected_total);
            $display("Test8: line addresses are word addresses 0, %0d, %0d, ...",
                     WORDS_PER_LINE,
                     2 * WORDS_PER_LINE);
            $display("Test8: CPU uses %0d reusable request ID slots", CPU_SLOT_COUNT);
            $display("==================================================");

            seq_next = 0;

            for (int i = 0; i < num_cycles; i++) begin
                addr = make_addr(TEST8, i);

                in_read_phase <= 1'b1;
                issue_one_request(TEST8, seq_next, 1'b0, addr, '0);
                seq_next++;

                in_read_phase <= 1'b0;
                issue_one_request(TEST8, seq_next, 1'b1, addr, make_wdata(TEST8, i));
                seq_next++;

                in_read_phase <= 1'b1;
                issue_one_request(TEST8, seq_next, 1'b0, addr, '0);
                seq_next++;
            end

            repeat (300) @(posedge clk);

            check_results(TEST8, expected_writes, expected_reads, pass);
            print_report(TEST8);
            record_assoc_result(TEST8, pass, data_error_count);

            test8_pass = pass;

            if (pass)
                $display("Test8 PASSED: line-stride read/write/read triples returned old then new data.");
            else
                $display("Test8 FAILED.");

            $display("Test8 complete.");
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask

    task automatic run_wrw_readback_test(input int test_id,
                                         input int num_cycles);
        bit pass;
        int seq_next;
        int expected_reads;
        int expected_writes;
        int expected_total;
        logic [ADDR_WIDTH-1:0] addr;
        begin
            expected_reads  = num_cycles * 2;
            expected_writes = num_cycles * 2;
            expected_total  = expected_reads + expected_writes;

            reset_dut_and_scoreboard(test_id, expected_writes, expected_reads);

            $display("==================================================");
            $display("Starting %s", test_name(test_id));
            $display("%s: for each address, issue write, read, write without waiting for responses",
                     test_name(test_id));
            $display("%s: after all write/read/write triples, read all addresses back",
                     test_name(test_id));
            $display("%s: cycles=%0d total requests=%0d",
                     test_name(test_id),
                     num_cycles,
                     expected_total);

            if (test_id == TEST10) begin
                $display("%s: line addresses are word addresses 0, %0d, %0d, ...",
                         test_name(test_id),
                         WORDS_PER_LINE,
                         2 * WORDS_PER_LINE);
            end
            else begin
                $display("%s: address sequence 0..%0d", test_name(test_id), num_cycles - 1);
            end

            $display("%s: CPU uses %0d reusable request ID slots", test_name(test_id), CPU_SLOT_COUNT);
            $display("==================================================");

            seq_next = 0;

            for (int i = 0; i < num_cycles; i++) begin
                addr = make_addr(test_id, i);

                in_read_phase <= 1'b0;
                issue_one_request(test_id, seq_next, 1'b1, addr, make_wdata(test_id, i));
                seq_next++;

                in_read_phase <= 1'b1;
                issue_one_request(test_id, seq_next, 1'b0, addr, '0);
                seq_next++;

                in_read_phase <= 1'b0;
                issue_one_request(test_id, seq_next, 1'b1, addr, make_wdata_second(test_id, i));
                seq_next++;
            end

            in_read_phase <= 1'b1;
            for (int i = 0; i < num_cycles; i++) begin
                addr = make_addr(test_id, i);
                issue_one_request(test_id, seq_next, 1'b0, addr, '0);
                seq_next++;
            end

            repeat (300) @(posedge clk);

            check_results(test_id, expected_writes, expected_reads, pass);
            print_report(test_id);
            record_assoc_result(test_id, pass, data_error_count);

            if (test_id == TEST9)
                test9_pass = pass;
            else
                test10_pass = pass;

            if (pass)
                $display("%s PASSED: write/read/write triples and final readback returned correct data.",
                         test_name(test_id));
            else
                $display("%s FAILED.", test_name(test_id));

            $display("%s complete.", test_name(test_id));
            $display("==================================================");
            repeat (20) @(posedge clk);
        end
    endtask
