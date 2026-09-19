package mc_svpwm_pkg;
  localparam int SVPWM_INPUT_WIDTH       = 25;
  localparam int SVPWM_INPUT_FRAC_BITS   = 15;
  localparam int SVPWM_XYZ_WIDTH         = 40;
  localparam int SVPWM_DWELL_WIDTH       = 34;
  localparam int SVPWM_DWELL_FRAC_BITS   = 32;
  localparam int SVPWM_DUTY_WIDTH        = 26;
  localparam int SVPWM_DUTY_FRAC_BITS    = 24;

  localparam logic signed [35:0] SVPWM_CMP_A = 36'sd433;
  localparam logic signed [35:0] SVPWM_CMP_B = 36'sd250;
  localparam logic signed [40:0] SVPWM_X_COEFF  = 41'sd17321;
  localparam logic signed [40:0] SVPWM_YB_COEFF = 41'sd8660;
  localparam logic signed [40:0] SVPWM_YA_COEFF = 41'sd15000;
  localparam logic signed [33:0] SVPWM_ONE_F32 = 34'sd4294967296;

  // Signed nearest rounding with exact half ties away from zero. Extending
  // before abs makes the S96 negative rail representable as a magnitude.
  function automatic logic signed [95:0] svpwm_round_shift_s96(
    input logic signed [95:0] value,
    input int unsigned shift
  );
    logic signed [96:0] extended_value;
    logic [96:0] magnitude;
    logic [96:0] rounding_bias;
    logic [96:0] rounded_magnitude;
    logic signed [96:0] signed_result;
    begin
      extended_value = {value[95], value};
      magnitude = extended_value[96] ? $unsigned(-extended_value)
                                     : $unsigned(extended_value);
      rounding_bias = '0;
      rounded_magnitude = '0;
      signed_result = '0;
      if (shift > 95) begin
        svpwm_round_shift_s96 = 'x;
      end else begin
        if (shift == 0) begin
          rounded_magnitude = magnitude;
        end else begin
          rounding_bias = 97'd1 << (shift - 1);
          rounded_magnitude = (magnitude + rounding_bias) >> shift;
        end
        signed_result = extended_value[96]
                      ? -$signed({1'b0, rounded_magnitude[95:0]})
                      :  $signed({1'b0, rounded_magnitude[95:0]});
        svpwm_round_shift_s96 = signed_result[95:0];
      end
    end
  endfunction

  function automatic logic svpwm_fits_s40(
    input logic signed [95:0] value
  );
    begin
      svpwm_fits_s40 = (value >= -96'sd549755813888) &&
                       (value <=  96'sd549755813887);
    end
  endfunction

  function automatic logic svpwm_fits_s34(
    input logic signed [95:0] value
  );
    begin
      svpwm_fits_s34 = (value >= -96'sd8589934592) &&
                       (value <=  96'sd8589934591);
    end
  endfunction

  function automatic logic svpwm_fits_s26(
    input logic signed [95:0] value
  );
    begin
      svpwm_fits_s26 = (value >= -96'sd33554432) &&
                       (value <=  96'sd33554431);
    end
  endfunction
endpackage
