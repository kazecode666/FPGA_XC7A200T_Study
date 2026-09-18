`timescale 1ns/1ps

module mc_sincos_lut_tb;
  localparam int PHASE_COUNT = 65536;
  localparam int QUEUE_DEPTH = PHASE_COUNT + 64;
  localparam int LATENCY_EDGES = 1;
  localparam real TWO_PI = 6.283185307179586476925286766559;

  logic clk = 1'b0;
  logic reset_n = 1'b0;
  logic input_valid = 1'b0;
  logic [15:0] theta_e = '0;
  logic output_valid;
  logic signed [17:0] sin_theta;
  logic signed [17:0] cos_theta;

  integer fixture_sin [0:PHASE_COUNT-1];
  integer fixture_cos [0:PHASE_COUNT-1];
  integer expected_theta [0:QUEUE_DEPTH-1];
  integer expected_sin [0:QUEUE_DEPTH-1];
  integer expected_cos [0:QUEUE_DEPTH-1];
  integer expected_due [0:QUEUE_DEPTH-1];
  integer head = 0;
  integer tail = 0;
  integer edge_index = 0;
  integer checked = 0;
  real max_sin_error = 0.0;
  real max_cos_error = 0.0;

  mc_sincos_lut dut (
    .clk(clk), .reset_n(reset_n), .input_valid(input_valid), .theta_e(theta_e),
    .output_valid(output_valid), .sin_theta(sin_theta), .cos_theta(cos_theta)
  );

  always #10 clk = ~clk;

  task automatic fail(input string message);
    begin
      $fatal(1, "SINCOS_TB_FAIL: %s", message);
    end
  endtask

  task automatic load_vectors;
    string vector_dir;
    string vector_file;
    string line;
    integer fd;
    integer fields;
    integer line_status;
    integer row;
    integer phase;
    integer sin_raw;
    integer cos_raw;
    begin
      if (!$value$plusargs("VECTOR_DIR=%s", vector_dir))
        vector_dir = "motor_control_ip/foc/tb/vectors";
      vector_file = {vector_dir, "/sincos_all_phases.txt"};
      fd = $fopen(vector_file, "r");
      if (fd == 0) fail($sformatf("cannot open %s", vector_file));
      row = 0;
      while (!$feof(fd)) begin
        line = "";
        line_status = $fgets(line, fd);
        fields = $sscanf(line, "%d %d %d", phase, sin_raw, cos_raw);
        if (fields == 3) begin
          if (row >= PHASE_COUNT) fail("too many fixture rows");
          if (phase != row)
            fail($sformatf("fixture phase/order mismatch row=%0d phase=%0d", row, phase));
          fixture_sin[row] = sin_raw;
          fixture_cos[row] = cos_raw;
          row = row + 1;
        end
      end
      $fclose(fd);
      if (row != PHASE_COUNT)
        fail($sformatf("fixture row count %0d expected %0d", row, PHASE_COUNT));
    end
  endtask

  task automatic require_fixture(input integer phase, input integer sin_raw, input integer cos_raw);
    begin
      if ((fixture_sin[phase] != sin_raw) || (fixture_cos[phase] != cos_raw))
        fail($sformatf("fixture directed phase=%04h got (%0d,%0d) expected (%0d,%0d)",
                       phase, fixture_sin[phase], fixture_cos[phase], sin_raw, cos_raw));
    end
  endtask

  task automatic check_directed_fixture;
    begin
      require_fixture(16'h0000,      0,  65536);
      require_fixture(16'h4000,  65536,      0);
      require_fixture(16'h8000,      0, -65536);
      require_fixture(16'hC000, -65536,      0);

      // Lowest two phase bits are intentionally ignored.
      require_fixture(16'h0001, fixture_sin[16'h0000], fixture_cos[16'h0000]);
      require_fixture(16'h0002, fixture_sin[16'h0000], fixture_cos[16'h0000]);
      require_fixture(16'h0003, fixture_sin[16'h0000], fixture_cos[16'h0000]);
      require_fixture(16'hFFFF, fixture_sin[16'hFFFC], fixture_cos[16'hFFFC]);

      // q=1, q=4094, q=4095 and both sides of all quadrant boundaries.
      if (fixture_sin[16'h0004] == fixture_sin[16'h0000]) fail("q=1 did not advance");
      if (fixture_sin[16'h3FF8] <= 0 || fixture_sin[16'h3FFC] <= 0) fail("quarter endpoint neighbors invalid");
      if (fixture_cos[16'h3FFC] <= 0) fail("q=4095 cosine must remain positive in quadrant 0");
      require_fixture(16'h3FFF, fixture_sin[16'h3FFC], fixture_cos[16'h3FFC]);
      require_fixture(16'h4001, fixture_sin[16'h4000], fixture_cos[16'h4000]);
      require_fixture(16'h7FFF, fixture_sin[16'h7FFC], fixture_cos[16'h7FFC]);
      require_fixture(16'h8001, fixture_sin[16'h8000], fixture_cos[16'h8000]);
      require_fixture(16'hBFFF, fixture_sin[16'hBFFC], fixture_cos[16'hBFFC]);
      require_fixture(16'hC001, fixture_sin[16'hC000], fixture_cos[16'hC000]);
    end
  endtask

  task automatic drive_phase(input integer phase, input bit valid);
    begin
      @(negedge clk);
      input_valid = valid;
      if (valid) begin
        theta_e = phase[15:0];
        if (tail >= QUEUE_DEPTH) fail("expected queue overflow");
        expected_theta[tail] = phase;
        expected_sin[tail] = fixture_sin[phase];
        expected_cos[tail] = fixture_cos[phase];
        expected_due[tail] = edge_index + 1 + LATENCY_EDGES;
        tail = tail + 1;
      end else begin
        theta_e = 16'hA5A5;
      end
    end
  endtask

  always @(posedge clk) begin
    real angle;
    real sin_error;
    real cos_error;
    edge_index = edge_index + 1;
    #1;
    if (!reset_n) begin
      head = 0;
      tail = 0;
      if (output_valid !== 1'b0) fail("output_valid not cleared asynchronously");
    end else begin
      if (output_valid) begin
        if (head >= tail) fail("unexpected output transaction");
        if (edge_index != expected_due[head])
          fail($sformatf("phase=%04h latency due edge %0d got %0d",
                         expected_theta[head], expected_due[head], edge_index));
        if (($signed(sin_theta) !== expected_sin[head]) ||
            ($signed(cos_theta) !== expected_cos[head]))
          fail($sformatf("phase=%04h got (%0d,%0d) expected (%0d,%0d)",
                         expected_theta[head], $signed(sin_theta), $signed(cos_theta),
                         expected_sin[head], expected_cos[head]));

        angle = TWO_PI * expected_theta[head] / 65536.0;
        sin_error = ($itor($signed(sin_theta)) / 65536.0) - $sin(angle);
        cos_error = ($itor($signed(cos_theta)) / 65536.0) - $cos(angle);
        if (sin_error < 0.0) sin_error = -sin_error;
        if (cos_error < 0.0) cos_error = -cos_error;
        if (sin_error > max_sin_error) max_sin_error = sin_error;
        if (cos_error > max_cos_error) max_cos_error = cos_error;
        if ((sin_error > 5.0e-4) || (cos_error > 5.0e-4))
          fail($sformatf("phase=%04h ideal error sin=%e cos=%e",
                         expected_theta[head], sin_error, cos_error));
        head = head + 1;
        checked = checked + 1;
      end else if ((head < tail) && (edge_index == expected_due[head])) begin
        fail($sformatf("phase=%04h missing at fixed-latency edge", expected_theta[head]));
      end
    end
  end

  initial begin
    integer k;
    load_vectors();
    check_directed_fixture();

    repeat (2) @(negedge clk);
    reset_n = 1'b1;

    // Exact comparison against the Python fixture for every 16-bit phase word.
    for (k = 0; k < PHASE_COUNT; k = k + 1) drive_phase(k, 1'b1);
    drive_phase(0, 1'b0);
    drive_phase(0, 1'b0);

    // Gaps must preserve order and must not create transactions.
    for (k = 0; k < 8; k = k + 1) begin
      drive_phase((k * 16'h1F03) & 16'hFFFF, 1'b1);
      drive_phase(0, 1'b0);
    end
    drive_phase(0, 1'b0);
    drive_phase(0, 1'b0);

    // Reset flushes both stages, including transactions already read from ROM.
    drive_phase(16'h3FFC, 1'b1);
    @(negedge clk);
    reset_n = 1'b0;
    input_valid = 1'b0;
    head = 0;
    tail = 0;
    #1;
    if (output_valid !== 1'b0) fail("asynchronous reset assertion did not clear valid");
    repeat (2) @(negedge clk);
    reset_n = 1'b1;
    drive_phase(16'h0000, 1'b1);
    drive_phase(16'h4000, 1'b1);
    drive_phase(16'h8000, 1'b1);
    drive_phase(16'hC000, 1'b1);
    drive_phase(0, 1'b0);
    drive_phase(0, 1'b0);

    if (head != tail) fail("expected transaction queue not drained");
    if (checked != PHASE_COUNT + 8 + 4)
      fail($sformatf("checked count %0d expected %0d", checked, PHASE_COUNT + 12));
    $display("ALL STEP 6C1 SINCOS TESTS PASSED rows=%0d checked=%0d latency_edges=%0d max_sin_error=%e max_cos_error=%e",
             PHASE_COUNT, checked, LATENCY_EDGES, max_sin_error, max_cos_error);
    $finish;
  end
endmodule
