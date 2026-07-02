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

            for (int i = 0; i < cpu_resp_count_by_seq.size(); i++) begin
                cpu_resp_count_by_seq[i] = 0;
                read_done_by_seq[i]      = 1'b0;
            end

            for (int s = 0; s < CPU_SLOT_COUNT; s++) begin
                slot_busy[s] = 1'b0;
                slot_seq[s]  = 0;
                slot_addr[s] = 0;
            end

            for (int a = 0; a < RAM_DEPTH_WORDS; a++) begin
                outstanding_addr_busy[a] = 1'b0;
            end
        end
        else if (cpu_resp_valid && cpu_resp_ready) begin
            resp_slot = int'(cpu_resp_id);

            total_cpu_responses = total_cpu_responses + 1;

            if (resp_slot >= CPU_SLOT_COUNT) begin
                unexpected_resp_errors = unexpected_resp_errors + 1;

                $error("UNEXPECTED CPU RESPONSE SLOT OUT OF RANGE: test=%s slot=%0d max_slot=%0d hit=%0b rdata=%h",
                       test_name(active_test),
                       resp_slot,
                       CPU_SLOT_COUNT - 1,
                       cpu_resp_hit,
                       cpu_resp_rdata);
            end
            else if (!slot_busy[resp_slot]) begin
                unexpected_resp_errors = unexpected_resp_errors + 1;

                $error("UNEXPECTED CPU RESPONSE TO FREE SLOT: test=%s slot=%0d hit=%0b rdata=%h",
                       test_name(active_test),
                       resp_slot,
                       cpu_resp_hit,
                       cpu_resp_rdata);
            end
            else begin
                resp_seq = slot_seq[resp_slot];
                slot_busy[resp_slot] = 1'b0;
                if (slot_addr[resp_slot] < RAM_DEPTH_WORDS)
                    outstanding_addr_busy[slot_addr[resp_slot]] = 1'b0;

                if ((resp_seq < 0) || (resp_seq >= cpu_resp_count_by_seq.size())) begin
                    unexpected_resp_errors = unexpected_resp_errors + 1;
                    $error("UNEXPECTED CPU RESPONSE SEQUENCE OUT OF RANGE: test=%s req_seq=%0d size=%0d slot=%0d hit=%0b rdata=%h",
                           test_name(active_test),
                           resp_seq,
                           cpu_resp_count_by_seq.size(),
                           resp_slot,
                           cpu_resp_hit,
                           cpu_resp_rdata);
                end
                else begin
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
            if (mem_req_valid) begin
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

            mem_req_valid_d = mem_req_valid;
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
