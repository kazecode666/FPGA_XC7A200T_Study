package mc_pi_fxp_pkg;
  // Frozen external and intermediate fixed-point formats.
  localparam int PI_CURRENT_WIDTH          = 25;
  localparam int PI_CURRENT_FRAC_BITS      = 15;
  localparam int PI_ERROR_WIDTH            = 26;
  localparam int PI_ERROR_FRAC_BITS        = 15;
  localparam int PI_SPEED_WIDTH            = 32;
  localparam int PI_SPEED_FRAC_BITS        = 16;
  localparam int PI_COEFF_WIDTH            = 32;
  localparam int PI_COEFF_FRAC_BITS        = 24;
  localparam int PI_MOTOR_CONST_WIDTH      = 32;
  localparam int PI_MOTOR_CONST_FRAC_BITS  = 30;
  localparam int PI_STATE_WIDTH            = 40;
  localparam int PI_STATE_FRAC_BITS        = 24;
  localparam int PI_NORM_WIDTH             = 80;
  localparam int PI_NORM_FRAC_BITS         = 48;
  localparam int PI_ROOT_WIDTH             = 40;
  localparam int PI_ROOT_FRAC_BITS         = 24;
  localparam int PI_DENOM_WIDTH            = 41;
  localparam int PI_DENOM_FRAC_BITS        = 24;
  localparam int PI_SCALE_WIDTH            = 33;
  localparam int PI_SCALE_FRAC_BITS        = 32;

  localparam int PI_PROFILE_REAL_COMMISSIONING = 0;
  localparam int PI_PROFILE_MIL_PI_OVERRIDE    = 1;

  // S32/F24 profile coefficients.  The descriptive profile names keep later
  // evaluator/core selection readable and prevent deriving profile 1 from an
  // already rounded profile-0 coefficient.
  localparam logic signed [31:0] PI_KP_REAL_COMMISSIONING = 32'sd36595302;
  localparam logic signed [31:0] PI_KI_TS_REAL_COMMISSIONING = 32'sd4970250;
  localparam logic signed [31:0] PI_KAW_D_REAL_COMMISSIONING = 32'sd3355443;
  localparam logic signed [31:0] PI_KAW_Q_REAL_COMMISSIONING = 32'sd3355443;

  localparam logic signed [31:0] PI_KP_MIL_PI_OVERRIDE = 32'sd73190605;
  localparam logic signed [31:0] PI_KI_TS_MIL_PI_OVERRIDE = 32'sd9940500;
  localparam logic signed [31:0] PI_KAW_D_MIL_PI_OVERRIDE = 32'sd3355443;
  localparam logic signed [31:0] PI_KAW_Q_MIL_PI_OVERRIDE = 32'sd3355443;

  // Shared S32/F30 motor constants and limiter literals.
  localparam logic signed [31:0] PI_LD = 32'sd1873679;
  localparam logic signed [31:0] PI_LQ = 32'sd1873679;
  localparam logic signed [31:0] PI_PSI_F = 32'sd151397597;
  localparam logic [31:0] PI_C_UMAX = 32'd557932618;
  localparam logic [40:0] PI_EPS_RAW = 41'd17;
  localparam logic signed [39:0] PI_STATE_MIN = 40'sh8000000000;
  localparam logic signed [39:0] PI_STATE_MAX = 40'sh7fffffffff;
  localparam logic [32:0] PI_ONE_SCALE = 33'd4294967296;

  // Signed nearest rounding, ties away from zero.  The signed input is first
  // extended to 97 bits, so abs(-2^95) is represented without overflow.
  function automatic logic signed [95:0] pi_round_shift_s96(
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
        pi_round_shift_s96 = 'x;
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
        pi_round_shift_s96 = signed_result[95:0];
      end
    end
  endfunction

  function automatic logic pi_fits_s40(
    input logic signed [95:0] value
  );
    begin
      pi_fits_s40 = (value >= -96'sd549755813888) &&
                    (value <=  96'sd549755813887);
    end
  endfunction

  function automatic logic pi_fits_s25(
    input logic signed [95:0] value
  );
    begin
      pi_fits_s25 = (value >= -96'sd16777216) &&
                    (value <=  96'sd16777215);
    end
  endfunction
endpackage
