`timescale 1ns/1ps
// Explicit polarity boundary: raw C4 modulation -> upper-switch logical HIGH.
module mc_duty_to_cmp (
  input logic clk,reset_n,flush,input_valid,
  output logic input_ready,
  input logic signed [25:0] foc_duty_u,foc_duty_v,foc_duty_w,
  output logic [11:0] cmp_u_cmd,cmp_v_cmd,cmp_w_cmd,
  output logic cmp_cmd_valid,
  input logic cmp_cmd_ready
);
  typedef enum logic [1:0] {IDLE,MULTIPLY,ROUND,HOLD} state_t;
  state_t state;
  logic [24:0] high_u,high_v,high_w;
  logic [36:0] product_u,product_v,product_w;
  logic [37:0] rounded_u,rounded_v,rounded_w;
  function automatic logic [24:0] high_raw(input logic signed [25:0] raw);
    logic signed [26:0] difference;
    begin
      difference=27'sd16777216-$signed({raw[25],raw});
      if(difference<0) high_raw=0;
      else if(difference>27'sd16777216) high_raw=25'd16777216;
      else high_raw=difference[24:0];
    end
  endfunction
  assign input_ready=reset_n && !flush && state==IDLE;
  assign rounded_u={1'b0,product_u}+38'd8388608;
  assign rounded_v={1'b0,product_v}+38'd8388608;
  assign rounded_w={1'b0,product_w}+38'd8388608;
  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      state<=IDLE;cmp_cmd_valid<=0;
      high_u<=0;high_v<=0;high_w<=0;product_u<=0;product_v<=0;product_w<=0;
      cmp_u_cmd<=0;cmp_v_cmd<=0;cmp_w_cmd<=0;
    end else if(flush) begin state<=IDLE;cmp_cmd_valid<=0;end
    else case(state)
      IDLE: if(input_valid && input_ready) begin
        high_u<=high_raw(foc_duty_u);high_v<=high_raw(foc_duty_v);high_w<=high_raw(foc_duty_w);state<=MULTIPLY;
      end
      MULTIPLY: begin
        product_u<=37'(high_u)*37'd2500;product_v<=37'(high_v)*37'd2500;product_w<=37'(high_w)*37'd2500;
        state<=ROUND;
      end
      ROUND: begin
        // Clamp proved high<=ONE; retain a final bound check before U12 narrowing.
        cmp_u_cmd<=rounded_u[37:24]>14'd2500 ? 12'd2500 : rounded_u[35:24];
        cmp_v_cmd<=rounded_v[37:24]>14'd2500 ? 12'd2500 : rounded_v[35:24];
        cmp_w_cmd<=rounded_w[37:24]>14'd2500 ? 12'd2500 : rounded_w[35:24];
        cmp_cmd_valid<=1;state<=HOLD;
      end
      HOLD: if(cmp_cmd_ready) begin cmp_cmd_valid<=0;state<=IDLE;end
      default: begin state<=IDLE;cmp_cmd_valid<=0;end
    endcase
  end
endmodule
