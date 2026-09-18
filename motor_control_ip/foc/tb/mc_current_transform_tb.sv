`timescale 1ns/1ps
module mc_current_transform_tb;
  logic clk=0, reset_n=0, input_valid=0;
  always #10 clk=~clk;
  logic signed [23:0] ia=0, ib=0, ic=0;
  logic [15:0] theta_e=0;
  wire output_valid;
  wire signed [24:0] i_alpha_dbg, i_beta_dbg, id, iq;
  wire signed [17:0] sin_theta_dbg, cos_theta_dbg;
  mc_current_transform dut(.*);
  integer vec[0:255][0:10];
  integer queue_row[0:1023], queue_edge[0:1023], queue_id[0:1023];
  integer head=0, tail=0, edge_index=0, selected=0, checked=0, flushed=0;
  integer latency=-1, fd, fields, rows=0, scratch[0:10];
  integer seen[0:255];
  string vector_dir, line;

  always @(negedge reset_n) begin
    flushed=flushed+tail-head;
    head=0; tail=0;
  end
  always @(posedge clk) begin : scoreboard
    integer row, elapsed;
    edge_index=edge_index+1;
    if (reset_n && input_valid) begin
      queue_row[tail]=selected;
      queue_id[tail]=vec[selected][0];
      queue_edge[tail]=edge_index;
      tail=tail+1;
    end
    #1;
    if (!reset_n) begin
      if (output_valid !== 1'b0) $fatal(1,"valid during reset");
    end else begin
      if (output_valid !== 1'b0 && output_valid !== 1'b1)
        $fatal(1,"unknown output_valid at edge %0d",edge_index);
      if (output_valid === 1'b1) begin
        if (head>=tail) $fatal(1,"extra output at edge %0d",edge_index);
        row=queue_row[head]; elapsed=edge_index-queue_edge[head];
        if (latency<0) latency=elapsed;
        if (elapsed!=latency || elapsed!=5 || elapsed>=32)
          $fatal(1,"transaction %0d latency %0d expected %0d",queue_id[head],elapsed,latency);
        if ($signed(i_alpha_dbg) !== vec[row][5] || $signed(i_beta_dbg) !== vec[row][6] ||
            $signed(sin_theta_dbg) !== vec[row][7] || $signed(cos_theta_dbg) !== vec[row][8] ||
            $signed(id) !== vec[row][9] || $signed(iq) !== vec[row][10])
          $fatal(1,"transaction %0d field mismatch input edge %0d output edge %0d: got %0d %0d %0d %0d %0d %0d expected %0d %0d %0d %0d %0d %0d",
            queue_id[head],queue_edge[head],edge_index,i_alpha_dbg,i_beta_dbg,sin_theta_dbg,cos_theta_dbg,id,iq,
            vec[row][5],vec[row][6],vec[row][7],vec[row][8],vec[row][9],vec[row][10]);
        seen[row]=seen[row]+1; checked=checked+1; head=head+1;
      end
      if (head<tail && edge_index-queue_edge[head]>=32)
        $fatal(1,"missing transaction %0d",queue_id[head]);
    end
  end
  task automatic drive(input integer row, input bit valid);
    @(negedge clk);
    selected=row; input_valid=valid;
    ia=vec[row][1]; ib=vec[row][2]; ic=vec[row][3]; theta_e=vec[row][4];
  endtask
  initial begin
    for (integer n=0;n<256;n=n+1) seen[n]=0;
    if (!$value$plusargs("VECTOR_DIR=%s",vector_dir)) vector_dir="motor_control_ip/foc/tb/vectors";
    fd=$fopen({vector_dir,"/current_transform_transactions.txt"},"r");
    if (!fd) $fatal(1,"cannot open transaction fixture in %s",vector_dir);
    while ($fgets(line,fd)) begin
      if (line.len()>0 && line.substr(0,0)!="#") begin
        fields=$sscanf(line,"%d %d %d %d %d %d %d %d %d %d %d",scratch[0],scratch[1],scratch[2],scratch[3],scratch[4],scratch[5],scratch[6],scratch[7],scratch[8],scratch[9],scratch[10]);
        if (fields!=11 || rows>=256) $fatal(1,"bad fixture row %0d",rows);
        for (integer c=0;c<11;c=c+1) vec[rows][c]=scratch[c];
        for (integer n=0;n<rows;n=n+1)
          if (vec[n][0]==scratch[0]) $fatal(1,"duplicate transaction ID");
        rows=rows+1;
      end
    end
    $fclose(fd);
    if (rows!=256) $fatal(1,"expected 160 Step6A + 96 unique rows, got %0d",rows);
    for (integer n=161;n<256;n=n+1)
      if (vec[n][4]==vec[n-1][4] ||
          (vec[n][1]==vec[n-1][1] && vec[n][2]==vec[n-1][2] && vec[n][3]==vec[n-1][3]))
        $fatal(1,"continuous fixture must change angle and current");
    repeat(3) @(negedge clk);
    reset_n=1;
    // Four in-flight transactions are reset before the first output is due.
    for (integer n=0;n<4;n=n+1) drive(n,1);
    @(negedge clk); input_valid=0;
    #2 reset_n=0;
    #1 if (output_valid !== 1'b0) $fatal(1,"asynchronous reset failed");
    repeat(3) @(negedge clk);
    reset_n=1;
    repeat(8) @(negedge clk);
    // 96 changing transactions without bubbles establish one-per-clock throughput.
    for (integer n=160;n<256;n=n+1) drive(n,1);
    for (integer n=0;n<160;n=n+1) begin
      if (n%3==0) drive(255-n,0);
      if (n%11==0) drive(n,0);
      drive(n,1);
    end
    drive(0,0);
    repeat(35) @(negedge clk);
    if (head!=tail || checked!=256 || flushed!=4)
      $fatal(1,"counts checked=%0d flushed=%0d pending=%0d",checked,flushed,tail-head);
    for (integer n=0;n<256;n=n+1)
      if (seen[n]!=1) $fatal(1,"row %0d missing or duplicated",n);
    $display("Rows=256 (Step6A=160 unique=96), checked=%0d reset-flushed=%0d continuous=96",checked,flushed);
    $display("Measured deterministic acceptance-edge to output-edge latency=%0d clocks (<32)",latency);
    $display("All six fields bit-exact; bubbles/reset recovery/extra/missing/reordering checked");
    $display("ALL STEP 6C1 TRANSFORM TESTS PASSED");
    $finish;
  end
  initial begin #100000; $fatal(1,"watchdog timeout"); end
endmodule
