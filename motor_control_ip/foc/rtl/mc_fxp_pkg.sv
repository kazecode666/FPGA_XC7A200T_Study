package mc_fxp_pkg;
  localparam int PHASE_WIDTH = 24;
  localparam int TRANSFORM_WIDTH = 25;
  localparam int COEFF_WIDTH = 18;
  localparam int CURRENT_FRAC_BITS = 15;
  localparam int COEFF_FRAC_BITS = 16;

  localparam logic signed [17:0] C_TWO_THIRDS = 18'sd43691;
  localparam logic signed [17:0] C_INV_SQRT3  = 18'sd37837;
  localparam logic signed [17:0] SIN_COS_ONE  = 18'sd65536;

  // F31 signed-44 value to its rounded signed integer.  The extra magnitude
  // bit makes abs(-2^43) representable; ties round away from zero.
  function automatic logic signed [43:0] fxp_round_shift16_s44(
    input logic signed [43:0] value
  );
    logic signed [44:0] extended_value;
    logic [44:0] magnitude;
    logic [44:0] rounded_magnitude;
    begin
      extended_value = {value[43], value};
      magnitude = extended_value[44] ? $unsigned(-extended_value)
                                     : $unsigned(extended_value);
      rounded_magnitude = (magnitude + 45'd32768) >> 16;
      fxp_round_shift16_s44 = extended_value[44]
                            ? -$signed(rounded_magnitude[43:0])
                            :  $signed(rounded_magnitude[43:0]);
    end
  endfunction

  function automatic logic signed [24:0] fxp_sat_s25(
    input logic signed [43:0] value
  );
    begin
      if (value > 44'sd16777215)
        fxp_sat_s25 = 25'sd16777215;
      else if (value < -44'sd16777216)
        fxp_sat_s25 = -25'sd16777216;
      else
        fxp_sat_s25 = value[24:0];
    end
  endfunction

  function automatic logic signed [24:0] fxp_round_sat_f31_to_s25(
    input logic signed [43:0] value
  );
    logic signed [43:0] rounded;
    begin
      rounded = fxp_round_shift16_s44(value);
      fxp_round_sat_f31_to_s25 = fxp_sat_s25(rounded);
    end
  endfunction

  // Magnitude-based division by two, nearest with odd ties away from zero.
  function automatic logic signed [24:0] fxp_half_away_s25(
    input logic signed [24:0] value
  );
    logic signed [25:0] extended_value;
    logic [25:0] magnitude;
    logic [25:0] half_magnitude;
    begin
      extended_value = {value[24], value};
      magnitude = extended_value[25] ? $unsigned(-extended_value)
                                     : $unsigned(extended_value);
      half_magnitude = (magnitude + 26'd1) >> 1;
      fxp_half_away_s25 = extended_value[25]
                        ? -$signed(half_magnitude[24:0])
                        :  $signed(half_magnitude[24:0]);
    end
  endfunction
endpackage
