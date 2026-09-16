`timescale 1ns / 1ps
module pwm_demo_top_tb;
    logic clk = 0;
    logic key2_n = 1;
    wire led1;
    pwm_demo_top #(.PERIOD_CYCLES(8), .COMPARE_CYCLES(4)) dut (.*);
    always #10 clk = ~clk;
    int config_samples = 0;
    always @(posedge clk)
        if (dut.config_en) config_samples++;

    task automatic tick;
        @(posedge clk); #1;
    endtask

    task automatic check_release_and_blink;
        int before_samples;
        before_samples = config_samples;
        tick();
        if (dut.reset_n !== 0 || led1 !== 0 || dut.config_en !== 0)
            $fatal(1, "Reset released before two clock edges");
        tick();
        if (dut.reset_n !== 1 || dut.config_en !== 1 || led1 !== 0)
            $fatal(1, "Two-edge reset release / config pulse failed");
        tick(); // load the fixed configuration, counter starts at zero
        if (dut.config_en !== 0 || dut.u_pwm.time_cnt !== 0)
            $fatal(1, "One-shot config did not complete");
        for (int k = 0; k < 32; k++) begin
            if (led1 !== ((k % 8) >= 4) || led1 !== dut.pwm_core_out)
                $fatal(1, "LED duty/polarity failure at sample %0d", k);
            if (dut.config_en !== 0)
                $fatal(1, "Repeated configuration pulse");
            tick();
        end
        if (config_samples != before_samples + 1)
            $fatal(1, "Expected exactly one sampled config pulse");
    endtask

    initial begin
        // Startup with no external button press exercises FPGA INIT values.
        check_release_and_blink();
        $display("PASS: startup, two-edge release, one-shot config, four 50%% periods");
        // Assert while LED is ON and away from a clock edge.
        wait (led1 === 1); #3; key2_n = 0; #1;
        if (dut.reset_n !== 0 || dut.config_en !== 0 || led1 !== 0)
            $fatal(1, "Asynchronous assertion did not turn LED off");
        repeat (3) begin
            tick();
            if (led1 !== 0 || dut.reset_n !== 0)
                $fatal(1, "Reset hold failed");
        end
        @(negedge clk); #3; key2_n = 1; #1;
        if (dut.reset_n !== 0) $fatal(1, "Asynchronous deassertion escaped");
        check_release_and_blink();
        $display("PASS: asynchronous assertion, held reset, deterministic restart");
        $display("ALL STEP 5A BOARD TESTS PASSED");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "Board test watchdog expired");
    end
endmodule
