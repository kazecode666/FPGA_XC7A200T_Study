module mc_pi_dq_eval #(
  parameter int PI_PROFILE = 0
) (
  input logic clk, reset_n, input_valid,
  output logic input_ready, output_valid,
  input logic signed [24:0] id_meas, iq_meas, id_ref, iq_ref,
  input logic signed [31:0] we,
  input logic signed [24:0] vdc,
  input logic pi_reset, uq_zero_en,
  input logic signed [39:0] xd_old, xq_old, du_d_old, du_q_old,
  output logic signed [39:0] ud_raw, uq_raw, xd_next, xq_next,
  output logic [1:0] error_code
);
  import mc_pi_fxp_pkg::*;
  localparam logic signed [31:0] KP = (PI_PROFILE == 0)
    ? PI_KP_REAL_COMMISSIONING : PI_KP_MIL_PI_OVERRIDE;
  localparam logic signed [31:0] KI_TS = (PI_PROFILE == 0)
    ? PI_KI_TS_REAL_COMMISSIONING : PI_KI_TS_MIL_PI_OVERRIDE;
  localparam logic signed [31:0] KAW_D = (PI_PROFILE == 0)
    ? PI_KAW_D_REAL_COMMISSIONING : PI_KAW_D_MIL_PI_OVERRIDE;
  localparam logic signed [31:0] KAW_Q = (PI_PROFILE == 0)
    ? PI_KAW_Q_REAL_COMMISSIONING : PI_KAW_Q_MIL_PI_OVERRIDE;
  generate
    if (PI_PROFILE != 0 && PI_PROFILE != 1) begin : g_invalid_profile
      initial $fatal(1, "mc_pi_dq_eval PI_PROFILE must be 0 or 1");
    end
  endgenerate

  logic busy;
  logic [3:0] count;
  logic signed [24:0] cap_id, cap_iq, cap_id_ref, cap_iq_ref;
  logic signed [31:0] cap_we;
  logic cap_invalid_vdc, cap_pi_reset, cap_q_zero;
  logic signed [39:0] cap_x [0:1], cap_du [0:1];
  logic signed [25:0] error_current [0:1];
  logic signed [57:0] product_p [0:1], product_i [0:1];
  logic signed [71:0] product_aw [0:1];
  logic signed [56:0] product_flux [0:1];
  logic signed [57:0] flux [0:1];

  // Exact 32 x 58 multiplication split into six DSP-sized products.
  // Low/middle flux limbs and low speed limb have explicit unsigned-to-signed
  // extension. Only their top limbs are signed. Reassembly retains S90.
  logic signed [41:0] ff_ll [0:1], ff_lm [0:1];
  logic signed [26:0] ff_lh [0:1];
  logic signed [40:0] ff_hl [0:1], ff_hm [0:1];
  logic signed [25:0] ff_hh [0:1];
  logic signed [89:0] ff_pair0 [0:1], ff_pair1 [0:1], ff_pair2 [0:1];
  logic signed [89:0] ff_pair01 [0:1], product_ff [0:1];
  logic signed [95:0] term_p [0:1], term_i [0:1], term_aw [0:1], term_ff [0:1];
  logic signed [95:0] sum_px [0:1], sum_xi [0:1];
  logic signed [95:0] voltage_candidate [0:1], state_candidate [0:1];
  logic signed [95:0] voltage_selected [0:1], state_selected [0:1];
  logic signed [39:0] result_v [0:1], result_x [0:1];
  logic [1:0] result_error;
  integer axis;

  assign input_ready = reset_n && !busy;

  // Arithmetic registers deliberately have no reset. The busy/count controller
  // masks them, and every stage is overwritten before a response can use it.
  // No persistent integrator or correction is owned by this transaction unit.
  always_ff @(posedge clk) begin
    if (reset_n && input_valid && input_ready) begin
      cap_id <= id_meas; cap_iq <= iq_meas;
      cap_id_ref <= id_ref; cap_iq_ref <= iq_ref; cap_we <= we;
      cap_x[0] <= xd_old; cap_x[1] <= xq_old;
      cap_du[0] <= du_d_old; cap_du[1] <= du_q_old;
      cap_invalid_vdc <= (vdc <= 25'sd0);
      cap_pi_reset <= pi_reset; cap_q_zero <= uq_zero_en;
    end
    if (reset_n && busy) begin
      case (count)
        4'd0: begin // acceptance +1: form S26 errors, full flux/AW products
          error_current[0] <= $signed({cap_id_ref[24],cap_id_ref}) - $signed({cap_id[24],cap_id});
          error_current[1] <= cap_q_zero ? 26'sd0 :
            $signed({cap_iq_ref[24],cap_iq_ref}) - $signed({cap_iq[24],cap_iq});
          product_flux[0] <= PI_LQ * cap_iq;
          product_flux[1] <= PI_LD * cap_id;
          product_aw[0] <= cap_du[0] * KAW_D;
          product_aw[1] <= cap_du[1] * KAW_Q;
        end
        4'd1: begin // +2: S58 gain products, S58 q-flux addition
          for (axis=0;axis<2;axis=axis+1) begin
            product_p[axis] <= error_current[axis] * KP;
            product_i[axis] <= error_current[axis] * KI_TS;
          end
          flux[0] <= {product_flux[0][56],product_flux[0]};
          flux[1] <= $signed({product_flux[1][56],product_flux[1]}) +
            ($signed({{26{PI_PSI_F[31]}},PI_PSI_F}) <<< 15);
        end
        4'd2: begin // +3: registered partial products and independent R points
          for (axis=0;axis<2;axis=axis+1) begin
            term_p[axis] <= pi_round_shift_s96({{38{product_p[axis][57]}},product_p[axis]},15);
            term_i[axis] <= pi_round_shift_s96({{38{product_i[axis][57]}},product_i[axis]},15);
            term_aw[axis] <= pi_round_shift_s96({{24{product_aw[axis][71]}},product_aw[axis]},24);
            ff_ll[axis] <= $signed({1'b0,cap_we[15:0]}) * $signed({1'b0,flux[axis][23:0]});
            ff_lm[axis] <= $signed({1'b0,cap_we[15:0]}) * $signed({1'b0,flux[axis][47:24]});
            ff_lh[axis] <= $signed({1'b0,cap_we[15:0]}) * $signed(flux[axis][57:48]);
            ff_hl[axis] <= $signed(cap_we[31:16]) * $signed({1'b0,flux[axis][23:0]});
            ff_hm[axis] <= $signed(cap_we[31:16]) * $signed({1'b0,flux[axis][47:24]});
            ff_hh[axis] <= $signed(cap_we[31:16]) * $signed(flux[axis][57:48]);
          end
        end
        4'd3: begin // +4: pairwise S90 sums, widen before shifts
          for (axis=0;axis<2;axis=axis+1) begin
            ff_pair0[axis] <= $signed({{48{ff_ll[axis][41]}},ff_ll[axis]}) +
              ($signed({{49{ff_hl[axis][40]}},ff_hl[axis]}) <<< 16);
            ff_pair1[axis] <= ($signed({{48{ff_lm[axis][41]}},ff_lm[axis]}) <<< 24) +
              ($signed({{49{ff_hm[axis][40]}},ff_hm[axis]}) <<< 40);
            ff_pair2[axis] <= ($signed({{63{ff_lh[axis][26]}},ff_lh[axis]}) <<< 48) +
              ($signed({{64{ff_hh[axis][25]}},ff_hh[axis]}) <<< 64);
          end
        end
        4'd4: begin // +5
          for (axis=0;axis<2;axis=axis+1)
            ff_pair01[axis] <= ff_pair0[axis] + ff_pair1[axis];
        end
        4'd5: begin // +6: exact full S90/F61 products
          for (axis=0;axis<2;axis=axis+1)
            product_ff[axis] <= ff_pair01[axis] + ff_pair2[axis];
        end
        4'd6: begin // +7: sign-extend d before negation; round only here
          term_ff[0] <= pi_round_shift_s96(-$signed({{6{product_ff[0][89]}},product_ff[0]}),37);
          term_ff[1] <= pi_round_shift_s96({{6{product_ff[1][89]}},product_ff[1]},37);
        end
        4'd7: begin // +8: OLD x in voltage, no S40 intermediate clipping
          for (axis=0;axis<2;axis=axis+1) begin
            sum_px[axis] <= term_p[axis] + $signed({{56{cap_x[axis][39]}},cap_x[axis]});
            sum_xi[axis] <= $signed({{56{cap_x[axis][39]}},cap_x[axis]}) + term_i[axis];
          end
        end
        4'd8: begin // +9: all final sums remain S96
          for (axis=0;axis<2;axis=axis+1) begin
            voltage_candidate[axis] <= sum_px[axis] + term_ff[axis];
            state_candidate[axis] <= sum_xi[axis] - term_aw[axis];
          end
        end
        4'd9: begin // +10: reset selected axes BEFORE final range tests
          for (axis=0;axis<2;axis=axis+1) begin
            voltage_selected[axis] <= (cap_pi_reset || (axis==1 && cap_q_zero)) ? 96'sd0 : voltage_candidate[axis];
            state_selected[axis] <= (cap_pi_reset || (axis==1 && cap_q_zero)) ? 96'sd0 : state_candidate[axis];
          end
        end
        4'd10: begin // +11: invalid bus wins, errors preserve OLD next states
          if (cap_invalid_vdc) begin
            result_error <= 2'b01;
            result_v[0] <= '0; result_v[1] <= '0;
            result_x[0] <= cap_x[0]; result_x[1] <= cap_x[1];
          end else if (!pi_fits_s40(voltage_selected[0]) || !pi_fits_s40(voltage_selected[1]) ||
                       !pi_fits_s40(state_selected[0]) || !pi_fits_s40(state_selected[1])) begin
            result_error <= 2'b10;
            result_v[0] <= '0; result_v[1] <= '0;
            result_x[0] <= cap_x[0]; result_x[1] <= cap_x[1];
          end else begin
            result_error <= 2'b00;
            for (axis=0;axis<2;axis=axis+1) begin
              result_v[axis] <= voltage_selected[axis][39:0];
              result_x[axis] <= state_selected[axis][39:0];
            end
          end
        end
        default: begin end // +12..+16 pad all paths to the same response slot
      endcase
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      busy <= 1'b0; count <= '0; output_valid <= 1'b0;
      ud_raw <= '0; uq_raw <= '0; xd_next <= '0; xq_next <= '0; error_code <= '0;
    end else begin
      output_valid <= 1'b0;
      if (input_valid && input_ready) begin
        busy <= 1'b1; count <= '0;
      end else if (busy) begin
        if (count == 4'd15) begin
          busy <= 1'b0; output_valid <= 1'b1;
          ud_raw <= result_v[0]; uq_raw <= result_v[1];
          xd_next <= result_x[0]; xq_next <= result_x[1]; error_code <= result_error;
        end else count <= count + 4'd1;
      end
    end
  end
endmodule
