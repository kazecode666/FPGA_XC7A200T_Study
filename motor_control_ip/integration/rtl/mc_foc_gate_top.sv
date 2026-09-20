`timescale 1ns/1ps
module mc_foc_gate_top #(parameter int PI_PROFILE=0,DEADTIME_CYCLES=25) (
  input logic clk,reset_n,run_enable,sample_valid,trip_req,
  input logic signed [23:0] ia,ib,ic,
  input logic [15:0] theta_e,
  input logic signed [31:0] we,
  input logic signed [24:0] id_ref,iq_ref,vdc,
  input logic pi_reset,uq_zero_en,
  output logic sample_request,sample_ready,
  output logic gate_uh,gate_ul,gate_vh,gate_vl,gate_wh,gate_wl,
  output logic needs_reset,trip_latched,
  output logic [2:0] fault_code
);
  logic control_run,control_needs_reset,pwm_command_loaded,armed,gate_enable;
  logic pwm_u,pwm_v,pwm_w;
  assign control_run=run_enable && !trip_req && !trip_latched;
  assign needs_reset=control_needs_reset || trip_latched;
  // This is the input to registered legs, never a combinational gate output.
  // Include trip_req itself so the sampling edge shuts down, not one edge later.
  assign gate_enable=reset_n && run_enable && armed && !trip_req && !trip_latched && !control_needs_reset;
  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin trip_latched<=0;armed<=0;end
    else begin
      if(trip_req)trip_latched<=1;
      if(!run_enable || trip_req || trip_latched || control_needs_reset)armed<=0;
      else if(pwm_command_loaded)armed<=1;
    end
  end
  mc_foc_pwm_top #(.PI_PROFILE(PI_PROFILE)) control(
    .clk(clk),.reset_n(reset_n),.run_enable(control_run),.sample_valid(sample_valid),
    .ia(ia),.ib(ib),.ic(ic),.theta_e(theta_e),.we(we),.id_ref(id_ref),.iq_ref(iq_ref),.vdc(vdc),
    .pi_reset(pi_reset),.uq_zero_en(uq_zero_en),.sample_request(sample_request),.sample_ready(sample_ready),
    .pwm_u(pwm_u),.pwm_v(pwm_v),.pwm_w(pwm_w),.needs_reset(control_needs_reset),
    .fault_code(fault_code),.pwm_command_loaded(pwm_command_loaded));
  mc_pwm_deadtime_leg #(.DEADTIME_CYCLES(DEADTIME_CYCLES)) leg_u(
    .clk(clk),.reset_n(reset_n),.gate_enable(gate_enable),.pwm_req(pwm_u),.gate_h(gate_uh),.gate_l(gate_ul));
  mc_pwm_deadtime_leg #(.DEADTIME_CYCLES(DEADTIME_CYCLES)) leg_v(
    .clk(clk),.reset_n(reset_n),.gate_enable(gate_enable),.pwm_req(pwm_v),.gate_h(gate_vh),.gate_l(gate_vl));
  mc_pwm_deadtime_leg #(.DEADTIME_CYCLES(DEADTIME_CYCLES)) leg_w(
    .clk(clk),.reset_n(reset_n),.gate_enable(gate_enable),.pwm_req(pwm_w),.gate_h(gate_wh),.gate_l(gate_wl));
endmodule
