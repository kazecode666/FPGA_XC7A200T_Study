// Three registered stages: input accepted on N produces output on N+2.
module mc_park (
  input logic clk, reset_n, input_valid,
  input logic signed [24:0] i_alpha, i_beta,
  input logic signed [17:0] sin_theta, cos_theta,
  output logic output_valid,
  output logic signed [24:0] id, iq
);
  import mc_fxp_pkg::*;
  (* use_dsp = "yes" *) logic signed [42:0] p_ac, p_bs, p_as, p_bc;
  logic signed [43:0] acc_x, acc_y;
  logic valid_product, valid_acc;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      valid_product <= 0; valid_acc <= 0; output_valid <= 0;
      p_ac <= '0; p_bs <= '0; p_as <= '0; p_bc <= '0;
      acc_x <= '0; acc_y <= '0; id <= '0; iq <= '0;
    end else begin
      valid_product <= input_valid;
      valid_acc <= valid_product;
      output_valid <= valid_acc;
      if (input_valid) begin
        // Signed native 25x18 operands retain full 43-bit F31 products.
        p_ac <= i_alpha * cos_theta;
        p_bs <= i_beta * sin_theta;
        p_as <= i_alpha * sin_theta;
        p_bc <= i_beta * cos_theta;
      end
      if (valid_product) begin
        // Extend BEFORE addition/subtraction, preserving the guard bit.
        acc_x <= $signed({p_ac[42], p_ac}) + $signed({p_bs[42], p_bs});
        acc_y <= $signed({p_bc[42], p_bc}) - $signed({p_as[42], p_as});
      end
      if (valid_acc) begin
        id <= fxp_round_sat_f31_to_s25(acc_x);
        iq <= fxp_round_sat_f31_to_s25(acc_y);
      end
    end
  end
endmodule
