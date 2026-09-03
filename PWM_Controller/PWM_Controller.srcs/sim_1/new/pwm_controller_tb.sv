`timescale 1ns / 1ps

module pwm_controller_tb;
    localparam integer CLK_PERIOD_NS = 20;

    logic        clk;
    logic        reset_n;
    logic [31:0] period_set;
    logic [31:0] pulse_width_set;
    logic        config_en;
    wire         pwm_out;

    integer error_count;

    pwm_controller dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .period_set      (period_set),
        .pulse_width_set (pulse_width_set),
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
            reset_n         = 1'b0;
            period_set      = 32'd0;
            pulse_width_set = 32'd0;
            config_en       = 1'b0;

            repeat (3) @(negedge clk);
            reset_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // 在下降沿设置配置，并保持 config_en 跨过一个上升沿。
    task automatic configure_pwm(
        input logic [31:0] new_period,
        input logic [31:0] new_pulse_width
    );
        begin
            @(negedge clk);
            period_set      = new_period;
            pulse_width_set = new_pulse_width;
            config_en       = 1'b1;

            @(posedge clk);
            @(negedge clk);
            config_en = 1'b0;
        end
    endtask

    // 同步到稳定的 HIGH->LOW 边界，再测量一个完整 PWM 周期。
    task automatic check_pwm_case(
        input integer      case_number,
        input logic [31:0] test_period,
        input logic [31:0] test_pulse_width
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
            expected_low    = test_pulse_width;
            expected_high   = test_period - test_pulse_width;
            expected_period = test_period;
            max_wait        = (test_period * 3) + 10;

            if ((test_period == 0) ||
                (test_pulse_width == 0) ||
                (test_pulse_width >= test_period)) begin
                $fatal(1,
                    "Case %0d uses a configuration deferred to Step 2.",
                    case_number);
            end

            configure_pwm(test_period, test_pulse_width);

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
                    "[PASS] Case %0d period=%0d pulse=%0d : LOW=%0d HIGH=%0d TOTAL=%0d",
                    case_number, test_period, test_pulse_width,
                    measured_low, measured_high, measured_period);
            end
            else begin
                error_count = error_count + 1;
                $display("[FAIL] Case %0d period=%0d pulse=%0d",
                         case_number, test_period, test_pulse_width);
                $display("Expected: LOW=%0d HIGH=%0d TOTAL=%0d",
                         expected_low, expected_high, expected_period);
                $display("Measured: LOW=%0d HIGH=%0d TOTAL=%0d",
                         measured_low, measured_high, measured_period);
            end
        end
    endtask

    initial begin
        reset_n         = 1'b0;
        period_set      = 32'd0;
        pulse_width_set = 32'd0;
        config_en       = 1'b0;
        error_count     = 0;

        reset_dut();

        check_pwm_case(1, 32'd10, 32'd4);
        check_pwm_case(2, 32'd15, 32'd10);
        check_pwm_case(3, 32'd8,  32'd1);
        check_pwm_case(4, 32'd8,  32'd7);

        if (error_count == 0) begin
            $display("================================");
            $display("ALL PWM TESTS PASSED");
            $display("================================");
            $finish;
        end
        else begin
            $fatal(1, "%0d PWM test case(s) failed.", error_count);
        end
    end
endmodule
