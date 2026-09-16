`timescale 1ns / 1ps
module pwm_breathe_top_tb;
    localparam int N = 8;
    localparam int PERIODS = 2;
    localparam int INTERVAL = N * PERIODS;
    logic clk = 0;
    logic key2_n = 1;
    wire led1;
    pwm_breathe_top #(
        .PWM_PERIOD_CYCLES(N), .UPDATE_PWM_PERIODS(PERIODS), .COMPARE_STEP(2)
    ) dut (.*);
    always #10 clk = ~clk;

    int compare_sequence [0:7] = '{8, 6, 4, 2, 0, 2, 4, 6};
    int edge_number = 0;
    int config_events = 0;
    time pulse_start;
    bit pulse_was_started = 0;
    always @(posedge clk) edge_number++;
    always @(posedge dut.config_en) begin
        pulse_start = $time;
        pulse_was_started = 1;
    end
    always @(negedge dut.config_en) begin
        // Async reset may truncate a pulse; normal pulses must be 20 ns.
        if (pulse_was_started && key2_n && $time - pulse_start != 20)
            $fatal(1, "config_en width was %0t, expected one clock", $time - pulse_start);
        pulse_was_started = 0;
    end

    task automatic tick;
        @(posedge clk); #1;
    endtask

    task automatic check_release;
        tick();
        if (dut.reset_n !== 0 || dut.config_en !== 0 || led1 !== 0)
            $fatal(1, "Reset escaped before two edges");
        tick();
        if (dut.reset_n !== 1 || dut.config_en !== 1 ||
            dut.compare_command !== N || dut.brightening !== 1 || led1 !== 0)
            $fatal(1, "Release/startup did not request C=N, brightening, LED OFF");
    endtask

    // Every level lasts exactly two complete PWM periods. Count physical LED
    // samples, independently calculate period phase/duty, and inspect the
    // core's applied value to catch command/config off-by-one errors.
    task automatic check_ramp(input int levels);
        int expected_c, high_count, low_count, previous_event;
        bit expected_direction, sampled_config;
        previous_event = -1;
        for (int level = 0; level < levels; level++) begin
            expected_c = compare_sequence[level % 8];
            expected_direction = (level % 8) < 4;
            high_count = 0;
            low_count = 0;
            for (int sample = 0; sample < INTERVAL; sample++) begin
                @(posedge clk);
                sampled_config = dut.config_en;
                if (sampled_config !== (sample == 0))
                    $fatal(1, "Config alignment mismatch level=%0d sample=%0d", level, sample);
                if (sample == 0) begin
                    if (dut.compare_command !== expected_c)
                        $fatal(1, "Compare sequence mismatch level=%0d got=%0d expected=%0d",
                            level, dut.compare_command, expected_c);
                    // Except for startup, the previous period must have ended.
                    if (level > 0 && dut.u_pwm.time_cnt !== N-1)
                        $fatal(1, "Config truncated a carrier period");
                end
                #1;
                if (sampled_config) begin
                    if (previous_event >= 0 && edge_number - previous_event != INTERVAL)
                        $fatal(1, "Update did not span exactly %0d clocks", INTERVAL);
                    previous_event = edge_number;
                    config_events++;
                end
                if ($isunknown(dut.compare_command) || dut.compare_command > N ||
                    dut.compare_active !== expected_c || dut.brightening !== expected_direction)
                    $fatal(1, "Compare bounds/active value/endpoint direction failed");
                if (dut.interval_count !== sample || dut.u_pwm.time_cnt !== sample % N ||
                    dut.u_pwm.compare_value_reg !== expected_c || dut.u_pwm.period_set_reg !== N)
                    $fatal(1, "Scheduler/core phase or applied config mismatch");
                if (led1 !== (sample % N >= expected_c) || led1 !== dut.pwm_core_out)
                    $fatal(1, "PWM sample/polarity mismatch");
                if (led1) high_count++; else low_count++;
                if (sample % N == N-1) begin
                    if (high_count != N-expected_c || low_count != expected_c)
                        $fatal(1, "Wrong HIGH/LOW count: C=%0d H=%0d L=%0d", expected_c, high_count, low_count);
                    high_count = 0;
                    low_count = 0;
                end
            end
            $display("PASS: level=%0d C=%0d HIGH=%0d LOW=%0d periods=%0d interval=%0d",
                level, expected_c, N-expected_c, expected_c, PERIODS, INTERVAL);
        end
    endtask

    initial begin
        check_release(); // Power-on with KEY2 already HIGH, as on the board.
        check_ramp(18);  // More than two envelopes, including both turns.
        wait (led1 === 1); #3; key2_n = 0; #1;
        if (led1 !== 0 || dut.reset_n !== 0 || dut.config_en !== 0 ||
            dut.compare_active !== N || dut.brightening !== 1 || dut.interval_count !== 0)
            $fatal(1, "KEY2 did not asynchronously reset the running demo");
        repeat (3) begin
            tick();
            if (led1 !== 0 || dut.reset_n !== 0) $fatal(1, "Held reset failed");
        end
        @(negedge clk); #3; key2_n = 1; #1;
        if (dut.reset_n !== 0) $fatal(1, "Reset release was asynchronous");
        check_release();
        check_ramp(10); // Restart must repeat the same OFF -> bright -> OFF path.
        if (config_events != 28) $fatal(1, "Unexpected config event count");
        $display("PASS: async reset during LED ON and deterministic OFF restart; 28 configuration events");
        $display("ALL STEP 5B BREATHING TESTS PASSED");
        $finish;
    end
    initial begin
        #20000;
        $fatal(1, "Breathing test watchdog expired");
    end
endmodule
