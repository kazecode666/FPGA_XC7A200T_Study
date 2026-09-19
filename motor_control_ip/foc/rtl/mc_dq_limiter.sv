`timescale 1ns/1ps
// Stateless circular limiter. Arithmetic finishes by +124; every response is +160.
module mc_dq_limiter (
  input logic clk, reset_n, input_valid,
  output logic input_ready, output_valid,
  input logic signed [39:0] ud_raw, uq_raw,
  input logic signed [24:0] vdc,
  output logic signed [39:0] ud_hi, uq_hi, du_d_next, du_q_next,
  output logic signed [24:0] ud_lim, uq_lim,
  output logic [32:0] scale,
  output logic limited, sat_flag,
  output logic [1:0] error_code
);
  import mc_pi_fxp_pkg::*;
  localparam logic [1:0] OK=2'b00, INVALID_VDC=2'b01,
                         RANGE_ERROR=2'b10, INTERNAL_ERROR=2'b11;
  logic busy, result_done;
  logic [7:0] count;
  logic [1:0] work_error;
  logic signed [39:0] captured_d, captured_q;
  logic [24:0] captured_bus;
  logic signed [79:0] square_d, square_q;
  logic [80:0] norm_sum;
  logic [56:0] bus_product;
  logic [39:0] umax;
  logic [40:0] denom;
  logic [32:0] work_scale;
  logic signed [73:0] scaled_d, scaled_q;
  logic signed [95:0] high_d, high_q, correction_d, correction_q;
  logic signed [95:0] external_d, external_q;
  logic [42:0] sat_product;

  logic sqrt_input_valid, sqrt_ready, sqrt_output_valid;
  logic [39:0] root_floor;
  logic [40:0] root_remainder;
  logic div_input_valid, div_ready, div_output_valid, div_by_zero;
  logic [71:0] quotient;
  logic [40:0] div_remainder;

  assign input_ready=reset_n && !busy;
  // +4 accept -> +44 sqrt response, sampled here at +45.
  assign sqrt_input_valid=busy && count==8'd3 && work_error==OK;
  mc_isqrt_u80 sqrt_engine (
    .clk(clk), .reset_n(reset_n), .input_valid(sqrt_input_valid),
    .input_ready(sqrt_ready), .output_valid(sqrt_output_valid),
    .radicand(norm_sum[79:0]), .root_floor(root_floor), .remainder(root_remainder)
  );
  // +47 accept -> +119 divider response, sampled here at +120.
  assign div_input_valid=busy && count==8'd46 && work_error==OK &&
                         {1'b0,umax}<denom;
  mc_udiv_u72_u41 div_engine (
    .clk(clk), .reset_n(reset_n), .input_valid(div_input_valid),
    .input_ready(div_ready), .output_valid(div_output_valid),
    .numerator({umax[39:0],32'b0}), .denominator(denom),
    .quotient(quotient), .remainder(div_remainder), .div_by_zero(div_by_zero)
  );

  // No asynchronous reset on datapath registers. Busy/error/result_done mask all
  // stale values; registered full-width multiplies precede their consumers.
  always_ff @(posedge clk) begin
    if(reset_n) begin
      if(!busy && input_valid) begin
        captured_d<=ud_raw; captured_q<=uq_raw; captured_bus<=$unsigned(vdc);
      end else if(busy) begin
        case(count)
          8'd0: begin
            square_d<=captured_d*captured_d;
            square_q<=captured_q*captured_q;
            bus_product<=captured_bus*PI_C_UMAX;
          end
          8'd1: begin
            // Explicit U81 sum: both most-negative S40 inputs yield U80 bit79.
            norm_sum<={1'b0,$unsigned(square_d)}+{1'b0,$unsigned(square_q)};
            umax<=bus_product>>21;
          end
          8'd44: begin
            // Extend BEFORE ceil carry and epsilon addition.
            denom<={1'b0,root_floor}+((root_remainder!=0)?41'd1:41'd0)+PI_EPS_RAW;
          end
          8'd45: begin
            if({1'b0,umax}>=denom) work_scale<=PI_ONE_SCALE;
          end
          8'd119: begin
            if({1'b0,umax}<denom) work_scale<={1'b0,quotient[31:0]};
          end
          8'd120: begin
            // Unsigned U33 scale becomes nonnegative signed S34, full S74 result.
            scaled_d<=captured_d*$signed({1'b0,work_scale});
            scaled_q<=captured_q*$signed({1'b0,work_scale});
            sat_product<=43'd1000*{10'b0,work_scale};
          end
          8'd121: begin
            high_d<=pi_round_shift_s96({{22{scaled_d[73]}},scaled_d},32);
            high_q<=pi_round_shift_s96({{22{scaled_q[73]}},scaled_q},32);
          end
          8'd122: begin
            // Back-calculation is F24; only external outputs round to F15.
            correction_d<=$signed({{56{captured_d[39]}},captured_d})-high_d;
            correction_q<=$signed({{56{captured_q[39]}},captured_q})-high_q;
            external_d<=pi_round_shift_s96(high_d,9);
            external_q<=pi_round_shift_s96(high_q,9);
          end
          default: begin end
        endcase
      end
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      busy<=0; count<=0; work_error<=OK; result_done<=0;
      ud_hi<=0; uq_hi<=0; du_d_next<=0; du_q_next<=0;
      ud_lim<=0; uq_lim<=0; scale<=0; limited<=0; sat_flag<=0;
      error_code<=OK; output_valid<=0;
    end else begin
      output_valid<=0;
      if(busy) begin
        if(count==8'd159) begin
          busy<=0; output_valid<=1;
          if(work_error!=OK || !result_done) begin
            error_code<=(work_error!=OK)?work_error:INTERNAL_ERROR;
            ud_hi<=0; uq_hi<=0; du_d_next<=0; du_q_next<=0;
            ud_lim<=0; uq_lim<=0; scale<=0; limited<=0; sat_flag<=0;
          end else begin
            error_code<=OK;
            ud_hi<=high_d[39:0]; uq_hi<=high_q[39:0];
            du_d_next<=correction_d[39:0]; du_q_next<=correction_q[39:0];
            ud_lim<=external_d[24:0]; uq_lim<=external_q[24:0];
            scale<=work_scale; limited<=work_scale<PI_ONE_SCALE;
            sat_flag<=sat_product<(43'd999*43'd4294967296);
          end
        end else begin
          count<=count+8'd1;
          if(work_error==OK) begin
            case(count)
              8'd2: if(norm_sum[80]) work_error<=INTERNAL_ERROR;
              8'd3: if(!sqrt_ready) work_error<=INTERNAL_ERROR;
              8'd44: if(!sqrt_output_valid) work_error<=INTERNAL_ERROR;
              8'd45: if(denom==0) work_error<=INTERNAL_ERROR;
              8'd46: if(div_input_valid && !div_ready) work_error<=INTERNAL_ERROR;
              8'd119: begin
                if({1'b0,umax}<denom && (!div_output_valid || div_by_zero ||
                   quotient[71:32]!=0 || div_remainder>=denom))
                  work_error<=INTERNAL_ERROR;
              end
              8'd120: if(work_scale>PI_ONE_SCALE) work_error<=INTERNAL_ERROR;
              8'd123: begin
                if(!pi_fits_s40(high_d) || !pi_fits_s40(high_q) ||
                   !pi_fits_s40(correction_d) || !pi_fits_s40(correction_q) ||
                   !pi_fits_s25(external_d) || !pi_fits_s25(external_q))
                  work_error<=RANGE_ERROR;
                else result_done<=1;
              end
              default: begin end
            endcase
          end
        end
      end else if(input_valid) begin
        busy<=1; count<=0; result_done<=0;
        work_error<=($signed(vdc)<=0)?INVALID_VDC:OK;
      end
    end
  end
endmodule
