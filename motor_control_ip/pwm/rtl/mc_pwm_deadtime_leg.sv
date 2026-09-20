`timescale 1ns/1ps
// Registered logical gate requests; external driver polarity is not defined here.
module mc_pwm_deadtime_leg #(parameter int DEADTIME_CYCLES=25) (
  input logic clk,reset_n,gate_enable,pwm_req,
  output logic gate_h,gate_l
);
  localparam int COUNT_WIDTH=($clog2(DEADTIME_CYCLES+1)<1)?1:$clog2(DEADTIME_CYCLES+1);
  // Intentional unresolved instance only for unsupported parameter values:
  // reject at elaboration, not after a simulation starts.
  generate if(DEADTIME_CYCLES<1 || DEADTIME_CYCLES>2500) begin : invalid_deadtime
    ERROR_DEADTIME_CYCLES_MUST_BE_1_TO_2500 invalid_parameter();
  end endgenerate
  logic target,target_valid;
  logic [COUNT_WIDTH-1:0] remaining;
  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      target<=0;target_valid<=0;remaining<=0;gate_h<=0;gate_l<=0;
    end else if(!gate_enable) begin
      target<=0;target_valid<=0;remaining<=0;gate_h<=0;gate_l<=0;
    end else if(!target_valid || pwm_req!=target) begin
      target<=pwm_req;target_valid<=1;remaining<=COUNT_WIDTH'(DEADTIME_CYCLES);
      gate_h<=0;gate_l<=0;
    end else if(remaining!=0) begin
      remaining<=remaining-1'b1;
      if(remaining==1) begin gate_h<=target;gate_l<=!target;end
    end
  end
endmodule
