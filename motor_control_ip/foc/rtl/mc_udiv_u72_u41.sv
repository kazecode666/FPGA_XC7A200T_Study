`timescale 1ns/1ps
// One restoring-division bit per busy clock. Zero divisor uses the same slot.
module mc_udiv_u72_u41 (
  input logic clk, reset_n, input_valid,
  output logic input_ready, output_valid,
  input logic [71:0] numerator,
  input logic [40:0] denominator,
  output logic [71:0] quotient,
  output logic [40:0] remainder,
  output logic div_by_zero
);
  logic busy, zero_divisor;
  logic [6:0] count;
  logic [71:0] work_input, work_result;
  logic [40:0] work_rem, divisor;
  logic [41:0] shifted_rem, next_rem;
  logic [71:0] next_result;
  assign input_ready=reset_n && !busy;
  always_comb begin
    shifted_rem={work_rem,work_input[71]};
    next_rem=shifted_rem;
    next_result={work_result[70:0],1'b0};
    if(!zero_divisor && shifted_rem>={1'b0,divisor}) begin
      next_rem=shifted_rem-{1'b0,divisor};
      next_result={work_result[70:0],1'b1};
    end
  end
  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      busy<=0; count<=0; work_input<=0; work_result<=0; work_rem<=0;
      divisor<=0; zero_divisor<=0; quotient<=0; remainder<=0;
      div_by_zero<=0; output_valid<=0;
    end else begin
      output_valid<=0;
      if(busy) begin
        // Do not iterate zero-divisor data; only the fixed slot counter runs.
        if(!zero_divisor) begin
          work_input<=work_input << 1;
          work_result<=next_result; work_rem<=next_rem[40:0];
        end
        if(count==7'd71) begin
          busy<=0; output_valid<=1; div_by_zero<=zero_divisor;
          quotient<=zero_divisor ? 72'd0 : next_result;
          remainder<=zero_divisor ? 41'd0 : next_rem[40:0];
        end else count<=count+7'd1;
      end else if(input_valid) begin
        busy<=1; count<=0; work_input<=numerator; divisor<=denominator;
        zero_divisor<=(denominator==0); work_result<=0; work_rem<=0;
      end
    end
  end
endmodule
