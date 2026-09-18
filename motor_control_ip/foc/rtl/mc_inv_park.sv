// Three registered stages: input accepted on N produces output on N+2.
module mc_inv_park (
  input logic clk, reset_n, input_valid,
  input logic signed [24:0] vd, vq,
  input logic signed [17:0] sin_theta, cos_theta,
  output logic output_valid,
  output logic signed [24:0] v_alpha, v_beta
);
  import mc_fxp_pkg::*;
  (* use_dsp = "yes" *) logic signed [42:0] p_ac, p_bs, p_as, p_bc;
  logic signed [43:0] acc_x, acc_y;
  logic valid_product, valid_acc;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      valid_product <= 0; valid_acc <= 0; output_valid <= 0;
      p_ac <= '0; p_bs <= '0; p_as <= '0; p_bc <= '0;
      acc_x <= '0; acc_y <= '0; v_alpha <= '0; v_beta <= '0;
    end else begin
      valid_product <= input_valid;
      valid_acc <= valid_product;
      output_valid <= valid_acc;
      if (input_valid) begin
        // Signed native 25x18 operands retain full 43-bit F31 products.
        p_ac <= vd * cos_theta;
        p_bs <= vq * sin_theta;
        p_as <= vd * sin_theta;
        p_bc <= vq * cos_theta;
      end
      if (valid_product) begin
        // Extend BEFORE addition/subtraction, preserving the guard bit.
        acc_x <= $signed({p_ac[42], p_ac}) - $signed({p_bs[42], p_bs});
        acc_y <= $signed({p_as[42], p_as}) + $signed({p_bc[42], p_bc});
      end
      if (valid_acc) begin
        v_alpha <= fxp_round_sat_f31_to_s25(acc_x);
        v_beta <= fxp_round_sat_f31_to_s25(acc_y);
      end
    end
  end
endmodule
