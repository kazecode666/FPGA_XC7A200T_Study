`timescale 1ns/1ps
// One radix-4 digit per busy clock; acceptance itself performs no iteration.
module mc_isqrt_u80 (
  input logic clk, reset_n, input_valid,
  output logic input_ready, output_valid,
  input logic [79:0] radicand,
  output logic [39:0] root_floor,
  output logic [40:0] remainder
);
  logic busy;
  logic [5:0] count;
  logic [79:0] work_input;
  logic [39:0] work_result;
  logic [43:0] work_rem;
  logic [43:0] shifted_rem, trial, next_rem;
  logic [40:0] grown_root;
  assign input_ready=reset_n && !busy;
  always_comb begin
    shifted_rem=(work_rem << 2) | {42'b0,work_input[79:78]};
    trial={2'b0,work_result,2'b01};
    next_rem=shifted_rem;
    grown_root={work_result,1'b0};
    if(shifted_rem>=trial) begin
      next_rem=shifted_rem-trial;
      grown_root={work_result,1'b1};
    end
  end
  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      busy<=0; count<=0; work_input<=0; work_result<=0; work_rem<=0;
      root_floor<=0; remainder<=0; output_valid<=0;
    end else begin
      output_valid<=0;
      if(busy) begin
        work_input<=work_input << 2;
        work_result<=grown_root[39:0]; work_rem<=next_rem;
        if(count==6'd39) begin
          busy<=0; root_floor<=grown_root[39:0]; remainder<=next_rem[40:0];
          output_valid<=1;
        end else count<=count+6'd1;
      end else if(input_valid) begin
        busy<=1; count<=0; work_input<=radicand; work_result<=0; work_rem<=0;
      end
    end
  end
endmodule
