// Identical thin CE/valid adapter for every compared implementation.
// No numerical logic, extra data pipeline, or debug pruning.
`timescale 1ns/1ps
module speed_pi_compare (
  input wire clk, init_reset, clk_enable,
  input wire signed [31:0] v_ref_mmps, v_meas_mmps,
  input wire enable, pi_reset, sample_tick, angle_init, test_mode,
  output wire ce_out, result_valid,
  output wire signed [24:0] iq_ref_A,
  output wire signed [41:0] iq_unlimited_A,
  output wire signed [31:0] integrator_A,
  output wire saturation_active,
  output wire signed [31:0] integrator_next_A,
  output wire signed [39:0] previous_excess_A, excess_next_A,
  output wire hard_reset, int_reset,
  output wire signed [41:0] iq_limited_A,
  output wire signed [32:0] error_mmps,
  output wire signed [39:0] P_A, KiTs_A, AW_A
);
  // Model trigger memory starts high; first stage of the data carrier starts low.
  logic source_previous=1;
  logic [1:0] valid_pipe=0;
  always_ff @(posedge clk) begin
    if (init_reset) begin source_previous<=1; valid_pipe<=0; end
    else if (clk_enable) begin
      source_previous<=sample_tick;
      valid_pipe<={valid_pipe[0],sample_tick && !source_previous};
    end
  end
  assign result_valid = clk_enable && valid_pipe[1];
`ifdef HAND_SV
  speed_pi_sv core (
`else
  HDLCore core (
`endif
    .clk(clk),.init_reset(init_reset),.clk_enable(clk_enable),
    .v_ref_mmps(v_ref_mmps),.v_meas_mmps(v_meas_mmps),.enable(enable),
    .pi_reset(pi_reset),.sample_tick(sample_tick),.angle_init(angle_init),.test_mode(test_mode),
    .ce_out(ce_out),.iq_ref_A(iq_ref_A),.iq_unlimited_A(iq_unlimited_A),
    .integrator_A(integrator_A),.saturation_active(saturation_active),
    .integrator_next_A(integrator_next_A),.previous_excess_A(previous_excess_A),
    .excess_next_A(excess_next_A),.hard_reset(hard_reset),.int_reset(int_reset),
    .iq_limited_A(iq_limited_A),.error_mmps(error_mmps),.P_A(P_A),.KiTs_A(KiTs_A),.AW_A(AW_A)
  );
endmodule
