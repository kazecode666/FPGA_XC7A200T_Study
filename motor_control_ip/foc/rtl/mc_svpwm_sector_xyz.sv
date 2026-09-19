`timescale 1ns/1ps

// Pure combinational Sector/XYZ stage. A transaction owner captures the S25
// inputs; these outputs settle from that captured pair without local state.
module mc_svpwm_sector_xyz (
  input  logic signed [24:0] v_alpha,
  input  logic signed [24:0] v_beta,
  output logic signed [24:0] cmp0,
  output logic signed [35:0] cmp1,
  output logic signed [35:0] cmp2,
  output logic b0,
  output logic b1,
  output logic b2,
  output logic [2:0] sector,
  output logic signed [39:0] x_num,
  output logic signed [39:0] y_num,
  output logic signed [39:0] z_num,
  output logic signed [39:0] a_num,
  output logic signed [39:0] b_num,
  output logic xyz_range_ok
);
  import mc_svpwm_pkg::*;

  logic signed [35:0] alpha_cmp_w;
  logic signed [35:0] beta_cmp_w;
  logic signed [35:0] cmp1_w;
  logic signed [35:0] cmp2_w;
  logic signed [40:0] alpha_xyz_w;
  logic signed [40:0] beta_xyz_w;
  logic signed [40:0] x_w;
  logic signed [40:0] y_w;
  logic signed [40:0] z_w;
  logic signed [40:0] selected_a_w;
  logic signed [40:0] selected_b_w;
  logic all_s40;

  always_comb begin
    // Widen first so sign extension precedes every multiply, add and negate.
    alpha_cmp_w = {{11{v_alpha[24]}}, v_alpha};
    beta_cmp_w = {{11{v_beta[24]}}, v_beta};
    cmp1_w = (alpha_cmp_w * SVPWM_CMP_A) -
             (beta_cmp_w * SVPWM_CMP_B);
    cmp2_w = ((-alpha_cmp_w) * SVPWM_CMP_A) -
             (beta_cmp_w * SVPWM_CMP_B);

    cmp0 = v_beta;
    cmp1 = cmp1_w;
    cmp2 = cmp2_w;
    b0 = (cmp0 > 0);
    b1 = (cmp1_w >= 0);
    b2 = (cmp2_w > 0);
    sector = {2'b0, b0} + ({2'b0, b1} << 1) + ({2'b0, b2} << 2);

    alpha_xyz_w = {{16{v_alpha[24]}}, v_alpha};
    beta_xyz_w = {{16{v_beta[24]}}, v_beta};
    x_w = beta_xyz_w * SVPWM_X_COEFF;
    y_w = (beta_xyz_w * SVPWM_YB_COEFF) +
          (alpha_xyz_w * SVPWM_YA_COEFF);
    z_w = (beta_xyz_w * SVPWM_YB_COEFF) -
          (alpha_xyz_w * SVPWM_YA_COEFF);

    selected_a_w = '0;
    selected_b_w = '0;
    case (sector)
      3'd1: begin selected_a_w = z_w;    selected_b_w = y_w;    end
      3'd2: begin selected_a_w = y_w;    selected_b_w = -x_w;   end
      3'd3: begin selected_a_w = -z_w;   selected_b_w = x_w;    end
      3'd4: begin selected_a_w = -x_w;   selected_b_w = z_w;    end
      3'd5: begin selected_a_w = x_w;    selected_b_w = -y_w;   end
      3'd6: begin selected_a_w = -y_w;   selected_b_w = -z_w;   end
      default: begin selected_a_w = '0; selected_b_w = '0; end
    endcase

    all_s40 = svpwm_fits_s40({{55{x_w[40]}}, x_w}) &&
              svpwm_fits_s40({{55{y_w[40]}}, y_w}) &&
              svpwm_fits_s40({{55{z_w[40]}}, z_w}) &&
              svpwm_fits_s40({{55{selected_a_w[40]}}, selected_a_w}) &&
              svpwm_fits_s40({{55{selected_b_w[40]}}, selected_b_w});
    xyz_range_ok = all_s40 && (sector >= 3'd1) && (sector <= 3'd6);

    // Invalid widened results are surfaced through xyz_range_ok and are not
    // truncated into apparently valid S40 values.
    if (xyz_range_ok) begin
      x_num = x_w[39:0];
      y_num = y_w[39:0];
      z_num = z_w[39:0];
      a_num = selected_a_w[39:0];
      b_num = selected_b_w[39:0];
    end else begin
      x_num = '0;
      y_num = '0;
      z_num = '0;
      a_num = '0;
      b_num = '0;
    end
  end
endmodule
