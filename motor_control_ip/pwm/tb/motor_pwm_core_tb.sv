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
    int phase = 0;
    int monitored_clocks = 0;
    bit previous_zero = 0, previous_peak = 0, previous_load = 0;
    // A modulo time index is independent of the DUT's directional counter.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) phase = 0;
        else if (!pwm_enable) phase = 0;
        else phase = (phase + 1) % (2*TBPRD_TEST);
        #1;
        if (reset_n) begin
            monitored_clocks++;
            check(int'(tbctr) == ((phase <= TBPRD_TEST) ? phase : 2*TBPRD_TEST-phase),"carrier sequence");
            check(count_up === (phase < TBPRD_TEST),"carrier direction");
            check(carrier_zero === (pwm_enable && phase == 0),"ZERO event alignment");
            check(carrier_peak === (pwm_enable && phase == TBPRD_TEST),"PEAK event alignment");
            check(!(carrier_zero && previous_zero),"ZERO pulse width");
            check(!(carrier_peak && previous_peak),"PEAK pulse width");
            check(!(compare_load_event && previous_load),"load pulse width");
        end
        previous_zero = carrier_zero; previous_peak = carrier_peak; previous_load = compare_load_event;
    end

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
    task automatic wait_for_zero;
        tick();
        while (!carrier_zero) tick();
    endtask
    task automatic expect_active(input int u, input int v, input int w);
        check({cmp_u_active,cmp_v_active,cmp_w_active} === {CW'(u),CW'(v),CW'(w)},"atomic active tuple");
    endtask
    task automatic expect_shadow(input int u, input int v, input int w);
        check({cmp_u_shadow,cmp_v_shadow,cmp_w_shadow} === {CW'(u),CW'(v),CW'(w)},"atomic shadow tuple");
    endtask
    initial begin
        apply_reset();
        send_cmp_command(0,4,8);
        check({cmp_u_active,cmp_v_active,cmp_w_active} === {4'd0,4'd4,4'd8},"disabled active preload");
        check({cmp_u_shadow,cmp_v_shadow,cmp_w_shadow} === {4'd0,4'd4,4'd8},"disabled shadow preload");
        check({shadow_pending,compare_load_event,pwm_u,pwm_v,pwm_w} === '0,"preload inhibited");
        pwm_enable = 1;
        wait_for_zero();
        repeat (8) tick(); check(carrier_peak === 1'b1,"peak 8 clocks after ZERO");
        repeat (8) tick(); check(carrier_zero === 1'b1,"ZERO 16 clocks after ZERO");
        send_cmp_command(2,4,6); wait_for_zero(); expect_active(2,4,6);
        tick(); tick();
        send_cmp_command(6,2,4);
        expect_active(2,4,6); expect_shadow(6,2,4);
        check(shadow_pending && !cmp_cmd_ready,"pending backpressure");
        cmp_u_cmd=1; cmp_v_cmd=3; cmp_w_cmd=5; cmp_cmd_valid=1;
        tick(); cmp_cmd_valid=0;
        expect_shadow(6,2,4); expect_active(2,4,6);
        wait_for_zero(); expect_active(6,2,4);
        check(compare_load_event && !shadow_pending,"ZERO load event");
        tick(); check(!compare_load_event,"load pulse clears");
        while (!(tbctr == 1 && !count_up)) tick();
        send_cmp_command(1,3,5); // This acceptance edge enters ZERO.
        check(carrier_zero && shadow_pending && !compare_load_event,"ZERO collision deferred");
        expect_active(6,2,4); expect_shadow(1,3,5);
        repeat (15) begin tick(); expect_active(6,2,4); end
        tick(); check(carrier_zero && compare_load_event,"collision loads at following ZERO");
        expect_active(1,3,5);
        if (error_count) $fatal(1,"scaffold failed: %0d",error_count);
        $display("STEP6B CARRIER/SHADOW/ATOMIC/ZERO-COLLISION PASSED");
        $finish;
    end
    initial begin
        #200000;
        $fatal(1,"Step6B watchdog expired");
    end
endmodule
