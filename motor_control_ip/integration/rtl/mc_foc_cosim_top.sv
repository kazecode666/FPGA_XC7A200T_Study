`timescale 1ns/1ps
// Stable monitor boundary. All control math and PWM timing remain in 6D.
module mc_foc_cosim_top #(parameter int PI_PROFILE=0) (
  input logic clk,reset_n,run_enable,
  input logic signed [23:0] ia,ib,ic,
  input logic [15:0] theta_e,
  input logic signed [31:0] we,
  input logic signed [24:0] id_ref,iq_ref,vdc,
  input logic pi_reset,uq_zero_en,
  output logic [11:0] cmp_u_active,cmp_v_active,cmp_w_active,
  output logic [31:0] accepted_sample_id,active_command_id,
  output logic active_valid,needs_reset,
  output logic [2:0] fault_code
);
  logic sample_request_i,sample_ready_i,pwm_command_loaded_i;
  logic pwm_u_i,pwm_v_i,pwm_w_i,active_seen;
  wire sample_valid_i=sample_request_i;
  wire sample_accept_i=sample_request_i && sample_ready_i;
  assign active_valid=active_seen && run_enable && !needs_reset;
  mc_foc_pwm_top #(.PI_PROFILE(PI_PROFILE)) control (
    .clk(clk),.reset_n(reset_n),.run_enable(run_enable),.sample_valid(sample_valid_i),
    .ia(ia),.ib(ib),.ic(ic),.theta_e(theta_e),.we(we),.id_ref(id_ref),.iq_ref(iq_ref),.vdc(vdc),
    .pi_reset(pi_reset),.uq_zero_en(uq_zero_en),
    .sample_request(sample_request_i),.sample_ready(sample_ready_i),
    .pwm_u(pwm_u_i),.pwm_v(pwm_v_i),.pwm_w(pwm_w_i),
    .needs_reset(needs_reset),.fault_code(fault_code),.pwm_command_loaded(pwm_command_loaded_i),
    .cmp_u_active_mon(cmp_u_active),.cmp_v_active_mon(cmp_v_active),.cmp_w_active_mon(cmp_w_active));
  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      accepted_sample_id<=0; active_command_id<=0; active_seen<=0;
    end else begin
      if(sample_accept_i) accepted_sample_id<=accepted_sample_id+1'b1;
      if(pwm_command_loaded_i) begin
        active_command_id<=active_command_id+1'b1; active_seen<=1;
      end
      if(!run_enable || needs_reset) active_seen<=0;
    end
  end
endmodule
