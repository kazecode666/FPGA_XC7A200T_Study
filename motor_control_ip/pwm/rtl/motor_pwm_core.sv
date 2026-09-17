// Portable shared center-aligned carrier; see ../README.md for edge semantics.
module motor_pwm_core #(
    parameter int unsigned TBPRD = 2500,
    parameter int unsigned COUNTER_WIDTH = $clog2(TBPRD + 1)
) (
    input logic clk, reset_n, pwm_enable,
    input logic [COUNTER_WIDTH-1:0] cmp_u_cmd, cmp_v_cmd, cmp_w_cmd,
    input logic cmp_cmd_valid,
    output logic cmp_cmd_ready,
    output logic pwm_u, pwm_v, pwm_w,
    output logic [COUNTER_WIDTH-1:0] tbctr,
    output logic count_up, carrier_zero, carrier_peak,
    output logic [COUNTER_WIDTH-1:0] cmp_u_shadow, cmp_v_shadow, cmp_w_shadow,
    output logic [COUNTER_WIDTH-1:0] cmp_u_active, cmp_v_active, cmp_w_active,
    output logic shadow_pending, compare_load_event
);
    localparam logic [COUNTER_WIDTH-1:0] PERIOD = COUNTER_WIDTH'(TBPRD);
    logic [COUNTER_WIDTH-1:0] next_ctr;
    logic next_up, enter_zero, enter_peak;
    logic load_shadow;

    // Eligibility uses OLD pending state: never bypass a just-accepted command.
    assign load_shadow = pwm_enable && enter_zero && shadow_pending;

    assign cmp_cmd_ready = reset_n && (!pwm_enable || !shadow_pending);

    // Endpoint events describe the state entered on this edge, not the old state.
    always_comb begin
        next_ctr = '0;
        next_up = 1'b1;
        enter_zero = 1'b0;
        enter_peak = 1'b0;
        if (pwm_enable) begin
            if (count_up) begin
                next_ctr = tbctr + 1'b1;
                enter_peak = (tbctr == PERIOD - 1'b1);
                next_up = !enter_peak;
            end else begin
                next_ctr = tbctr - 1'b1;
                enter_zero = (tbctr == 1);
                next_up = enter_zero;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tbctr <= '0; count_up <= 1'b1;
            carrier_zero <= 1'b0; carrier_peak <= 1'b0;
            cmp_u_shadow <= '0; cmp_v_shadow <= '0; cmp_w_shadow <= '0;
            cmp_u_active <= '0; cmp_v_active <= '0; cmp_w_active <= '0;
            shadow_pending <= 1'b0; compare_load_event <= 1'b0;
            pwm_u <= 1'b0; pwm_v <= 1'b0; pwm_w <= 1'b0;
        end else begin
            tbctr <= next_ctr; count_up <= next_up;
            carrier_zero <= enter_zero; carrier_peak <= enter_peak;
            compare_load_event <= 1'b0;
            pwm_u <= 1'b0; pwm_v <= 1'b0; pwm_w <= 1'b0;
            if (!pwm_enable) begin
                shadow_pending <= 1'b0;
                if (cmp_cmd_valid && cmp_cmd_ready) begin
                    cmp_u_shadow <= cmp_u_cmd; cmp_v_shadow <= cmp_v_cmd; cmp_w_shadow <= cmp_w_cmd;
                    cmp_u_active <= cmp_u_cmd; cmp_v_active <= cmp_v_cmd; cmp_w_active <= cmp_w_cmd;
                end
            end else begin
                if (load_shadow) begin
                    cmp_u_active <= cmp_u_shadow; cmp_v_active <= cmp_v_shadow; cmp_w_active <= cmp_w_shadow;
                    shadow_pending <= 1'b0;
                    compare_load_event <= 1'b1;
                end
                if (cmp_cmd_valid && cmp_cmd_ready) begin
                    cmp_u_shadow <= cmp_u_cmd; cmp_v_shadow <= cmp_v_cmd; cmp_w_shadow <= cmp_w_cmd;
                    shadow_pending <= 1'b1;
                end
            end
        end
    end
endmodule
