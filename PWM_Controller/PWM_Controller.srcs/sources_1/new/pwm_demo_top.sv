`timescale 1ns / 1ps

// BX72: 50 MHz Y18, active-low KEY2 V17, active-high LED1 AA18.
// Source evidence: coordination/reports/step5a_codex_report.md.
module pwm_demo_top #(
    parameter logic [31:0] PERIOD_CYCLES = 32'd50_000_000,
    parameter logic [31:0] COMPARE_CYCLES = 32'd25_000_000
)(
    input  wire clk,
    input  wire key2_n,
    output wire led1
);
    // INIT=0 also provides deterministic startup if KEY2 is not pressed
    // during FPGA configuration. KEY2 asynchronously asserts both stages;
    // release reaches the system only after two rising clock edges.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] reset_release = 2'b00;
    always_ff @(posedge clk or negedge key2_n)
        if (!key2_n) reset_release <= 2'b00;
        else         reset_release <= {reset_release[0], 1'b1};

    wire reset_n = reset_release[1];
    logic configured = 1'b0;
    wire config_en = reset_n && !configured;
    always_ff @(posedge clk or negedge reset_n)
        if (!reset_n) configured <= 1'b0;
        else          configured <= 1'b1;

    wire pwm_core_out;
    pwm_controller u_pwm (
        .clk(clk), .reset_n(reset_n),
        .period_set(PERIOD_CYCLES),
        .compare_value_set(COMPARE_CYCLES),
        .config_en(config_en), .pwm_out(pwm_core_out)
    );

    // D7 cathode is grounded (schematic p7); HIGH means visibly ON.
    assign led1 = pwm_core_out;
endmodule
