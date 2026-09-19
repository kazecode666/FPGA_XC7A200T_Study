`timescale 1ns/1ps

module mc_sector_svpwm_tb;
  localparam int FIXTURE_ROWS = 790;
  localparam int FIXTURE_FIELDS = 21;
  localparam int QUEUE_DEPTH = 4;

  logic clk;
  logic reset_n;
  logic input_valid;
  logic input_ready;
  logic signed [24:0] v_alpha;
  logic signed [24:0] v_beta;
  logic signed [24:0] vdc;
  logic output_valid;
  logic signed [25:0] duty_u;
  logic signed [25:0] duty_v;
  logic signed [25:0] duty_w;
  logic [2:0] sector;
  logic overmodulated;
  logic [1:0] error_code;

  logic [2:0] drive_sector;
  logic drive_overmodulated;
  logic [1:0] drive_error_code;
  logic signed [39:0] drive_a_num;
  logic signed [39:0] drive_b_num;
  logic signed [40:0] drive_sum_num;
  logic signed [38:0] drive_base;
  logic signed [40:0] drive_denominator;
  logic signed [33:0] drive_t1;
  logic signed [33:0] drive_t2;
  logic signed [33:0] drive_l;
  logic signed [33:0] drive_m;
  logic signed [33:0] drive_h;
  logic signed [25:0] drive_duty_u;
  logic signed [25:0] drive_duty_v;
  logic signed [25:0] drive_duty_w;
  logic [31:0] drive_id;

  logic [2:0] expected_sector [0:QUEUE_DEPTH-1];
  logic expected_overmodulated [0:QUEUE_DEPTH-1];
  logic [1:0] expected_error_code [0:QUEUE_DEPTH-1];
  logic signed [39:0] expected_a_num [0:QUEUE_DEPTH-1];
  logic signed [39:0] expected_b_num [0:QUEUE_DEPTH-1];
  logic signed [40:0] expected_sum_num [0:QUEUE_DEPTH-1];
  logic signed [38:0] expected_base [0:QUEUE_DEPTH-1];
  logic signed [40:0] expected_denominator [0:QUEUE_DEPTH-1];
  logic signed [33:0] expected_t1 [0:QUEUE_DEPTH-1];
  logic signed [33:0] expected_t2 [0:QUEUE_DEPTH-1];
  logic signed [33:0] expected_l [0:QUEUE_DEPTH-1];
  logic signed [33:0] expected_m [0:QUEUE_DEPTH-1];
  logic signed [33:0] expected_h [0:QUEUE_DEPTH-1];
  logic signed [25:0] expected_duty_u [0:QUEUE_DEPTH-1];
  logic signed [25:0] expected_duty_v [0:QUEUE_DEPTH-1];
  logic signed [25:0] expected_duty_w [0:QUEUE_DEPTH-1];
  logic [31:0] expected_id [0:QUEUE_DEPTH-1];
  integer expected_edge [0:QUEUE_DEPTH-1];

  integer edge_number;
  integer queue_head;
  integer queue_tail;
  integer queue_count;
  integer accepted_count;
  integer response_count;
  integer poisoned_cycles;
  integer abort_count;
  bit seen_tag [0:22];
  logic accepted_now;

  mc_sector_svpwm dut (
    .clk(clk), .reset_n(reset_n),
    .input_valid(input_valid), .input_ready(input_ready),
    .v_alpha(v_alpha), .v_beta(v_beta), .vdc(vdc),
    .output_valid(output_valid),
    .duty_u(duty_u), .duty_v(duty_v), .duty_w(duty_w),
    .sector(sector), .overmodulated(overmodulated),
    .error_code(error_code)
  );

  always #10 clk = ~clk;

  task automatic fail(input string message);
    begin
      $fatal(1, "SECTOR_SVPWM_TB_FAIL: %s", message);
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
      expected = "# id tag_id v_alpha v_beta vdc sector overmodulated error_code a_num b_num sum_num base denominator t1 t2 L M H duty_u duty_v duty_w";
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

  task automatic clear_queue;
    begin
      queue_head = 0;
      queue_tail = 0;
      queue_count = 0;
    end
  endtask

  task automatic enqueue_expected;
    begin
      if (queue_count >= QUEUE_DEPTH)
        fail("scoreboard queue overflow");
      expected_sector[queue_tail] = drive_sector;
      expected_overmodulated[queue_tail] = drive_overmodulated;
      expected_error_code[queue_tail] = drive_error_code;
      expected_a_num[queue_tail] = drive_a_num;
      expected_b_num[queue_tail] = drive_b_num;
      expected_sum_num[queue_tail] = drive_sum_num;
      expected_base[queue_tail] = drive_base;
      expected_denominator[queue_tail] = drive_denominator;
      expected_t1[queue_tail] = drive_t1;
      expected_t2[queue_tail] = drive_t2;
      expected_l[queue_tail] = drive_l;
      expected_m[queue_tail] = drive_m;
      expected_h[queue_tail] = drive_h;
      expected_duty_u[queue_tail] = drive_duty_u;
      expected_duty_v[queue_tail] = drive_duty_v;
      expected_duty_w[queue_tail] = drive_duty_w;
      expected_id[queue_tail] = drive_id;
      expected_edge[queue_tail] = edge_number;
      queue_tail = (queue_tail + 1) % QUEUE_DEPTH;
      queue_count = queue_count + 1;
      accepted_count = accepted_count + 1;
    end
  endtask

  task automatic check_response;
    integer latency;
    begin
      if (queue_count == 0)
        fail("output_valid without an accepted transaction");
      latency = edge_number - expected_edge[queue_head];
      if (latency != 128)
        fail($sformatf("id=%h latency=%0d expected=128",
                       expected_id[queue_head], latency));
      if ($isunknown({duty_u, duty_v, duty_w, sector,
                      overmodulated, error_code,
                      dut.a_num_debug, dut.b_num_debug,
                      dut.sum_num_debug, dut.base_debug,
                      dut.denominator_debug, dut.t1_debug, dut.t2_debug,
                      dut.l_debug, dut.m_debug, dut.h_debug}))
        fail($sformatf("id=%h response contains X/Z", expected_id[queue_head]));
      if ((sector !== expected_sector[queue_head]) ||
          (overmodulated !== expected_overmodulated[queue_head]) ||
          (error_code !== expected_error_code[queue_head]) ||
          (duty_u !== expected_duty_u[queue_head]) ||
          (duty_v !== expected_duty_v[queue_head]) ||
          (duty_w !== expected_duty_w[queue_head]) ||
          (dut.a_num_debug !== expected_a_num[queue_head]) ||
          (dut.b_num_debug !== expected_b_num[queue_head]) ||
          (dut.sum_num_debug !== expected_sum_num[queue_head]) ||
          (dut.base_debug !== expected_base[queue_head]) ||
          (dut.denominator_debug !== expected_denominator[queue_head]) ||
          (dut.t1_debug !== expected_t1[queue_head]) ||
          (dut.t2_debug !== expected_t2[queue_head]) ||
          (dut.l_debug !== expected_l[queue_head]) ||
          (dut.m_debug !== expected_m[queue_head]) ||
          (dut.h_debug !== expected_h[queue_head]))
        fail($sformatf("bit-exact response mismatch id=%h tag-sector=%0d error=%0d",
                       expected_id[queue_head], expected_sector[queue_head],
                       expected_error_code[queue_head]));
      queue_head = (queue_head + 1) % QUEUE_DEPTH;
      queue_count = queue_count - 1;
      response_count = response_count + 1;
    end
  endtask

  // Sample the handshake in the active region, then observe DUT NBA outputs.
  initial begin
    forever begin
      @(posedge clk);
      edge_number = edge_number + 1;
      accepted_now = reset_n && input_valid && input_ready;
      #1;
      if (!reset_n) begin
        clear_queue();
        if (output_valid !== 1'b0)
          fail("output_valid asserted during reset");
      end else begin
        if (accepted_now)
          enqueue_expected();
        if (output_valid)
          check_response();
      end
    end
  end

  task automatic run_transaction(
    input logic signed [24:0] next_alpha,
    input logic signed [24:0] next_beta,
    input logic signed [24:0] next_vdc
  );
    integer target_response;
    integer timeout;
    begin
      @(negedge clk);
      while (!input_ready)
        @(negedge clk);
      target_response = response_count + 1;
      v_alpha = next_alpha;
      v_beta = next_beta;
      vdc = next_vdc;
      input_valid = 1'b1;
      @(negedge clk);
      input_valid = 1'b0;
      timeout = 0;
      while (response_count < target_response) begin
        // Poison live input buses while busy; the accepted transaction must
        // depend only on the captured sample. Keep input_valid hostile too;
        // input_ready must prevent an additional acceptance while occupied.
        input_valid = 1'b1;
        v_alpha = $signed(25'h1555555 ^ timeout[24:0]);
        v_beta = $signed(25'h0aaaaaa ^ {timeout[23:0], 1'b0});
        vdc = $signed(25'h0000001 + timeout[24:0]);
        poisoned_cycles = poisoned_cycles + 1;
        timeout = timeout + 1;
        if (timeout > 132)
          fail($sformatf("timeout waiting for id=%h", drive_id));
        @(negedge clk);
      end
      input_valid = 1'b0;
    end
  endtask

  task automatic reset_abort_probe;
    integer prior_responses;
    integer i;
    begin
      drive_id = 32'hffff0001;
      drive_sector = 3'd2;
      drive_overmodulated = 1'b0;
      drive_error_code = 2'b00;
      drive_a_num = '0;
      drive_b_num = '0;
      drive_sum_num = '0;
      drive_base = 39'sd1000000;
      drive_denominator = 41'sd1000000;
      drive_t1 = '0;
      drive_t2 = '0;
      drive_l = 34'sd2147483648;
      drive_m = 34'sd2147483648;
      drive_h = 34'sd2147483648;
      drive_duty_u = 26'sd8388608;
      drive_duty_v = 26'sd8388608;
      drive_duty_w = 26'sd8388608;
      prior_responses = response_count;

      @(negedge clk);
      while (!input_ready)
        @(negedge clk);
      v_alpha = 25'sd0;
      v_beta = 25'sd0;
      vdc = 25'sd100;
      input_valid = 1'b1;
      @(negedge clk);
      input_valid = 1'b0;
      repeat (20) @(negedge clk);
      reset_n = 1'b0;
      abort_count = abort_count + 1;
      #3;
      if (input_ready !== 1'b0 || output_valid !== 1'b0 ||
          duty_u !== '0 || duty_v !== '0 || duty_w !== '0 ||
          sector !== '0 || overmodulated !== 1'b0 || error_code !== 2'b00)
        fail("asynchronous reset did not clear visible state");
      repeat (2) @(negedge clk);
      reset_n = 1'b1;
      for (i = 0; i < 140; i = i + 1) begin
        @(posedge clk);
        #2;
        if (output_valid)
          fail("stale response after reset-aborted transaction");
      end
      if (response_count != prior_responses)
        fail("reset-aborted transaction was counted as a response");
    end
  endtask

  task automatic load_and_run_fixture(input string vector_dir);
    string path;
    string line;
    string token;
    string tok [0:FIXTURE_FIELDS-1];
    logic [31:0] parsed_id;
    logic [15:0] parsed_tag;
    logic signed [24:0] parsed_alpha;
    logic signed [24:0] parsed_beta;
    logic signed [24:0] parsed_vdc;
    logic [2:0] parsed_sector;
    logic parsed_overmodulated;
    logic [1:0] parsed_error_code;
    logic signed [39:0] parsed_a_num;
    logic signed [39:0] parsed_b_num;
    logic signed [40:0] parsed_sum_num;
    logic signed [38:0] parsed_base;
    logic signed [40:0] parsed_denominator;
    logic signed [33:0] parsed_t1;
    logic signed [33:0] parsed_t2;
    logic signed [33:0] parsed_l;
    logic signed [33:0] parsed_m;
    logic signed [33:0] parsed_h;
    logic signed [25:0] parsed_duty_u;
    logic signed [25:0] parsed_duty_v;
    logic signed [25:0] parsed_duty_w;
    logic [31:0] canonical_id;
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
      path = {vector_dir, "/svpwm_vectors.txt"};
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
            // XSim 2026.1 can native-crash on string.getc and missing
            // multi-string sscanf destinations. Tokenize indexed bytes.
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
                !valid_lower_hex(tok[5], 1, 3) ||
                !valid_lower_hex(tok[6], 1, 1) ||
                !valid_lower_hex(tok[7], 1, 2) ||
                !valid_lower_hex(tok[8], 10, 40) ||
                !valid_lower_hex(tok[9], 10, 40) ||
                !valid_lower_hex(tok[10], 11, 41) ||
                !valid_lower_hex(tok[11], 10, 39) ||
                !valid_lower_hex(tok[12], 11, 41) ||
                !valid_lower_hex(tok[13], 9, 34) ||
                !valid_lower_hex(tok[14], 9, 34) ||
                !valid_lower_hex(tok[15], 9, 34) ||
                !valid_lower_hex(tok[16], 9, 34) ||
                !valid_lower_hex(tok[17], 9, 34) ||
                !valid_lower_hex(tok[18], 7, 26) ||
                !valid_lower_hex(tok[19], 7, 26) ||
                !valid_lower_hex(tok[20], 7, 26))
              fail($sformatf("fixture lexical/width failure at line %0d", line_number));
            if (($sscanf(tok[0], "%h", parsed_id) != 1) ||
                ($sscanf(tok[1], "%h", parsed_tag) != 1) ||
                ($sscanf(tok[2], "%h", parsed_alpha) != 1) ||
                ($sscanf(tok[3], "%h", parsed_beta) != 1) ||
                ($sscanf(tok[4], "%h", parsed_vdc) != 1) ||
                ($sscanf(tok[5], "%h", parsed_sector) != 1) ||
                ($sscanf(tok[6], "%h", parsed_overmodulated) != 1) ||
                ($sscanf(tok[7], "%h", parsed_error_code) != 1) ||
                ($sscanf(tok[8], "%h", parsed_a_num) != 1) ||
                ($sscanf(tok[9], "%h", parsed_b_num) != 1) ||
                ($sscanf(tok[10], "%h", parsed_sum_num) != 1) ||
                ($sscanf(tok[11], "%h", parsed_base) != 1) ||
                ($sscanf(tok[12], "%h", parsed_denominator) != 1) ||
                ($sscanf(tok[13], "%h", parsed_t1) != 1) ||
                ($sscanf(tok[14], "%h", parsed_t2) != 1) ||
                ($sscanf(tok[15], "%h", parsed_l) != 1) ||
                ($sscanf(tok[16], "%h", parsed_m) != 1) ||
                ($sscanf(tok[17], "%h", parsed_h) != 1) ||
                ($sscanf(tok[18], "%h", parsed_duty_u) != 1) ||
                ($sscanf(tok[19], "%h", parsed_duty_v) != 1) ||
                ($sscanf(tok[20], "%h", parsed_duty_w) != 1))
              fail($sformatf("fixture numeric conversion failure at line %0d", line_number));

            canonical_id = (rows < 22) ? (rows + 1) : (32'h1000 + rows - 22);
            if (parsed_id !== canonical_id)
              fail($sformatf("fixture id %h at row %0d expected %h",
                             parsed_id, rows, canonical_id));
            if ((rows < 22 && parsed_tag !== rows + 1) ||
                (rows >= 22 && parsed_tag !== 0))
              fail($sformatf("fixture tag %h at row %0d is not canonical",
                             parsed_tag, rows));
            if (parsed_tag <= 22)
              seen_tag[parsed_tag] = 1'b1;

            drive_id = parsed_id;
            drive_sector = parsed_sector;
            drive_overmodulated = parsed_overmodulated;
            drive_error_code = parsed_error_code;
            drive_a_num = parsed_a_num;
            drive_b_num = parsed_b_num;
            drive_sum_num = parsed_sum_num;
            drive_base = parsed_base;
            drive_denominator = parsed_denominator;
            drive_t1 = parsed_t1;
            drive_t2 = parsed_t2;
            drive_l = parsed_l;
            drive_m = parsed_m;
            drive_h = parsed_h;
            drive_duty_u = parsed_duty_u;
            drive_duty_v = parsed_duty_v;
            drive_duty_w = parsed_duty_w;
            run_transaction(parsed_alpha, parsed_beta, parsed_vdc);
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
    clk = 1'b0;
    reset_n = 1'b0;
    input_valid = 1'b0;
    v_alpha = '0;
    v_beta = '0;
    vdc = '0;
    edge_number = 0;
    accepted_count = 0;
    response_count = 0;
    poisoned_cycles = 0;
    abort_count = 0;
    clear_queue();
    for (i = 0; i <= 22; i = i + 1)
      seen_tag[i] = 1'b0;
    if (!$value$plusargs("VECTOR_DIR=%s", vector_dir))
      vector_dir = "motor_control_ip/foc/tb/vectors/step6c3";

    repeat (3) @(negedge clk);
    reset_n = 1'b1;
    reset_abort_probe();
    load_and_run_fixture(vector_dir);
    if (accepted_count != FIXTURE_ROWS + 1)
      fail($sformatf("accepted count %0d expected %0d",
                     accepted_count, FIXTURE_ROWS + 1));
    if (response_count != FIXTURE_ROWS)
      fail($sformatf("response count %0d expected %0d",
                     response_count, FIXTURE_ROWS));
    if (queue_count != 0)
      fail("scoreboard queue not empty at completion");
    if (poisoned_cycles < FIXTURE_ROWS * 120)
      fail("busy-time input poisoning did not cover every fixture transaction");
    if (abort_count != 1)
      fail("reset-abort probe count mismatch");
    $display("ALL STEP 6C3 SECTOR SVPWM TESTS PASSED rows=%0d accepted=%0d responses=%0d latency=128 aborts=%0d poisoned_cycles=%0d",
             FIXTURE_ROWS, accepted_count, response_count, abort_count,
             poisoned_cycles);
    $finish;
  end
endmodule
