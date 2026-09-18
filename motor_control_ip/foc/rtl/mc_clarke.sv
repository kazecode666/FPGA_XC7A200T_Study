module mc_clarke (
  input  logic                     clk,
  input  logic                     reset_n,
  input  logic                     input_valid,
  input  logic signed [23:0]       ia,
  input  logic signed [23:0]       ib,
  input  logic signed [23:0]       ic,
  output logic                     output_valid,
  output logic signed [24:0]       i_alpha,
  output logic signed [24:0]       i_beta
);
  import mc_fxp_pkg::*;

  logic signed [24:0] sum_bc;
  logic signed [24:0] alpha_pre;
  logic signed [24:0] beta_pre;
  (* use_dsp = "yes" *) logic signed [42:0] alpha_product;
  (* use_dsp = "yes" *) logic signed [42:0] beta_product;
  logic valid_pre;
  logic valid_product;

  assign sum_bc = $signed({ib[23], ib}) + $signed({ic[23], ic});

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      alpha_pre    <= '0;
      beta_pre     <= '0;
      alpha_product <= '0;
      beta_product  <= '0;
      i_alpha      <= '0;
      i_beta       <= '0;
      valid_pre    <= 1'b0;
      valid_product <= 1'b0;
      output_valid <= 1'b0;
    end else begin
      valid_pre     <= input_valid;
      valid_product <= valid_pre;
      output_valid  <= valid_product;

      if (input_valid) begin
        alpha_pre <= $signed({ia[23], ia})
                   - fxp_half_away_s25(sum_bc);
        beta_pre  <= $signed({ib[23], ib}) - $signed({ic[23], ic});
      end

      if (valid_pre) begin
        alpha_product <= alpha_pre * C_TWO_THIRDS;
        beta_product  <= beta_pre * C_INV_SQRT3;
      end

      if (valid_product) begin
        i_alpha <= fxp_round_sat_f31_to_s25({alpha_product[42], alpha_product});
        i_beta  <= fxp_round_sat_f31_to_s25({beta_product[42], beta_product});
      end
    end
  end
endmodule
