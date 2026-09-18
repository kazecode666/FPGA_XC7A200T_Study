`timescale 1ns/1ps
module motor_pwm_core_tb;
    localparam int unsigned TBPRD_TEST = 8;
    localparam int unsigned CW = $clog2(TBPRD_TEST + 1);
    logic clk = 0;
    always #10 clk = ~clk;
    logic reset_n = 0, pwm_enable = 0, cmp_cmd_valid = 0;
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
    logic [3*CW-1:0] model_shadow = '0, model_active = '0;
    bit model_pending = 0, model_load = 0, accepted;
    bit model_running = 0, model_zero = 0;
    // A modulo time index is independent of the DUT's directional counter.
    always @(posedge clk or negedge reset_n) begin
        accepted = reset_n && cmp_cmd_valid && (!pwm_enable || !model_pending);
        model_zero = 0;
        if (!reset_n || !pwm_enable) begin
            phase = 0; model_running = 0;
        end else if (!model_running) begin
            phase = 0; model_running = 1;
        end else begin
            phase = (phase + 1) % (2*TBPRD_TEST);
            model_zero = (phase == 0);
        end
        model_load = 0;
        if (!reset_n) begin
            model_shadow = '0; model_active = '0; model_pending = 0;
        end else if (!pwm_enable) begin
            model_pending = 0;
            if (accepted) begin
                model_shadow = {cmp_u_cmd,cmp_v_cmd,cmp_w_cmd};
                model_active = model_shadow;
            end
        end else begin
            if (model_zero && model_pending) begin
                model_active = model_shadow;
                model_pending = 0; model_load = 1;
            end
            if (accepted) begin
                model_shadow = {cmp_u_cmd,cmp_v_cmd,cmp_w_cmd};
                model_pending = 1;
            end
        end
        #1;
        if (reset_n) begin
            monitored_clocks++;
            check({cmp_u_shadow,cmp_v_shadow,cmp_w_shadow} === model_shadow,"shadow scoreboard");
            check({cmp_u_active,cmp_v_active,cmp_w_active} === model_active,"active scoreboard");
            check(shadow_pending === model_pending,"pending scoreboard");
            check(compare_load_event === model_load,"load requires old pending and running ZERO");
            check(cmp_cmd_ready === (!pwm_enable || !model_pending),"ready scoreboard");
            check(int'(tbctr) == ((phase <= TBPRD_TEST) ? phase : 2*TBPRD_TEST-phase),"carrier sequence");
            check(count_up === (phase < TBPRD_TEST),"carrier direction");
            check(carrier_zero === model_zero,"ZERO event alignment");
            check(carrier_peak === (pwm_enable && phase == TBPRD_TEST),"PEAK event alignment");
            check(!(carrier_zero && previous_zero),"ZERO pulse width");
            check(!(carrier_peak && previous_peak),"PEAK pulse width");
            check(!(compare_load_event && previous_load),"load pulse width");
            check(pwm_u === (pwm_enable && expected_pwm(cmp_u_active,tbctr,count_up)),"U phase edge/level");
            check(pwm_v === (pwm_enable && expected_pwm(cmp_v_active,tbctr,count_up)),"V phase edge/level");
            check(pwm_w === (pwm_enable && expected_pwm(cmp_w_active,tbctr,count_up)),"W phase edge/level");
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
    task automatic count_highs_one_cycle(input int u, input int v, input int w);
        int hu, hv, hw, u_up, u_down, v_up, v_down, w_up, w_down;
        hu=0; hv=0; hw=0;
        u_up=0; u_down=0; v_up=0; v_down=0; w_up=0; w_down=0;
        wait_for_zero();
        // Includes opening ZERO, excludes closing ZERO: exactly 16 states.
        for (int i=0;i<2*TBPRD_TEST;i++) begin
            hu+=int'(pwm_u); hv+=int'(pwm_v); hw+=int'(pwm_w);
            if (count_up) begin
                u_up+=int'(pwm_u); v_up+=int'(pwm_v); w_up+=int'(pwm_w);
            end else begin
                u_down+=int'(pwm_u); v_down+=int'(pwm_v); w_down+=int'(pwm_w);
            end
            tick();
        end
        check(carrier_zero,"cycle closes at ZERO");
        check(hu == u && hv == v && hw == w,"full-cycle HIGH counts");
        check(u_up == u_down && v_up == v_down && w_up == w_down,"symmetric ZERO-side halves");
        $display("DUTY COUNTS: U=%0d V=%0d W=%0d /16; symmetric halves",hu,hv,hw);
    endtask
    // Inspect the opening cycle directly; never skip startup via wait_for_zero.
    task automatic check_first_enable_cycle(input int u, input int v, input int w);
        int hu, hv, hw;
        hu=0; hv=0; hw=0;
        pwm_enable=1; tick();
        check(tbctr == 0 && count_up, "startup exposes registered ZERO/UP");
        check(!carrier_zero && !carrier_peak && !compare_load_event,
              "startup has no recurring ZERO/PEAK/load event");
        for (int elapsed=0; elapsed<2*TBPRD_TEST; elapsed++) begin
            check(!carrier_zero, "no returned ZERO before 16 startup intervals");
            check(carrier_peak === (elapsed == TBPRD_TEST), "startup PEAK exactly after 8 intervals");
            hu+=int'(pwm_u); hv+=int'(pwm_v); hw+=int'(pwm_w);
            tick();
        end
        check(carrier_zero && tbctr == 0 && count_up, "first returned ZERO exactly after 16 intervals");
        check(hu == u && hv == v && hw == w, "first-cycle HIGH counts include opening ZERO");
        $display("STARTUP COUNTS: U=%0d V=%0d W=%0d /16",hu,hv,hw);
    endtask
    initial begin
        apply_reset();
        send_cmp_command(0,4,8);
        check({cmp_u_active,cmp_v_active,cmp_w_active} === {4'd0,4'd4,4'd8},"disabled active preload");
        check({cmp_u_shadow,cmp_v_shadow,cmp_w_shadow} === {4'd0,4'd4,4'd8},"disabled shadow preload");
        check({shadow_pending,compare_load_event,pwm_u,pwm_v,pwm_w} === '0,"preload inhibited");
        check_first_enable_cycle(0,8,16);
        repeat (8) tick(); check(carrier_peak === 1'b1,"peak 8 clocks after ZERO");
        repeat (8) tick(); check(carrier_zero === 1'b1,"ZERO 16 clocks after ZERO");
        count_highs_one_cycle(0,8,16);
        send_cmp_command(2,4,6); wait_for_zero(); expect_active(2,4,6);
        count_highs_one_cycle(4,8,12);
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
        $display("PASS: carrier continuity, atomic shadow load, backpressure, ZERO collision");

        // Disable with a pending command: cancel it without silently activating it.
        tick(); send_cmp_command(7,6,5);
        check(shadow_pending,"pending exists before disable");
        pwm_enable=0; tick();
        expect_active(1,3,5); expect_shadow(7,6,5);
        check(!shadow_pending && cmp_cmd_ready,"disable discards stale pending");
        repeat (4) tick();
        send_cmp_command(8,4,0); expect_active(8,4,0); expect_shadow(8,4,0);
        check_first_enable_cycle(16,8,0); count_highs_one_cycle(16,8,0);
        $display("PASS: disable cancellation, retained configuration and coherent re-enable");

        // Reset between edges, with live PWM and a pending command.
        tick(); send_cmp_command(6,2,4);
        check(pwm_u && shadow_pending,"activity before async reset");
        #3; reset_n=0; #2; safe_reset();
        check(!cmp_cmd_ready,"ready LOW during reset");
        pwm_enable=0; tick(); reset_n=1; tick(); safe_reset();
        $display("PASS: asynchronous reset during activity clears pending and all state");

        // Exhaust all representable compare values, including CMP > TBPRD.
        for (int c=0;c<16;c++) begin
            pwm_enable=0; tick(); send_cmp_command(c,15-c,c/2);
            check_first_enable_cycle(2*((c<8)?c:8),2*(((15-c)<8)?(15-c):8),2*(c/2));
            count_highs_one_cycle(2*((c<8)?c:8),2*(((15-c)<8)?(15-c):8),2*(c/2));
        end
        $display("PASS: all 4-bit compare values 0..15, boundaries and HIGH symmetry");
        // Accept at every possible carrier phase; continue driving a second
        // tuple while backpressured, including the eventual loading edge.
        for (int offset=0;offset<16;offset++) begin
            wait_for_zero();
            repeat (offset) tick();
            send_cmp_command(offset,15-offset,offset/2);
            cmp_u_cmd=15; cmp_v_cmd=0; cmp_w_cmd=8;
            cmp_cmd_valid=1;
            while (shadow_pending) tick();
            cmp_cmd_valid=0;
            expect_active(offset,15-offset,offset/2);
        end
        $display("PASS: acceptance at every carrier phase and rejection through load edge");
        if (error_count) $fatal(1,"STEP 6B MOTOR PWM TESTS FAILED: %0d errors",error_count);
        $display("MONITORED CLOCKS: %0d",monitored_clocks);
        $display("ALL STEP 6B MOTOR PWM TESTS PASSED");
        $finish;
    end
    initial begin
        #200000;
        $fatal(1,"Step6B watchdog expired");
    end
endmodule
