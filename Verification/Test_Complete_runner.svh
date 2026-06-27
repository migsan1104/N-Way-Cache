    function automatic bit all_tests_passed;
        begin
            all_tests_passed = 1'b1;

            for (int t = TEST1; t <= TEST_LAST; t++) begin
                for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
                    if (assoc_selected(a) && !test_pass_by_assoc[t][a])
                        all_tests_passed = 1'b0;
                end
            end
        end
    endfunction

    function automatic bit assoc_tests_passed(input int assoc_idx);
        begin
            assoc_tests_passed = 1'b1;

            for (int t = TEST1; t <= TEST_LAST; t++) begin
                if (assoc_selected(assoc_idx) && !test_pass_by_assoc[t][assoc_idx])
                    assoc_tests_passed = 1'b0;
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
            else if (test_id == TEST6)
                run_test6(TEST6_REPEAT_COUNT, TEST6_NUM_LINES);
            else if (test_id == TEST7)
                run_test7(TEST7_NUM_CYCLES);
            else if (test_id == TEST8)
                run_test8(TEST8_NUM_CYCLES);
            else if (test_id == TEST9)
                run_wrw_readback_test(TEST9, TEST9_NUM_CYCLES);
            else
                run_wrw_readback_test(TEST10, TEST10_NUM_CYCLES);
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
        test7_pass = 1'b0;
        test8_pass = 1'b0;
        test9_pass = 1'b0;
        test10_pass = 1'b0;

        if ((ASSOC != 0) &&
            (ASSOC != 1) &&
            (ASSOC != 2) &&
            (ASSOC != 4) &&
            (ASSOC != 8) &&
            (ASSOC != 16)) begin
            $fatal(1, "Unsupported ASSOC=%0d. Use 0, 1, 2, 4, 8, or 16.", ASSOC);
        end

        for (int t = TEST1; t <= TEST_LAST; t++) begin
            for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
                test_pass_by_assoc[t][a] = !assoc_selected(a);
                test_data_errors_by_assoc[t][a] = 0;
            end
        end

        for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
            total_requests_by_assoc[a] = 0;
            test3_requests_by_assoc[a] = 0;
            test3_misses_by_assoc[a]   = 0;
        end

        clear_scoreboard();
        drive_idle();

        // Associativity-major order:
        //   assoc1:  Test1, Test2, Test3, Test4, Test5, Test6, Test7, Test8, Test9, Test10
        //   assoc2:  Test1, Test2, Test3, Test4, Test5, Test6, Test7, Test8, Test9, Test10
        //   assoc4:  Test1, Test2, Test3, Test4, Test5, Test6, Test7, Test8, Test9, Test10
        //   assoc8:  Test1, Test2, Test3, Test4, Test5, Test6, Test7, Test8, Test9, Test10
        //   assoc16: Test1, Test2, Test3, Test4, Test5, Test6, Test7, Test8, Test9, Test10
        // This is closer to running the original single-DUT testbench once per associativity.
        for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
            if (!assoc_selected(a))
                continue;

            active_assoc_idx   = a;
            active_assoc_value = assoc_value_from_idx(a);
            drive_idle();
            @(posedge clk);

            $display("==================================================");
            $display("STARTING ASSOCIATIVITY %0d FULL TEST SUITE", assoc_value_from_idx(a));
            $display("Associativity %0d debug gate = %0b", assoc_value_from_idx(a), assoc_debug_enabled(a));
            $display("==================================================");

            for (int t = TEST1; t <= TEST_LAST; t++) begin
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
        for (int t = TEST1; t <= TEST_LAST; t++) begin
            for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
                if (assoc_selected(a))
                    $display("%s", test_status_line(t, a));
            end
        end

        $display("==================================================");
        $display("FINAL REPORT PER ASSOCIATIVITY");
        for (int a = 0; a < NUM_ASSOC_CONFIGS; a++) begin
            real test3_miss_rate;

            if (assoc_selected(a)) begin
                if (test3_requests_by_assoc[a] == 0)
                    test3_miss_rate = 0.0;
                else
                    test3_miss_rate = (real'(test3_misses_by_assoc[a]) * 100.0) /
                                      real'(test3_requests_by_assoc[a]);

                $display("Associativity %0d %s | Test3 miss rate = %0.2f%% | random requests = %0d | total requests = %0d",
                         assoc_value_from_idx(a),
                         pass_fail(assoc_tests_passed(a)),
                         test3_miss_rate,
                         test3_requests_by_assoc[a],
                         total_requests_by_assoc[a]);
            end
        end

        if (all_tests_passed())
            $display("Congrats all associativity tests passed");
        else
            $display("One or more associativity tests failed");
        $display("==================================================");

        $finish;
    end
