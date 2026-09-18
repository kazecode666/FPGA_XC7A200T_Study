`timescale 1ns/1ps

module mc_clarke_tb;
  import mc_fxp_pkg::*;

  localparam int MAX_VECTORS = 512;
  localparam int LATENCY_EDGES = 2;

  logic clk = 1'b0;
  logic reset_n = 1'b0;
  logic input_valid = 1'b0;
  logic signed [23:0] ia = '0;
  logic signed [23:0] ib = '0;
  logic signed [23:0] ic = '0;
  logic output_valid;
  logic signed [24:0] i_alpha;
  logic signed [24:0] i_beta;

  integer vec_ia [0:MAX_VECTORS-1];
  integer vec_ib [0:MAX_VECTORS-1];
  integer vec_ic [0:MAX_VECTORS-1];
  integer vec_alpha [0:MAX_VECTORS-1];
  integer vec_beta [0:MAX_VECTORS-1];
  integer vector_count = 0;

  integer exp_alpha [0:MAX_VECTORS-1];
  integer exp_beta [0:MAX_VECTORS-1];
  integer exp_id [0:MAX_VECTORS-1];
  integer exp_due [0:MAX_VECTORS-1];
  integer head = 0;
  integer tail = 0;
  integer next_id = 0;
  integer edge_index = 0;
  integer checked = 0;

  mc_clarke dut (
    .clk(clk), .reset_n(reset_n), .input_valid(input_valid),
    .ia(ia), .ib(ib), .ic(ic),
    .output_valid(output_valid), .i_alpha(i_alpha), .i_beta(i_beta)
  );

  always #10 clk = ~clk;

  task automatic fail(input string message);
    begin
      $fatal(1, "CLARKE_TB_FAIL: %s", message);
    end
  endtask

  task automatic check_helpers;
    logic signed [43:0] x44;
    begin
      if (fxp_round_shift16_s44(44'sd32767) !== 44'sd0) fail("positive tie-1");
      if (fxp_round_shift16_s44(44'sd32768) !== 44'sd1) fail("positive tie");
      if (fxp_round_shift16_s44(44'sd32769) !== 44'sd1) fail("positive tie+1");
      if (fxp_round_shift16_s44(-44'sd32767) !== 44'sd0) fail("negative tie+1 toward zero");
      if (fxp_round_shift16_s44(-44'sd32768) !== -44'sd1) fail("negative tie");
      if (fxp_round_shift16_s44(-44'sd32769) !== -44'sd1) fail("negative tie-1");
      if (fxp_round_shift16_s44(44'sd8060928) !== 44'sd123) fail("exact positive multiple");
      if (fxp_round_shift16_s44(-44'sd8060928) !== -44'sd123) fail("exact negative multiple");
      x44 = {1'b1, {43{1'b0}}};
      if (fxp_round_shift16_s44(x44) !== -44'sd134217728) fail("signed-44 minimum");
      if (fxp_sat_s25(44'sd1073741824) !== 25'sd16777215) fail("signed-25 positive saturation");
      if (fxp_sat_s25(-44'sd1073741824) !== -25'sd16777216) fail("signed-25 negative saturation");
      if (fxp_half_away_s25(25'sd3) !== 25'sd2) fail("positive odd divide");
      if (fxp_half_away_s25(-25'sd3) !== -25'sd2) fail("negative odd divide");
      if (fxp_half_away_s25(25'sd2) !== 25'sd1) fail("positive even divide");
      if (fxp_half_away_s25(-25'sd2) !== -25'sd1) fail("negative even divide");
    end
  endtask

  task automatic load_vectors;
    string vector_dir;
    string vector_file;
    string line;
    integer fd;
    integer fields;
    integer line_status;
    begin
      if (!$value$plusargs("VECTOR_DIR=%s", vector_dir))
        vector_dir = "motor_control_ip/foc/tb/vectors";
      vector_file = {vector_dir, "/clarke_vectors.txt"};
      fd = $fopen(vector_file, "r");
      if (fd == 0) fail($sformatf("cannot open %s", vector_file));
      while (!$feof(fd)) begin
        line = "";
        line_status = $fgets(line, fd);
        fields = $sscanf(line, "%d %d %d %d %d",
                         vec_ia[vector_count], vec_ib[vector_count],
                         vec_ic[vector_count], vec_alpha[vector_count],
                         vec_beta[vector_count]);
        if (fields == 5) begin
          vector_count = vector_count + 1;
          if (vector_count >= MAX_VECTORS) fail("too many fixture rows");
        end
      end
      $fclose(fd);
      if (vector_count == 0) fail("no Clarke fixture rows read");
    end
  endtask

  task automatic drive(input integer index, input bit valid);
    begin
      @(negedge clk);
      input_valid = valid;
      if (valid) begin
        ia = vec_ia[index]; ib = vec_ib[index]; ic = vec_ic[index];
        exp_alpha[tail] = vec_alpha[index]; exp_beta[tail] = vec_beta[index];
        exp_id[tail] = next_id; exp_due[tail] = edge_index + 1 + LATENCY_EDGES;
        tail = tail + 1; next_id = next_id + 1;
      end else begin
        ia = '0; ib = '0; ic = '0;
      end
    end
  endtask

  always @(posedge clk) begin
    edge_index = edge_index + 1;
    #1;
    if (!reset_n) begin
      head = 0; tail = 0;
      if (output_valid !== 1'b0) fail("output_valid not cleared asynchronously");
    end else begin
      if (output_valid) begin
        if (head >= tail) fail("unexpected output transaction");
        if (edge_index != exp_due[head])
          fail($sformatf("transaction %0d latency: due edge %0d got %0d",
                         exp_id[head], exp_due[head], edge_index));
        if ($signed(i_alpha) !== exp_alpha[head] || $signed(i_beta) !== exp_beta[head])
          fail($sformatf("transaction %0d mismatch got (%0d,%0d) expected (%0d,%0d)",
                         exp_id[head], $signed(i_alpha), $signed(i_beta),
                         exp_alpha[head], exp_beta[head]));
        head = head + 1; checked = checked + 1;
      end else if ((head < tail) && (edge_index == exp_due[head])) begin
        fail($sformatf("transaction %0d missing at fixed-latency edge", exp_id[head]));
      end
    end
  end

  initial begin
    integer k;
    check_helpers();
    load_vectors();

    repeat (2) @(negedge clk);
    reset_n = 1'b1;

    // Every checked-in fixture row is driven as a full-rate burst.
    for (k = 0; k < vector_count; k = k + 1) drive(k, 1'b1);
    drive(0, 1'b0); drive(0, 1'b0); drive(0, 1'b0);

    // Bubbles must propagate without creating or reordering transactions.
    for (k = 0; k < 8; k = k + 1) begin
      drive(k, 1'b1);
      drive(0, 1'b0);
    end
    drive(0, 1'b0); drive(0, 1'b0);

    // Assert reset while two transactions are in flight; neither may emerge.
    drive(0, 1'b1);
    drive(1, 1'b1);
    @(negedge clk); reset_n = 1'b0; input_valid = 1'b0; head = 0; tail = 0;
    #1;
    if (output_valid !== 1'b0) fail("asynchronous reset assertion did not clear valid");
    repeat (2) @(negedge clk);
    reset_n = 1'b1;
    drive(2, 1'b1);
    drive(3, 1'b1);
    drive(0, 1'b0); drive(0, 1'b0); drive(0, 1'b0);

    if (head != tail) fail("expected transaction queue not drained");
    if (checked != vector_count + 8 + 2)
      fail($sformatf("checked count %0d expected %0d", checked, vector_count + 10));
    $display("ALL STEP 6C1 CLARKE TESTS PASSED rows=%0d checked=%0d latency_edges=%0d",
             vector_count, checked, LATENCY_EDGES);
    $finish;
  end
endmodule
