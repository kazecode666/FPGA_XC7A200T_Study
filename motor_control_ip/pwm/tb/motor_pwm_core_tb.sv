`timescale 1ns/1ps
module motor_pwm_core_tb;
    localparam int unsigned TBPRD_TEST = 8;
    localparam int unsigned CW = $clog2(TBPRD_TEST + 1);
    logic clk = 0;
    always #10 clk = ~clk;
    logic reset_n = 1, pwm_enable = 0, cmp_cmd_valid = 0;
    logic [CW-1:0] cmp_u_cmd = 0, cmp_v_cmd = 0, cmp_w_cmd = 0;
    wire cmp_cmd_ready, pwm_u, pwm_v, pwm_w, count_up;
    wire carrier_zero, carrier_peak, shadow_pending, compare_load_event;
    wire [CW-1:0] tbctr;
    wire [CW-1:0] cmp_u_shadow, cmp_v_shadow, cmp_w_shadow;
    wire [CW-1:0] cmp_u_active, cmp_v_active, cmp_w_active;
    int error_count = 0;
    motor_pwm_core #(.TBPRD(TBPRD_TEST), .COUNTER_WIDTH(CW)) dut (.*);

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            error_count++;
            $error("%0t %s", $time, message);
        end
    endtask
    function automatic logic expected_pwm(input int unsigned cmp,
                                          input int unsigned ctr, input logic up);
        if (cmp == 0) expected_pwm = 0;
        else if (cmp >= TBPRD_TEST) expected_pwm = 1;
        else if (up) expected_pwm = (ctr < cmp);
        else expected_pwm = (ctr <= cmp);
    endfunction
    task automatic tick;
        @(negedge clk); #1;
    endtask
    task automatic safe_reset;
        check({tbctr,cmp_u_active,cmp_v_active,cmp_w_active,
               cmp_u_shadow,cmp_v_shadow,cmp_w_shadow} === '0,"reset registers");
        check(count_up === 1'b1,"reset direction UP");
        check({pwm_u,pwm_v,pwm_w,carrier_zero,carrier_peak,
               shadow_pending,compare_load_event} === '0,"reset outputs/events");
    endtask
    task automatic apply_reset;
        tick(); reset_n = 0; #1; safe_reset();
        tick(); reset_n = 1; tick(); safe_reset();
    endtask
    task automatic send_cmp_command(input int u, input int v, input int w);
        while (!cmp_cmd_ready) tick();
        cmp_u_cmd = CW'(u); cmp_v_cmd = CW'(v); cmp_w_cmd = CW'(w);
        cmp_cmd_valid = 1;
        tick(); cmp_cmd_valid = 0;
    endtask
    initial begin
        apply_reset();
        send_cmp_command(0,4,8);
        check({cmp_u_active,cmp_v_active,cmp_w_active} === {4'd0,4'd4,4'd8},"disabled active preload");
        check({cmp_u_shadow,cmp_v_shadow,cmp_w_shadow} === {4'd0,4'd4,4'd8},"disabled shadow preload");
        check({shadow_pending,compare_load_event,pwm_u,pwm_v,pwm_w} === '0,"preload inhibited");
        if (error_count) $fatal(1,"scaffold failed: %0d",error_count);
        $display("STEP6B RESET/PRELOAD SCAFFOLD PASSED");
        $finish;
    end
    initial begin
        #200000;
        $fatal(1,"Step6B watchdog expired");
    end
endmodule
