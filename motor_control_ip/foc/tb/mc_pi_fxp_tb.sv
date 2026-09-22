`timescale 1ns/1ps

module mc_pi_fxp_tb;
  import mc_pi_fxp_pkg::*;

  localparam int ROUND_ROWS = 1101;
  localparam int RANGE_ROWS = 9;

  logic [95:0] round_x [0:ROUND_ROWS-1];
  logic [7:0] round_shift [0:ROUND_ROWS-1];
  logic [95:0] round_expected [0:ROUND_ROWS-1];

  logic [95:0] range_x [0:RANGE_ROWS-1];
  logic range_s25 [0:RANGE_ROWS-1];
  logic range_s40 [0:RANGE_ROWS-1];

  task automatic fail(input string message);
    begin
      $fatal(1, "PI_FXP_TB_FAIL: %s", message);
    end
  endtask

  function automatic bit valid_lower_hex(
    input string token,
    input int expected_digits,
    input int significant_bits
  );
    int i;
    int c;
    int used_bits;
    int max_first;
    begin
      valid_lower_hex = (token.len() == expected_digits);
      if (valid_lower_hex) begin
        for (i = 0; i < token.len(); i = i + 1) begin
          c = token[i];
          if (!(((c >= 48) && (c <= 57)) || ((c >= 97) && (c <= 102))))
            valid_lower_hex = 1'b0;
        end
        used_bits = significant_bits - ((expected_digits - 1) * 4);
        if (used_bits < 4) begin
          max_first = (1 << used_bits) - 1;
          c = token[0];
          c = (c <= 57) ? (c - 48) : (c - 87);
          if (c > max_first)
            valid_lower_hex = 1'b0;
        end
      end
    end
  endfunction

  task automatic load_round_vectors(input string vector_dir);
    string path;
    string line;
    string id_token;
    string x_token;
    string shift_token;
    string expected_token;
    string extra_token;
    string token;
    logic [31:0] parsed_id;
    logic [95:0] parsed_x;
    logic [7:0] parsed_shift;
    logic [95:0] parsed_expected;
    int fd;
    int line_status;
    int fields;
    int idx;
    int ch;
    int rows;
    int line_number;
    int headers;
    begin
      path = {vector_dir, "/round_vectors.txt"};
      fd = $fopen(path, "r");
      if (fd == 0)
        fail($sformatf("cannot open %s", path));
      rows = 0;
      line_number = 0;
      headers = 0;
      while (!$feof(fd)) begin
        line = "";
        line_status = $fgets(line, fd);
        if (line_status != 0) begin
          line_number = line_number + 1;
          if ((line.len() == 1) && (line[0] == 10))
            fail($sformatf("blank line in round fixture at line %0d", line_number));
          if ((line.len() == 2) && (line[0] == 13) && (line[1] == 10))
            fail($sformatf("blank line in round fixture at line %0d", line_number));
          if ((line.len() > 0) && (line[0] == 35)) begin
            headers = headers + 1;
            if ((line_number != 1) || (headers != 1))
              fail("round fixture header is not the sole first-line header");
          end else begin
            id_token = "";
            x_token = "";
            shift_token = "";
            expected_token = "";
            extra_token = "";
            // XSim 2026.1 can crash when sscanf has missing string fields.
            // Indexed-byte tokenization preserves exact columns before hex casts.
            fields = 0;
            token = "";
            for (idx = 0; idx <= line.len(); idx = idx + 1) begin
              ch = (idx == line.len()) ? 32 : line[idx];
              if (ch == 32 || ch == 9 || ch == 10 || ch == 13) begin
                if (token.len() != 0) begin
                  case (fields)
                    0: id_token = token;
                    1: x_token = token;
                    2: shift_token = token;
                    3: expected_token = token;
                    default: extra_token = token;
                  endcase
                  fields = fields + 1;
                  token = "";
                end
              end else token = {token, 8'(ch)};
            end
            if (fields != 4)
              fail($sformatf("round fixture line %0d has %0d columns, expected 4",
                             line_number, fields));
            if (rows >= ROUND_ROWS)
              fail("round fixture has extra rows");
            if (!valid_lower_hex(id_token, 8, 32) ||
                !valid_lower_hex(x_token, 24, 96) ||
                !valid_lower_hex(shift_token, 2, 8) ||
                !valid_lower_hex(expected_token, 24, 96))
              fail($sformatf("round fixture lexical/width failure at line %0d",
                             line_number));
            if ($sscanf(id_token, "%h", parsed_id) != 1 ||
                $sscanf(x_token, "%h", parsed_x) != 1 ||
                $sscanf(shift_token, "%h", parsed_shift) != 1 ||
                $sscanf(expected_token, "%h", parsed_expected) != 1)
              fail($sformatf("round fixture conversion failure at line %0d",
                             line_number));
            if (parsed_id !== rows)
              fail($sformatf("round fixture id %0d is not contiguous expected %0d",
                             parsed_id, rows));
            round_x[rows] = parsed_x;
            round_shift[rows] = parsed_shift;
            round_expected[rows] = parsed_expected;
            if (round_shift[rows] > 8'd95)
              fail($sformatf("round fixture shift out of range at id %0d", rows));
            rows = rows + 1;
          end
        end
      end
      $fclose(fd);
      if (headers != 1)
        fail($sformatf("round fixture header count %0d expected 1", headers));
      if (rows != ROUND_ROWS)
        fail($sformatf("round fixture row count %0d expected %0d", rows, ROUND_ROWS));
    end
  endtask

  task automatic load_range_vectors(input string vector_dir);
    string path;
    string line;
    string id_token;
    string x_token;
    string s25_token;
    string s40_token;
    string extra_token;
    string token;
    logic [31:0] parsed_id;
    logic [95:0] parsed_x;
    logic parsed_s25;
    logic parsed_s40;
    int fd;
    int line_status;
    int fields;
    int idx;
    int ch;
    int rows;
    int line_number;
    int headers;
    begin
      path = {vector_dir, "/range_vectors.txt"};
      fd = $fopen(path, "r");
      if (fd == 0)
        fail($sformatf("cannot open %s", path));
      rows = 0;
      line_number = 0;
      headers = 0;
      while (!$feof(fd)) begin
        line = "";
        line_status = $fgets(line, fd);
        if (line_status != 0) begin
          line_number = line_number + 1;
          if ((line.len() == 1) && (line[0] == 10))
            fail($sformatf("blank line in range fixture at line %0d", line_number));
          if ((line.len() == 2) && (line[0] == 13) && (line[1] == 10))
            fail($sformatf("blank line in range fixture at line %0d", line_number));
          if ((line.len() > 0) && (line[0] == 35)) begin
            headers = headers + 1;
            if ((line_number != 1) || (headers != 1))
              fail("range fixture header is not the sole first-line header");
          end else begin
            id_token = "";
            x_token = "";
            s25_token = "";
            s40_token = "";
            extra_token = "";
            // XSim 2026.1 can crash when sscanf has missing string fields.
            // Indexed-byte tokenization preserves exact columns before hex casts.
            fields = 0;
            token = "";
            for (idx = 0; idx <= line.len(); idx = idx + 1) begin
              ch = (idx == line.len()) ? 32 : line[idx];
              if (ch == 32 || ch == 9 || ch == 10 || ch == 13) begin
                if (token.len() != 0) begin
                  case (fields)
                    0: id_token = token;
                    1: x_token = token;
                    2: s25_token = token;
                    3: s40_token = token;
                    default: extra_token = token;
                  endcase
                  fields = fields + 1;
                  token = "";
                end
              end else token = {token, 8'(ch)};
            end
            if (fields != 4)
              fail($sformatf("range fixture line %0d has %0d columns, expected 4",
                             line_number, fields));
            if (rows >= RANGE_ROWS)
              fail("range fixture has extra rows");
            if (!valid_lower_hex(id_token, 8, 32) ||
                !valid_lower_hex(x_token, 24, 96) ||
                !valid_lower_hex(s25_token, 1, 1) ||
                !valid_lower_hex(s40_token, 1, 1))
              fail($sformatf("range fixture lexical/width/high-padding failure at line %0d",
                             line_number));
            if ($sscanf(id_token, "%h", parsed_id) != 1 ||
                $sscanf(x_token, "%h", parsed_x) != 1 ||
                $sscanf(s25_token, "%h", parsed_s25) != 1 ||
                $sscanf(s40_token, "%h", parsed_s40) != 1)
              fail($sformatf("range fixture conversion failure at line %0d",
                             line_number));
            if (parsed_id !== rows)
              fail($sformatf("range fixture id %0d is not contiguous expected %0d",
                             parsed_id, rows));
            range_x[rows] = parsed_x;
            range_s25[rows] = parsed_s25;
            range_s40[rows] = parsed_s40;
            rows = rows + 1;
          end
        end
      end
      $fclose(fd);
      if (headers != 1)
        fail($sformatf("range fixture header count %0d expected 1", headers));
      if (rows != RANGE_ROWS)
        fail($sformatf("range fixture row count %0d expected %0d", rows, RANGE_ROWS));
    end
  endtask

  task automatic check_constants;
    begin
      if (PI_CURRENT_WIDTH != 25 || PI_CURRENT_FRAC_BITS != 15)
        fail("S25/F15 current format constants");
      if (PI_ERROR_WIDTH != 26 || PI_ERROR_FRAC_BITS != 15)
        fail("S26/F15 error format constants");
      if (PI_SPEED_WIDTH != 32 || PI_SPEED_FRAC_BITS != 16)
        fail("S32/F16 speed format constants");
      if (PI_COEFF_WIDTH != 32 || PI_COEFF_FRAC_BITS != 24)
        fail("S32/F24 PI coefficient format constants");
      if (PI_MOTOR_CONST_WIDTH != 32 || PI_MOTOR_CONST_FRAC_BITS != 30)
        fail("S32/F30 motor constant format constants");
      if (PI_STATE_WIDTH != 40 || PI_STATE_FRAC_BITS != 24)
        fail("S40/F24 state format constants");
      if (PI_NORM_WIDTH != 80 || PI_NORM_FRAC_BITS != 48 ||
          PI_ROOT_WIDTH != 40 || PI_ROOT_FRAC_BITS != 24 ||
          PI_DENOM_WIDTH != 41 || PI_DENOM_FRAC_BITS != 24 ||
          PI_SCALE_WIDTH != 33 || PI_SCALE_FRAC_BITS != 32)
        fail("limiter format constants");
      if (PI_PROFILE_REAL_COMMISSIONING != 0 || PI_PROFILE_MIL_PI_OVERRIDE != 1)
        fail("profile identifiers");

      if (PI_KP_REAL_COMMISSIONING !== 32'sd146381210 ||
          PI_KI_TS_REAL_COMMISSIONING !== 32'sd19881001 ||
          PI_KAW_D_REAL_COMMISSIONING !== 32'sd3355443 ||
          PI_KAW_Q_REAL_COMMISSIONING !== 32'sd3355443)
        fail("real_commissioning coefficient literals");
      if (PI_KP_MIL_PI_OVERRIDE !== 32'sd73190605 ||
          PI_KI_TS_MIL_PI_OVERRIDE !== 32'sd9940500 ||
          PI_KAW_D_MIL_PI_OVERRIDE !== 32'sd3355443 ||
          PI_KAW_Q_MIL_PI_OVERRIDE !== 32'sd3355443)
        fail("MIL_PI_override coefficient literals");
      if (PI_LD !== 32'sd1873679 || PI_LQ !== 32'sd1873679 ||
          PI_PSI_F !== 32'sd151397597)
        fail("motor constant literals");
      if (PI_C_UMAX !== 32'd557932618 || PI_EPS_RAW !== 41'd17 ||
          PI_STATE_MIN !== 40'sh8000000000 ||
          PI_STATE_MAX !== 40'sh7fffffffff ||
          PI_ONE_SCALE !== 33'd4294967296)
        fail("limiter/state literals");
    end
  endtask

  initial begin
    string vector_dir;
    logic signed [95:0] actual_round;
    logic actual_s25;
    logic actual_s40;
    bit seen_shift [0:95];
    int i;

    if (!$value$plusargs("VECTOR_DIR=%s", vector_dir))
      vector_dir = "motor_control_ip/foc/tb/vectors/step6c2";
    for (i = 0; i <= 95; i = i + 1)
      seen_shift[i] = 1'b0;

    check_constants();
    load_round_vectors(vector_dir);
    load_range_vectors(vector_dir);

    for (i = 0; i < ROUND_ROWS; i = i + 1) begin
      actual_round = pi_round_shift_s96($signed(round_x[i]), round_shift[i]);
      if ($isunknown(actual_round))
        fail($sformatf("round helper returned X/Z at id %0d", i));
      if (actual_round !== $signed(round_expected[i]))
        fail($sformatf("round id %0d shift %0d got %h expected %h",
                       i, round_shift[i], actual_round, round_expected[i]));
      seen_shift[round_shift[i]] = 1'b1;
    end

    if (!seen_shift[0] || !seen_shift[9] || !seen_shift[15] ||
        !seen_shift[24] || !seen_shift[32] || !seen_shift[37] ||
        !seen_shift[95])
      fail("required shift coverage 0/9/15/24/32/37/95 incomplete");

    for (i = 0; i < RANGE_ROWS; i = i + 1) begin
      actual_s25 = pi_fits_s25($signed(range_x[i]));
      actual_s40 = pi_fits_s40($signed(range_x[i]));
      if ($isunknown(actual_s25) || $isunknown(actual_s40))
        fail($sformatf("range helper returned X/Z at id %0d", i));
      if ((actual_s25 !== range_s25[i]) || (actual_s40 !== range_s40[i]))
        fail($sformatf("range id %0d got s25=%0b s40=%0b expected %0b/%0b",
                       i, actual_s25, actual_s40,
                       range_s25[i], range_s40[i]));
    end

    // Explicit rails and +/-1 neighbors make the range contract visible even
    // if a fixture is accidentally regenerated with less boundary coverage.
    if (!pi_fits_s25(96'sd16777215) || !pi_fits_s25(-96'sd16777216) ||
        pi_fits_s25(96'sd16777216) || pi_fits_s25(-96'sd16777217))
      fail("S25 rail +/-1 predicates");
    if (!pi_fits_s40(96'sd549755813887) || !pi_fits_s40(-96'sd549755813888) ||
        pi_fits_s40(96'sd549755813888) || pi_fits_s40(-96'sd549755813889))
      fail("S40 rail +/-1 predicates");

    $display("ALL STEP 6C2 FXP TESTS PASSED round_rows=%0d range_rows=%0d",
             ROUND_ROWS, RANGE_ROWS);
    $finish;
  end
endmodule
