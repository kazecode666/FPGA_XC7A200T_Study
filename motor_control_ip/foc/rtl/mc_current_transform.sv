// Coherent transaction pipeline: acceptance N -> output N+5, throughput 1/clock.
module mc_current_transform (
  input logic clk, reset_n, input_valid,
  input logic signed [23:0] ia, ib, ic,
  input logic [15:0] theta_e,
  output logic output_valid,
  output logic signed [24:0] i_alpha_dbg, i_beta_dbg,
  output logic signed [17:0] sin_theta_dbg, cos_theta_dbg,
  output logic signed [24:0] id, iq
);
  logic clarke_valid, sincos_valid, aligned_valid, park_valid;
  logic signed [24:0] alpha, beta;
  logic signed [17:0] sin_raw, cos_raw, sin_aligned, cos_aligned;
  logic [2:0] debug_valid;
  logic signed [24:0] alpha_delay[0:2], beta_delay[0:2];
  logic signed [17:0] sin_delay[0:2], cos_delay[0:2];

  mc_clarke clarke(.clk(clk), .reset_n(reset_n), .input_valid(input_valid),
    .ia(ia), .ib(ib), .ic(ic), .output_valid(clarke_valid), .i_alpha(alpha), .i_beta(beta));
  mc_sincos_lut sincos(.clk(clk), .reset_n(reset_n), .input_valid(input_valid),
    .theta_e(theta_e), .output_valid(sincos_valid), .sin_theta(sin_raw), .cos_theta(cos_raw));
  // Clarke is ready at N+2; sincos at N+1 gets one explicit alignment stage.
  assign park_valid=clarke_valid & aligned_valid;
  mc_park park(.clk(clk), .reset_n(reset_n), .input_valid(park_valid),
    .i_alpha(alpha), .i_beta(beta), .sin_theta(sin_aligned), .cos_theta(cos_aligned),
    .output_valid(output_valid), .id(id), .iq(iq));
  assign i_alpha_dbg=alpha_delay[2];
  assign i_beta_dbg=beta_delay[2];
  assign sin_theta_dbg=sin_delay[2];
  assign cos_theta_dbg=cos_delay[2];

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      aligned_valid<=0; sin_aligned<='0; cos_aligned<='0; debug_valid<='0;
      for (integer n=0;n<3;n=n+1) begin
        alpha_delay[n]<='0; beta_delay[n]<='0; sin_delay[n]<='0; cos_delay[n]<='0;
      end
    end else begin
      aligned_valid<=sincos_valid;
      if (sincos_valid) begin sin_aligned<=sin_raw; cos_aligned<=cos_raw; end
      // Park samples aligned operands at N+3 and quantizes at N+5. Carry the
      // entire debug tuple through those same three valid-gated stages.
      debug_valid<={debug_valid[1:0],park_valid};
      if (park_valid) begin
        alpha_delay[0]<=alpha; beta_delay[0]<=beta;
        sin_delay[0]<=sin_aligned; cos_delay[0]<=cos_aligned;
      end
      for (integer n=1;n<3;n=n+1) begin
        if (debug_valid[n-1]) begin
          alpha_delay[n]<=alpha_delay[n-1]; beta_delay[n]<=beta_delay[n-1];
          sin_delay[n]<=sin_delay[n-1]; cos_delay[n]<=cos_delay[n-1];
        end
      end
    end
  end
endmodule
