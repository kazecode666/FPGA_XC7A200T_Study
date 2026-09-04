`timescale 1ns / 1ps

module pwm_controller_tb;
    localparam integer CLK_PERIOD_NS = 20;
    localparam integer CONSTANT_CHECK_CLOCKS = 20;

    logic        clk;
    logic        reset_n;
    logic [31:0] period_set;
    logic [31:0] compare_value_set;
    logic        config_en;
    wire         pwm_out;

    integer error_count;

    pwm_controller dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .period_set      (period_set),
        .compare_value_set(compare_value_set),
        .config_en       (config_en),
        .pwm_out         (pwm_out)
    );

    // 50 MHz 时钟：周期为 20 ns。
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // 异步拉低复位，并在时钟下降沿释放，避免与 DUT 的上升沿采样竞争。
    task automatic reset_dut;
        begin
            reset_n          = 1'b0;
            period_set       = 32'd0;
            compare_value_set = 32'd0;
            config_en        = 1'b0;

            repeat (3) @(negedge clk);
            reset_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // 在下降沿设置配置，并保持 config_en 跨过一个上升沿。
    task automatic configure_pwm(
        input logic [31:0] new_period,
        input logic [31:0] new_compare_value
    );
        begin
            @(negedge clk);
            period_set       = new_period;
            compare_value_set = new_compare_value;
            config_en        = 1'b1;

            @(posedge clk);
            @(negedge clk);
            config_en = 1'b0;
        end
    endtask

    // 同步到稳定的 HIGH->LOW 边界，再测量一个完整 PWM 周期。
    task automatic check_pwm_case(
        input integer      case_number,
        input logic [31:0] test_period,
        input logic [31:0] test_compare_value
    );
        integer expected_low;
        integer expected_high;
        integer expected_period;
        integer measured_low;
        integer measured_high;
        integer measured_period;
        integer wait_count;
        integer max_wait;
        logic   sync_ok;
        begin
            expected_low    = test_compare_value;
            expected_high   = test_period - test_compare_value;
            expected_period = test_period;
            max_wait        = (test_period * 3) + 10;

            if ((test_period == 0) ||
                (test_compare_value == 0) ||
                (test_compare_value >= test_period)) begin
                $fatal(1,
                    "Case %0d normal PWM check requires 0 < C < N.",
                    case_number);
            end

            configure_pwm(test_period, test_compare_value);

            // 先观察到 HIGH，再等待下一次 LOW，排除配置过渡阶段。
            sync_ok    = 1'b1;
            wait_count = 0;
            while ((pwm_out !== 1'b1) && (wait_count < max_wait)) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            if (pwm_out !== 1'b1) begin
                sync_ok = 1'b0;
            end

            wait_count = 0;
            while (sync_ok && (pwm_out !== 1'b0) &&
                   (wait_count < max_wait)) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            if (pwm_out !== 1'b0) begin
                sync_ok = 1'b0;
            end

            measured_low    = 0;
            measured_high   = 0;
            measured_period = 0;

            if (sync_ok) begin
                // 当前采样点是一个稳定周期的第一个 LOW。
                while ((pwm_out === 1'b0) &&
                       (measured_low <= expected_period)) begin
                    measured_low = measured_low + 1;
                    @(negedge clk);
                end

                while ((pwm_out === 1'b1) &&
                       (measured_high <= expected_period)) begin
                    measured_high = measured_high + 1;
                    @(negedge clk);
                end

                measured_period = measured_low + measured_high;
            end

            if (sync_ok &&
                (pwm_out === 1'b0) &&
                (measured_low == expected_low) &&
                (measured_high == expected_high) &&
                (measured_period == expected_period)) begin
                $display(
                    "[PASS] Case %0d N=%0d C=%0d : LOW=%0d HIGH=%0d TOTAL=%0d",
                    case_number, test_period, test_compare_value,
                    measured_low, measured_high, measured_period);
            end
            else begin
                error_count = error_count + 1;
                $display("[FAIL] Case %0d N=%0d C=%0d",
                         case_number, test_period, test_compare_value);
                $display("Expected: LOW=%0d HIGH=%0d TOTAL=%0d",
                         expected_low, expected_high, expected_period);
                $display("Measured: LOW=%0d HIGH=%0d TOTAL=%0d",
                         measured_low, measured_high, measured_period);
            end
        end
    endtask

    // compare_value=0 时，非零周期内输出应持续为 HIGH。
    task automatic check_constant_high(
        input integer      case_number,
        input logic [31:0] test_period,
        input logic [31:0] test_compare_value
    );
        integer sample_count;
        logic   case_passed;
        begin
            configure_pwm(test_period, test_compare_value);
            @(negedge clk);

            case_passed = 1'b1;
            for (sample_count = 0;
                 sample_count < CONSTANT_CHECK_CLOCKS;
                 sample_count = sample_count + 1) begin
                if (pwm_out !== 1'b1) begin
                    case_passed = 1'b0;
                end
                @(negedge clk);
            end

            if (case_passed) begin
                $display("[PASS] Case %0d N=%0d C=%0d : CONSTANT HIGH",
                         case_number, test_period, test_compare_value);
            end
            else begin
                error_count = error_count + 1;
                $display("[FAIL] Case %0d N=%0d C=%0d : expected CONSTANT HIGH",
                         case_number, test_period, test_compare_value);
            end
        end
    endtask

    // compare_value>=period 时，输出应持续为 LOW。
    task automatic check_constant_low(
        input integer      case_number,
        input logic [31:0] test_period,
        input logic [31:0] test_compare_value
    );
        integer sample_count;
        logic   case_passed;
        begin
            configure_pwm(test_period, test_compare_value);
            @(negedge clk);

            case_passed = 1'b1;
            for (sample_count = 0;
                 sample_count < CONSTANT_CHECK_CLOCKS;
                 sample_count = sample_count + 1) begin
                if (pwm_out !== 1'b0) begin
                    case_passed = 1'b0;
                end
                @(negedge clk);
            end

            if (case_passed) begin
                $display("[PASS] Case %0d N=%0d C=%0d : CONSTANT LOW",
                         case_number, test_period, test_compare_value);
            end
            else begin
                error_count = error_count + 1;
                $display("[FAIL] Case %0d N=%0d C=%0d : expected CONSTANT LOW",
                         case_number, test_period, test_compare_value);
            end
        end
    endtask

    // period=0 时 PWM 禁用，输出和计数器都应保持为 0。
    task automatic check_disabled(
        input integer      case_number,
        input logic [31:0] test_period,
        input logic [31:0] test_compare_value
    );
        integer sample_count;
        logic   case_passed;
        begin
            configure_pwm(test_period, test_compare_value);
            @(negedge clk);

            case_passed = 1'b1;
            for (sample_count = 0;
                 sample_count < CONSTANT_CHECK_CLOCKS;
                 sample_count = sample_count + 1) begin
                if ((pwm_out !== 1'b0) || (dut.time_cnt !== 32'd0)) begin
                    case_passed = 1'b0;
                end
                @(negedge clk);
            end

            if (case_passed) begin
                $display("[PASS] Case %0d N=%0d C=%0d : PWM DISABLED / LOW",
                         case_number, test_period, test_compare_value);
            end
            else begin
                error_count = error_count + 1;
                $display("[FAIL] Case %0d N=%0d C=%0d : expected PWM DISABLED / LOW",
                         case_number, test_period, test_compare_value);
            end
        end
    endtask

    // 在下降沿检查当前 counter 与寄存式 PWM 输出是否描述同一状态。
    task automatic check_counter_pwm_alignment(
        input logic [31:0] test_period,
        input logic [31:0] test_compare_value
    );
        integer sample_count;
        integer check_clocks;
        logic   expected_pwm;
        logic   case_passed;
        begin
            configure_pwm(test_period, test_compare_value);

            if(test_period == 32'd0)
                check_clocks = CONSTANT_CHECK_CLOCKS;
            else
                check_clocks = test_period * 2;

            case_passed = 1'b1;
            for (sample_count = 0;
                 sample_count < check_clocks;
                 sample_count = sample_count + 1) begin
                if(dut.period_set_reg == 32'd0)
                    expected_pwm = 1'b0;
                else
                    expected_pwm =
                        (dut.time_cnt >= dut.compare_value_reg);

                if(pwm_out !== expected_pwm)
                    case_passed = 1'b0;

                @(negedge clk);
            end

            if(case_passed) begin
                $display("[PASS] PWM counter/output alignment N=%0d C=%0d",
                         test_period, test_compare_value);
            end
            else begin
                error_count = error_count + 1;
                $display("[FAIL] PWM counter/output alignment N=%0d C=%0d",
                         test_period, test_compare_value);
            end
        end
    endtask

    initial begin
        reset_n          = 1'b0;
        period_set       = 32'd0;
        compare_value_set = 32'd0;
        config_en        = 1'b0;
        error_count      = 0;

        reset_dut();

        check_pwm_case(1, 32'd10, 32'd4);
        check_pwm_case(2, 32'd15, 32'd10);
        check_pwm_case(3, 32'd8,  32'd1);
        check_pwm_case(4, 32'd8,  32'd7);
        check_constant_high(5, 32'd10, 32'd0);
        check_constant_low (6, 32'd10, 32'd10);
        check_constant_low (7, 32'd10, 32'd15);
        check_disabled     (8, 32'd0,  32'd0);

        check_counter_pwm_alignment(32'd10, 32'd4);
        check_counter_pwm_alignment(32'd10, 32'd0);
        check_counter_pwm_alignment(32'd10, 32'd10);
        check_counter_pwm_alignment(32'd0,  32'd0);

        if (error_count == 0) begin
            $display("================================");
            $display("ALL STEP 2.5 PWM TESTS PASSED");
            $display("================================");
            $finish;
        end
        else begin
            $fatal(1, "%0d PWM test case(s) failed.", error_count);
        end
    end
endmodule
