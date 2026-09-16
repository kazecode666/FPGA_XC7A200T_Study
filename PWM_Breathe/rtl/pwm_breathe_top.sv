`timescale 1ns / 1ps

// Step 5B: independent demo; the PWM core and Step 5A top are unchanged.
module pwm_breathe_top #(
    parameter int unsigned PWM_PERIOD_CYCLES = 50_000,
    parameter int unsigned UPDATE_PWM_PERIODS = 10,
    parameter int unsigned COMPARE_STEP = 500
)(
    input  wire clk,
    input  wire key2_n,
    output wire led1
);
    localparam logic [63:0] UPDATE_INTERVAL_CYCLES =
        64'd1 * PWM_PERIOD_CYCLES * UPDATE_PWM_PERIODS;
    localparam int INTERVAL_WIDTH = (UPDATE_INTERVAL_CYCLES <= 1)
        ? 1 : $clog2(UPDATE_INTERVAL_CYCLES);

    // INIT=0 guarantees reset at power-on even when KEY2 is already released.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] reset_release = 2'b00;
    always_ff @(posedge clk or negedge key2_n)
        if (!key2_n) reset_release <= 2'b00;
        else         reset_release <= {reset_release[0], 1'b1};
    wire reset_n = reset_release[1];

    logic started = 1'b0;
    logic [INTERVAL_WIDTH-1:0] interval_count = '0;
    logic [31:0] compare_active = PWM_PERIOD_CYCLES;
    logic brightening = 1'b1; // Decreasing compare means increasing HIGH duty.
    wire update_due = started &&
        (interval_count == INTERVAL_WIDTH'(UPDATE_INTERVAL_CYCLES - 1));
    wire config_en = reset_n && (!started || update_due);
    logic [31:0] compare_command;

    // Present the next command BEFORE its sampling edge. Saturating arithmetic
    // also supports positive steps that do not divide the carrier period.
    always_comb begin
        compare_command = compare_active;
        if (!started)
            compare_command = PWM_PERIOD_CYCLES;
        else if (update_due) begin
            if (brightening)
                compare_command = (compare_active <= COMPARE_STEP)
                    ? 32'd0 : compare_active - COMPARE_STEP;
            else
                compare_command = (COMPARE_STEP >= PWM_PERIOD_CYCLES - compare_active)
                    ? PWM_PERIOD_CYCLES : compare_active + COMPARE_STEP;
        end
    end

    // At every configuration sampling edge the core and scheduler both restart
    // at zero. Next config is sampled exactly N * UPDATE_PWM_PERIODS clocks
    // later, where the core would naturally wrap from N-1 to zero anyway.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            started        <= 1'b0;
            interval_count <= '0;
            compare_active <= PWM_PERIOD_CYCLES;
            brightening    <= 1'b1;
        end else if (config_en) begin
            started        <= 1'b1;
            interval_count <= '0;
            compare_active <= compare_command;
            if (compare_command == 0)
                brightening <= 1'b0;
            else if (compare_command == PWM_PERIOD_CYCLES)
                brightening <= 1'b1;
        end else begin
            interval_count <= interval_count + 1'b1;
        end
    end

    wire pwm_core_out;
    pwm_controller u_pwm (
        .clk(clk), .reset_n(reset_n),
        .period_set(PWM_PERIOD_CYCLES),
        .compare_value_set(compare_command), .config_en(config_en),
        .pwm_out(pwm_core_out)
    );
    assign led1 = pwm_core_out; // AA18/D7: HIGH lights LED1.

    // synthesis translate_off
    initial begin
        if (PWM_PERIOD_CYCLES == 0 || UPDATE_PWM_PERIODS == 0 ||
            UPDATE_INTERVAL_CYCLES < 2 || COMPARE_STEP == 0 ||
            COMPARE_STEP > PWM_PERIOD_CYCLES)
            $fatal(1, "Invalid breathing parameters: require N>0, periods>0, interval>=2, 0<step<=N");
    end
    // synthesis translate_on
endmodule
