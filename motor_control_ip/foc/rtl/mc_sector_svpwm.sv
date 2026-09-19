`timescale 1ns/1ps

module mc_sector_svpwm (
  input  logic clk,
  input  logic reset_n,
  input  logic input_valid,
  output logic input_ready,
  input  logic signed [24:0] v_alpha,
  input  logic signed [24:0] v_beta,
  input  logic signed [24:0] vdc,
  output logic output_valid,
  output logic signed [25:0] duty_u,
  output logic signed [25:0] duty_v,
  output logic signed [25:0] duty_w,
  output logic [2:0] sector,
  output logic overmodulated,
  output logic [1:0] error_code
);
  import mc_svpwm_pkg::*;

  localparam logic [1:0] OK            = 2'b00;
  localparam logic [1:0] INVALID_VDC   = 2'b01;
  localparam logic [1:0] RANGE_ERROR   = 2'b10;
  localparam logic [1:0] INTERNAL_ERROR = 2'b11;

  logic busy;
  logic [6:0] age;
  logic signed [24:0] captured_alpha;
  logic signed [24:0] captured_beta;
  logic signed [24:0] captured_vdc;

  logic signed [24:0] xyz_cmp0;
  logic signed [35:0] xyz_cmp1;
  logic signed [35:0] xyz_cmp2;
  logic xyz_b0;
  logic xyz_b1;
  logic xyz_b2;
  logic [2:0] xyz_sector;
  logic signed [39:0] xyz_x_num;
  logic signed [39:0] xyz_y_num;
  logic signed [39:0] xyz_z_num;
  logic signed [39:0] xyz_a_num;
  logic signed [39:0] xyz_b_num;
  logic xyz_range_ok;
  logic xyz_stage_valid;
  logic xyz_range_ok_reg;

  // These named registers are intentional hierarchy-visible debug nodes.
  logic signed [39:0] a_num_debug;
  logic signed [39:0] b_num_debug;
  logic signed [40:0] sum_num_debug;
  logic signed [38:0] base_debug;
  logic signed [40:0] denominator_debug;
  logic signed [33:0] t1_debug;
  logic signed [33:0] t2_debug;
  logic signed [33:0] l_debug;
  logic signed [33:0] m_debug;
  logic signed [33:0] h_debug;

  logic signed [95:0] sum_wide;
  logic signed [95:0] base_wide;
  logic signed [95:0] denominator_wide;
  logic selected_overmodulated;
  logic signed [40:0] a_extended;
  logic signed [40:0] b_extended;
  logic [40:0] a_magnitude;
  logic [40:0] b_magnitude;

  logic divider_input_valid;
  logic divider_a_ready;
  logic divider_b_ready;
  logic divider_a_valid;
  logic divider_b_valid;
  logic [71:0] divider_a_numerator;
  logic [71:0] divider_b_numerator;
  logic [40:0] divider_denominator;
  logic [71:0] divider_a_quotient;
  logic [71:0] divider_b_quotient;
  logic [40:0] divider_a_remainder;
  logic [40:0] divider_b_remainder;
  logic divider_a_zero;
  logic divider_b_zero;
  logic a_negative;
  logic b_negative;
  logic divider_expected;
  logic divider_result_valid;
  logic [71:0] captured_quotient_a;
  logic [71:0] captured_quotient_b;
  logic [40:0] captured_remainder_a;
  logic [40:0] captured_remainder_b;
  logic [112:0] quotient_product_a;
  logic [112:0] quotient_product_b;
  logic [113:0] reconstructed_numerator_a;
  logic [113:0] reconstructed_numerator_b;

  logic [41:0] twice_remainder_a;
  logic [41:0] twice_remainder_b;
  logic [41:0] denominator_compare;
  logic [72:0] rounded_magnitude_a;
  logic [72:0] rounded_magnitude_b;
  logic signed [73:0] signed_quotient_a;
  logic signed [73:0] signed_quotient_b;
  logic signed [95:0] t1_rounded_wide;
  logic signed [95:0] t2_rounded_wide;

  logic t_stage_valid;
  logic lmh_stage_valid;
  logic signed [95:0] t1_stage_wide;
  logic signed [95:0] t2_stage_wide;
  logic signed [95:0] l_numerator_wide;
  logic signed [95:0] m_numerator_wide;
  logic signed [95:0] h_numerator_wide;
  logic signed [95:0] l_rounded_wide;
  logic signed [95:0] m_rounded_wide;
  logic signed [95:0] h_rounded_wide;

  logic signed [95:0] phase_u_wide;
  logic signed [95:0] phase_v_wide;
  logic signed [95:0] phase_w_wide;
  logic signed [95:0] duty_u_wide;
  logic signed [95:0] duty_v_wide;
  logic signed [95:0] duty_w_wide;

  logic [2:0] pending_sector;
  logic pending_overmodulated;
  logic [1:0] pending_error;
  logic signed [25:0] pending_duty_u;
  logic signed [25:0] pending_duty_v;
  logic signed [25:0] pending_duty_w;
  logic result_ready;

  assign input_ready = reset_n && !busy;

  mc_svpwm_sector_xyz sector_xyz (
    .v_alpha(captured_alpha),
    .v_beta(captured_beta),
    .cmp0(xyz_cmp0),
    .cmp1(xyz_cmp1),
    .cmp2(xyz_cmp2),
    .b0(xyz_b0),
    .b1(xyz_b1),
    .b2(xyz_b2),
    .sector(xyz_sector),
    .x_num(xyz_x_num),
    .y_num(xyz_y_num),
    .z_num(xyz_z_num),
    .a_num(xyz_a_num),
    .b_num(xyz_b_num),
    .xyz_range_ok(xyz_range_ok)
  );

  mc_udiv_u72_u41 divider_t1 (
    .clk(clk), .reset_n(reset_n),
    .input_valid(divider_input_valid), .input_ready(divider_a_ready),
    .output_valid(divider_a_valid),
    .numerator(divider_a_numerator),
    .denominator(divider_denominator),
    .quotient(divider_a_quotient), .remainder(divider_a_remainder),
    .div_by_zero(divider_a_zero)
  );

  mc_udiv_u72_u41 divider_t2 (
    .clk(clk), .reset_n(reset_n),
    .input_valid(divider_input_valid), .input_ready(divider_b_ready),
    .output_valid(divider_b_valid),
    .numerator(divider_b_numerator),
    .denominator(divider_denominator),
    .quotient(divider_b_quotient), .remainder(divider_b_remainder),
    .div_by_zero(divider_b_zero)
  );

  always_comb begin
    sum_wide = {{56{a_num_debug[39]}}, a_num_debug} +
               {{56{b_num_debug[39]}}, b_num_debug};
    base_wide = {{71{captured_vdc[24]}}, captured_vdc} * 96'sd10000;
    selected_overmodulated = (sum_wide > base_wide);
    denominator_wide = selected_overmodulated ? sum_wide : base_wide;

    a_extended = {a_num_debug[39], a_num_debug};
    b_extended = {b_num_debug[39], b_num_debug};
    a_magnitude = a_extended[40] ? $unsigned(-a_extended)
                                         : $unsigned(a_extended);
    b_magnitude = b_extended[40] ? $unsigned(-b_extended)
                                         : $unsigned(b_extended);
  end

  always_comb begin
    quotient_product_a = captured_quotient_a * divider_denominator;
    quotient_product_b = captured_quotient_b * divider_denominator;
    reconstructed_numerator_a = {1'b0, quotient_product_a} +
                                {{73{1'b0}}, captured_remainder_a};
    reconstructed_numerator_b = {1'b0, quotient_product_b} +
                                {{73{1'b0}}, captured_remainder_b};
    twice_remainder_a = {captured_remainder_a, 1'b0};
    twice_remainder_b = {captured_remainder_b, 1'b0};
    denominator_compare = {1'b0, divider_denominator};
    rounded_magnitude_a = {1'b0, captured_quotient_a};
    rounded_magnitude_b = {1'b0, captured_quotient_b};
    if (twice_remainder_a >= denominator_compare)
      rounded_magnitude_a = rounded_magnitude_a + 73'd1;
    if (twice_remainder_b >= denominator_compare)
      rounded_magnitude_b = rounded_magnitude_b + 73'd1;
    signed_quotient_a = a_negative
                      ? -$signed({1'b0, rounded_magnitude_a})
                      :  $signed({1'b0, rounded_magnitude_a});
    signed_quotient_b = b_negative
                      ? -$signed({1'b0, rounded_magnitude_b})
                      :  $signed({1'b0, rounded_magnitude_b});
    t1_rounded_wide = {{22{signed_quotient_a[73]}}, signed_quotient_a};
    t2_rounded_wide = {{22{signed_quotient_b[73]}}, signed_quotient_b};
  end

  always_comb begin
    t1_stage_wide = {{62{t1_debug[33]}}, t1_debug};
    t2_stage_wide = {{62{t2_debug[33]}}, t2_debug};
    l_numerator_wide = 96'sd4294967296 - t1_stage_wide - t2_stage_wide;
    m_numerator_wide = 96'sd4294967296 + t1_stage_wide - t2_stage_wide;
    h_numerator_wide = 96'sd4294967296 + t1_stage_wide + t2_stage_wide;
    l_rounded_wide = svpwm_round_shift_s96(l_numerator_wide, 1);
    m_rounded_wide = svpwm_round_shift_s96(m_numerator_wide, 1);
    h_rounded_wide = svpwm_round_shift_s96(h_numerator_wide, 1);
  end

  always_comb begin
    phase_u_wide = '0;
    phase_v_wide = '0;
    phase_w_wide = '0;
    case (pending_sector)
      3'd1: begin
        phase_u_wide = {{62{m_debug[33]}}, m_debug};
        phase_v_wide = {{62{l_debug[33]}}, l_debug};
        phase_w_wide = {{62{h_debug[33]}}, h_debug};
      end
      3'd2: begin
        phase_u_wide = {{62{l_debug[33]}}, l_debug};
        phase_v_wide = {{62{h_debug[33]}}, h_debug};
        phase_w_wide = {{62{m_debug[33]}}, m_debug};
      end
      3'd3: begin
        phase_u_wide = {{62{l_debug[33]}}, l_debug};
        phase_v_wide = {{62{m_debug[33]}}, m_debug};
        phase_w_wide = {{62{h_debug[33]}}, h_debug};
      end
      3'd4: begin
        phase_u_wide = {{62{h_debug[33]}}, h_debug};
        phase_v_wide = {{62{m_debug[33]}}, m_debug};
        phase_w_wide = {{62{l_debug[33]}}, l_debug};
      end
      3'd5: begin
        phase_u_wide = {{62{h_debug[33]}}, h_debug};
        phase_v_wide = {{62{l_debug[33]}}, l_debug};
        phase_w_wide = {{62{m_debug[33]}}, m_debug};
      end
      3'd6: begin
        phase_u_wide = {{62{m_debug[33]}}, m_debug};
        phase_v_wide = {{62{h_debug[33]}}, h_debug};
        phase_w_wide = {{62{l_debug[33]}}, l_debug};
      end
      default: begin
        phase_u_wide = '0;
        phase_v_wide = '0;
        phase_w_wide = '0;
      end
    endcase
    duty_u_wide = svpwm_round_shift_s96(phase_u_wide, 8);
    duty_v_wide = svpwm_round_shift_s96(phase_v_wide, 8);
    duty_w_wide = svpwm_round_shift_s96(phase_w_wide, 8);
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      busy <= 1'b0;
      age <= '0;
      captured_alpha <= '0;
      captured_beta <= '0;
      captured_vdc <= '0;
      xyz_stage_valid <= 1'b0;
      xyz_range_ok_reg <= 1'b0;
      divider_input_valid <= 1'b0;
      divider_a_numerator <= '0;
      divider_b_numerator <= '0;
      divider_denominator <= '0;
      a_negative <= 1'b0;
      b_negative <= 1'b0;
      divider_expected <= 1'b0;
      divider_result_valid <= 1'b0;
      captured_quotient_a <= '0;
      captured_quotient_b <= '0;
      captured_remainder_a <= '0;
      captured_remainder_b <= '0;
      t_stage_valid <= 1'b0;
      lmh_stage_valid <= 1'b0;
      pending_sector <= '0;
      pending_overmodulated <= 1'b0;
      pending_error <= OK;
      pending_duty_u <= '0;
      pending_duty_v <= '0;
      pending_duty_w <= '0;
      result_ready <= 1'b0;
      a_num_debug <= '0;
      b_num_debug <= '0;
      sum_num_debug <= '0;
      base_debug <= '0;
      denominator_debug <= '0;
      t1_debug <= '0;
      t2_debug <= '0;
      l_debug <= '0;
      m_debug <= '0;
      h_debug <= '0;
      output_valid <= 1'b0;
      duty_u <= '0;
      duty_v <= '0;
      duty_w <= '0;
      sector <= '0;
      overmodulated <= 1'b0;
      error_code <= OK;
    end else begin
      output_valid <= 1'b0;
      xyz_stage_valid <= 1'b0;
      divider_input_valid <= 1'b0;
      divider_result_valid <= 1'b0;
      t_stage_valid <= 1'b0;
      lmh_stage_valid <= 1'b0;

      if (!busy) begin
        if (input_valid) begin
          busy <= 1'b1;
          age <= 7'd0;
          captured_alpha <= v_alpha;
          captured_beta <= v_beta;
          captured_vdc <= vdc;
          pending_sector <= '0;
          pending_overmodulated <= 1'b0;
          pending_error <= INTERNAL_ERROR;
          pending_duty_u <= '0;
          pending_duty_v <= '0;
          pending_duty_w <= '0;
          result_ready <= 1'b0;
          divider_expected <= 1'b0;
          captured_quotient_a <= '0;
          captured_quotient_b <= '0;
          captured_remainder_a <= '0;
          captured_remainder_b <= '0;
          xyz_range_ok_reg <= 1'b0;
          a_num_debug <= '0;
          b_num_debug <= '0;
          sum_num_debug <= '0;
          base_debug <= '0;
          denominator_debug <= '0;
          t1_debug <= '0;
          t2_debug <= '0;
          l_debug <= '0;
          m_debug <= '0;
          h_debug <= '0;
        end
      end else begin
        age <= age + 7'd1;

        if (age == 7'd0) begin
          // Register the combinational Sector/XYZ result before the wide
          // SUM/BASE selection and divider launch. This uses one otherwise
          // idle slot in the fixed N+128 response window.
          pending_sector <= xyz_sector;
          a_num_debug <= xyz_a_num;
          b_num_debug <= xyz_b_num;
          xyz_range_ok_reg <= xyz_range_ok;
          xyz_stage_valid <= 1'b1;
        end

        if (xyz_stage_valid && (age == 7'd1)) begin
          if (captured_vdc <= 0) begin
            pending_error <= INVALID_VDC;
            pending_sector <= '0;
            a_num_debug <= '0;
            b_num_debug <= '0;
            result_ready <= 1'b1;
          end else if ((pending_sector < 3'd1) || (pending_sector > 3'd6)) begin
            pending_error <= INTERNAL_ERROR;
            pending_sector <= '0;
            a_num_debug <= '0;
            b_num_debug <= '0;
            result_ready <= 1'b1;
          end else if (!xyz_range_ok_reg) begin
            pending_error <= RANGE_ERROR;
            pending_sector <= '0;
            a_num_debug <= '0;
            b_num_debug <= '0;
            result_ready <= 1'b1;
          end else if ((denominator_wide <= 0) ||
                       (denominator_wide > 96'sd1099511627775)) begin
            pending_error <= INTERNAL_ERROR;
            pending_sector <= '0;
            a_num_debug <= '0;
            b_num_debug <= '0;
            result_ready <= 1'b1;
          end else if (!divider_a_ready || !divider_b_ready) begin
            pending_error <= INTERNAL_ERROR;
            pending_sector <= '0;
            a_num_debug <= '0;
            b_num_debug <= '0;
            result_ready <= 1'b1;
          end else begin
            pending_overmodulated <= selected_overmodulated;
            pending_error <= OK;
            sum_num_debug <= sum_wide[40:0];
            base_debug <= base_wide[38:0];
            denominator_debug <= denominator_wide[40:0];
            a_negative <= a_num_debug[39];
            b_negative <= b_num_debug[39];
            divider_a_numerator <= {31'd0, a_magnitude} << 32;
            divider_b_numerator <= {31'd0, b_magnitude} << 32;
            divider_denominator <= denominator_wide[40:0];
            divider_input_valid <= 1'b1;
            divider_expected <= 1'b1;
          end
        end

        // Top accepts at N, registers Sector/XYZ at N+1, and launches both
        // dividers at N+2. They accept at N+3, update outputs at N+75, and
        // the parent observes them at N+76 while age is 75.
        if (divider_expected && (age == 7'd75)) begin
          if (!(divider_a_valid && divider_b_valid) ||
              divider_a_zero || divider_b_zero ||
              (divider_denominator == 0) ||
              (divider_a_remainder >= divider_denominator) ||
              (divider_b_remainder >= divider_denominator)) begin
            pending_error <= INTERNAL_ERROR;
            pending_sector <= '0;
            pending_overmodulated <= 1'b0;
            result_ready <= 1'b1;
          end else begin
            captured_quotient_a <= divider_a_quotient;
            captured_quotient_b <= divider_b_quotient;
            captured_remainder_a <= divider_a_remainder;
            captured_remainder_b <= divider_b_remainder;
            divider_result_valid <= 1'b1;
          end
        end else if (divider_a_valid || divider_b_valid) begin
          pending_error <= INTERNAL_ERROR;
          pending_sector <= '0;
          pending_overmodulated <= 1'b0;
          result_ready <= 1'b1;
        end

        if (divider_result_valid) begin
          if ((reconstructed_numerator_a !==
               {{42{1'b0}}, divider_a_numerator}) ||
              (reconstructed_numerator_b !==
               {{42{1'b0}}, divider_b_numerator})) begin
            pending_error <= INTERNAL_ERROR;
            pending_sector <= '0;
            pending_overmodulated <= 1'b0;
            result_ready <= 1'b1;
          end else if (!svpwm_fits_s34(t1_rounded_wide) ||
                       !svpwm_fits_s34(t2_rounded_wide)) begin
            pending_error <= RANGE_ERROR;
            pending_sector <= '0;
            pending_overmodulated <= 1'b0;
            result_ready <= 1'b1;
          end else begin
            t1_debug <= t1_rounded_wide[33:0];
            t2_debug <= t2_rounded_wide[33:0];
            t_stage_valid <= 1'b1;
          end
        end

        if (t_stage_valid) begin
          if (!svpwm_fits_s34(l_rounded_wide) ||
              !svpwm_fits_s34(m_rounded_wide) ||
              !svpwm_fits_s34(h_rounded_wide)) begin
            pending_error <= RANGE_ERROR;
            pending_sector <= '0;
            pending_overmodulated <= 1'b0;
            result_ready <= 1'b1;
          end else begin
            l_debug <= l_rounded_wide[33:0];
            m_debug <= m_rounded_wide[33:0];
            h_debug <= h_rounded_wide[33:0];
            lmh_stage_valid <= 1'b1;
          end
        end

        if (lmh_stage_valid) begin
          if ((pending_sector < 3'd1) || (pending_sector > 3'd6)) begin
            pending_error <= INTERNAL_ERROR;
            pending_sector <= '0;
            pending_overmodulated <= 1'b0;
            result_ready <= 1'b1;
          end else if (!svpwm_fits_s26(duty_u_wide) ||
                       !svpwm_fits_s26(duty_v_wide) ||
                       !svpwm_fits_s26(duty_w_wide)) begin
            pending_error <= RANGE_ERROR;
            pending_sector <= '0;
            pending_overmodulated <= 1'b0;
            result_ready <= 1'b1;
          end else begin
            pending_duty_u <= duty_u_wide[25:0];
            pending_duty_v <= duty_v_wide[25:0];
            pending_duty_w <= duty_w_wide[25:0];
            result_ready <= 1'b1;
          end
        end

        if (age == 7'd127) begin
          busy <= 1'b0;
          output_valid <= 1'b1;
          if (result_ready && (pending_error == OK)) begin
            duty_u <= pending_duty_u;
            duty_v <= pending_duty_v;
            duty_w <= pending_duty_w;
            sector <= pending_sector;
            overmodulated <= pending_overmodulated;
            error_code <= OK;
          end else begin
            duty_u <= '0;
            duty_v <= '0;
            duty_w <= '0;
            sector <= '0;
            overmodulated <= 1'b0;
            error_code <= result_ready ? pending_error : INTERNAL_ERROR;
            if (!result_ready) begin
              a_num_debug <= '0;
              b_num_debug <= '0;
              sum_num_debug <= '0;
              base_debug <= '0;
              denominator_debug <= '0;
              t1_debug <= '0;
              t2_debug <= '0;
              l_debug <= '0;
              m_debug <= '0;
              h_debug <= '0;
            end
          end
        end
      end
    end
  end
endmodule
