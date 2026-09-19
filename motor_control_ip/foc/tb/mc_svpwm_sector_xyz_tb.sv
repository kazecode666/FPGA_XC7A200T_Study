`timescale 1ns/1ps

module mc_svpwm_sector_xyz_tb;
  localparam int FIXTURE_ROWS = 790;
  localparam int FIXTURE_FIELDS = 16;

  logic signed [24:0] v_alpha;
  logic signed [24:0] v_beta;
  logic signed [24:0] cmp0;
  logic signed [35:0] cmp1;
  logic signed [35:0] cmp2;
  logic b0;
  logic b1;
  logic b2;
  logic [2:0] sector;
  logic signed [39:0] x_num;
  logic signed [39:0] y_num;
  logic signed [39:0] z_num;
  logic signed [39:0] a_num;
  logic signed [39:0] b_num;
  logic xyz_range_ok;

  bit seen_tag [0:22];

  mc_svpwm_sector_xyz dut (
    .v_alpha(v_alpha), .v_beta(v_beta),
    .cmp0(cmp0), .cmp1(cmp1), .cmp2(cmp2),
    .b0(b0), .b1(b1), .b2(b2), .sector(sector),
    .x_num(x_num), .y_num(y_num), .z_num(z_num),
    .a_num(a_num), .b_num(b_num), .xyz_range_ok(xyz_range_ok)
  );

  task automatic fail(input string message);
    begin
      $fatal(1, "SVPWM_SECTOR_XYZ_TB_FAIL: %s", message);
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

  function automatic bit exact_header(input string line);
    string expected;
    int content_len;
    int i;
    begin
      expected = "# id tag_id v_alpha v_beta cmp0 cmp1 cmp2 b0 b1 b2 sector X Y Z a_num b_num";
      content_len = line.len();
      while ((content_len > 0) &&
             ((line[content_len-1] == 10) || (line[content_len-1] == 13)))
        content_len = content_len - 1;
      exact_header = (content_len == expected.len());
      if (exact_header)
        for (i = 0; i < content_len; i = i + 1)
          if (line[i] != expected[i])
            exact_header = 1'b0;
    end
  endfunction

  task automatic check_directed(
    input logic signed [24:0] A,
    input logic signed [24:0] B,
    input logic signed [35:0] expected_cmp1,
    input logic [2:0] expected_sector,
    input string label
  );
    begin
      v_alpha = A;
      v_beta = B;
      #1;
      if ($isunknown({cmp0, cmp1, cmp2, b0, b1, b2, sector,
                      x_num, y_num, z_num, a_num, b_num, xyz_range_ok}))
        fail({label, " produced X/Z"});
      if (cmp1 !== expected_cmp1 || sector !== expected_sector || !xyz_range_ok)
        fail($sformatf("%s cmp1=%0d sector=%0d range_ok=%0b expected=%0d/%0d/1",
                       label, cmp1, sector, xyz_range_ok,
                       expected_cmp1, expected_sector));
    end
  endtask

  task automatic load_and_check_fixture(input string vector_dir);
    string path;
    string line;
    string token;
    string tok [0:FIXTURE_FIELDS-1];
    logic [31:0] parsed_id;
    logic [15:0] parsed_tag;
    logic signed [24:0] parsed_alpha;
    logic signed [24:0] parsed_beta;
    logic signed [24:0] expected_cmp0;
    logic signed [35:0] expected_cmp1;
    logic signed [35:0] expected_cmp2;
    logic expected_b0;
    logic expected_b1;
    logic expected_b2;
    logic [2:0] expected_sector;
    logic signed [39:0] expected_x;
    logic signed [39:0] expected_y;
    logic signed [39:0] expected_z;
    logic signed [39:0] expected_a;
    logic signed [39:0] expected_b;
    logic [31:0] expected_id;
    int fd;
    int status;
    int line_number;
    int headers;
    int rows;
    int fields;
    int idx;
    int ch;
    int i;
    begin
      path = {vector_dir, "/sector_xyz_vectors.txt"};
      fd = $fopen(path, "r");
      if (fd == 0)
        fail($sformatf("cannot open %s", path));
      line_number = 0;
      headers = 0;
      rows = 0;
      while (!$feof(fd)) begin
        line = "";
        status = $fgets(line, fd);
        if (status != 0) begin
          line_number = line_number + 1;
          if ((line.len() == 1) && (line[0] == 10))
            fail($sformatf("blank line at line %0d", line_number));
          if ((line.len() == 2) && (line[0] == 13) && (line[1] == 10))
            fail($sformatf("blank line at line %0d", line_number));
          if ((line.len() > 0) && (line[0] == 35)) begin
            headers = headers + 1;
            if ((line_number != 1) || (headers != 1) || !exact_header(line))
              fail("fixture header mismatch or misplaced header");
          end else begin
            for (i = 0; i < FIXTURE_FIELDS; i = i + 1)
              tok[i] = "";
            fields = 0;
            token = "";
            // XSim 2026.1 can native-crash on missing multi-string sscanf
            // destinations. Tokenize indexed bytes, then convert one number.
            for (idx = 0; idx <= line.len(); idx = idx + 1) begin
              ch = (idx == line.len()) ? 32 : line[idx];
              if ((ch == 32) || (ch == 9) || (ch == 10) || (ch == 13)) begin
                if (token.len() != 0) begin
                  if (fields < FIXTURE_FIELDS)
                    tok[fields] = token;
                  fields = fields + 1;
                  token = "";
                end
              end else begin
                token = {token, 8'(ch)};
              end
            end
            if (fields != FIXTURE_FIELDS)
              fail($sformatf("fixture line %0d has %0d fields, expected %0d",
                             line_number, fields, FIXTURE_FIELDS));
            if (rows >= FIXTURE_ROWS)
              fail("fixture has extra rows");
            if (!valid_lower_hex(tok[0], 8, 32) ||
                !valid_lower_hex(tok[1], 4, 16) ||
                !valid_lower_hex(tok[2], 7, 25) ||
                !valid_lower_hex(tok[3], 7, 25) ||
                !valid_lower_hex(tok[4], 7, 25) ||
                !valid_lower_hex(tok[5], 9, 36) ||
                !valid_lower_hex(tok[6], 9, 36) ||
                !valid_lower_hex(tok[7], 1, 1) ||
                !valid_lower_hex(tok[8], 1, 1) ||
                !valid_lower_hex(tok[9], 1, 1) ||
                !valid_lower_hex(tok[10], 1, 3) ||
                !valid_lower_hex(tok[11], 10, 40) ||
                !valid_lower_hex(tok[12], 10, 40) ||
                !valid_lower_hex(tok[13], 10, 40) ||
                !valid_lower_hex(tok[14], 10, 40) ||
                !valid_lower_hex(tok[15], 10, 40))
              fail($sformatf("fixture lexical/width failure at line %0d", line_number));
            if (($sscanf(tok[0], "%h", parsed_id) != 1) ||
                ($sscanf(tok[1], "%h", parsed_tag) != 1) ||
                ($sscanf(tok[2], "%h", parsed_alpha) != 1) ||
                ($sscanf(tok[3], "%h", parsed_beta) != 1) ||
                ($sscanf(tok[4], "%h", expected_cmp0) != 1) ||
                ($sscanf(tok[5], "%h", expected_cmp1) != 1) ||
                ($sscanf(tok[6], "%h", expected_cmp2) != 1) ||
                ($sscanf(tok[7], "%h", expected_b0) != 1) ||
                ($sscanf(tok[8], "%h", expected_b1) != 1) ||
                ($sscanf(tok[9], "%h", expected_b2) != 1) ||
                ($sscanf(tok[10], "%h", expected_sector) != 1) ||
                ($sscanf(tok[11], "%h", expected_x) != 1) ||
                ($sscanf(tok[12], "%h", expected_y) != 1) ||
                ($sscanf(tok[13], "%h", expected_z) != 1) ||
                ($sscanf(tok[14], "%h", expected_a) != 1) ||
                ($sscanf(tok[15], "%h", expected_b) != 1))
              fail($sformatf("fixture numeric conversion failure at line %0d", line_number));

            expected_id = (rows < 22) ? (rows + 1) : (32'h1000 + rows - 22);
            if (parsed_id !== expected_id)
              fail($sformatf("fixture id %h at row %0d expected %h",
                             parsed_id, rows, expected_id));
            if ((rows < 22 && parsed_tag !== rows + 1) ||
                (rows >= 22 && parsed_tag !== 0))
              fail($sformatf("fixture tag %h at row %0d is not canonical",
                             parsed_tag, rows));
            if (parsed_tag <= 22)
              seen_tag[parsed_tag] = 1'b1;

            v_alpha = parsed_alpha;
            v_beta = parsed_beta;
            #1;
            if ($isunknown({cmp0, cmp1, cmp2, b0, b1, b2, sector,
                            x_num, y_num, z_num, a_num, b_num, xyz_range_ok}))
              fail($sformatf("DUT produced X/Z at fixture id %h", parsed_id));
            if ((cmp0 !== expected_cmp0) || (cmp1 !== expected_cmp1) ||
                (cmp2 !== expected_cmp2) || (b0 !== expected_b0) ||
                (b1 !== expected_b1) || (b2 !== expected_b2) ||
                (sector !== expected_sector) || (x_num !== expected_x) ||
                (y_num !== expected_y) || (z_num !== expected_z) ||
                (a_num !== expected_a) || (b_num !== expected_b) ||
                !xyz_range_ok)
              fail($sformatf("bit-exact mismatch id=%h tag=%h A=%0d B=%0d",
                             parsed_id, parsed_tag, parsed_alpha, parsed_beta));
            rows = rows + 1;
          end
        end
      end
      $fclose(fd);
      if (headers != 1)
        fail($sformatf("header count %0d expected 1", headers));
      if (rows != FIXTURE_ROWS)
        fail($sformatf("fixture row count %0d expected %0d", rows, FIXTURE_ROWS));
      for (i = 1; i <= 22; i = i + 1)
        if (!seen_tag[i])
          fail($sformatf("directed tag %0d was not observed", i));
    end
  endtask

  initial begin
    string vector_dir;
    int i;
    if (!$value$plusargs("VECTOR_DIR=%s", vector_dir))
      vector_dir = "motor_control_ip/foc/tb/vectors/step6c3";
    for (i = 0; i <= 22; i = i + 1)
      seen_tag[i] = 1'b0;

    check_directed(25'sd0, 25'sd0, 36'sd0, 3'd2, "zero vector");
    check_directed(25'sd25000, 25'sd43299, 36'sd250, 3'd3,
                   "named boundary B=43299");
    check_directed(25'sd25000, 25'sd43300, 36'sd0, 3'd3,
                   "named boundary B=43300");
    check_directed(25'sd25000, 25'sd43301, -36'sd250, 3'd1,
                   "named boundary B=43301");

    load_and_check_fixture(vector_dir);
    $display("ALL STEP 6C3 SECTOR XYZ TESTS PASSED rows=%0d fields=%0d directed=%0d seeded=%0d",
             FIXTURE_ROWS, FIXTURE_FIELDS, 22, 768);
    $finish;
  end
endmodule
