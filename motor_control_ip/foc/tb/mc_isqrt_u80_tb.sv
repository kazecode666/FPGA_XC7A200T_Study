`timescale 1ns/1ps
module mc_isqrt_u80_tb;
  localparam int ROWS=2078, LATENCY=40;
  logic clk=0, reset_n=0, input_valid=0;
  wire input_ready, output_valid;
  always #10 clk=~clk;
  int transactions=0, aborts=0;
  logic [79:0] radicand=0;
  logic [79:0] vec_radicand[0:ROWS-1];
  logic [39:0] root_floor;
  logic [39:0] vec_root_floor[0:ROWS-1];
  logic [40:0] remainder;
  logic [40:0] vec_remainder[0:ROWS-1];
  mc_isqrt_u80 dut(.*);
  task automatic fail(input string msg); $fatal(1,"MC_ISQRT_U80_FAIL: %s",msg); endtask
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

  task automatic load_vectors;
    string dir,line,extra;
    string t_id; logic [31:0] p_id;
    string t_radicand; logic [79:0] p_radicand;
    string t_root_floor; logic [39:0] p_root_floor;
    string t_remainder; logic [40:0] p_remainder;
    int fd,rc,count,headers,lineno,cols;
    begin
      if (!$value$plusargs("VECTOR_DIR=%s",dir)) dir="motor_control_ip/foc/tb/vectors/step6c2";
      fd=$fopen({dir,"/sqrt_vectors.txt"},"r"); if(!fd) fail("fixture open");
      count=0; headers=0; lineno=0;
      while(!$feof(fd)) begin
        line=""; rc=$fgets(line,fd);
        if(rc!=0) begin
          lineno++;
          if(line.len()>0 && line[0]==35) begin
            headers++; if(lineno!=1 || headers!=1) fail("header position/count");
          end else begin
            t_id=""; t_radicand=""; t_root_floor=""; t_remainder=""; extra="";
            cols=$sscanf(line,"%s %s %s %s %s",t_id,t_radicand,t_root_floor,t_remainder,extra);
            if(cols!=4 || count>=ROWS) fail("column/extra row count");
            if(!valid_lower_hex(t_id,8,32) || !valid_lower_hex(t_radicand,20,80) || !valid_lower_hex(t_root_floor,10,40) || !valid_lower_hex(t_remainder,11,41)) fail("lexical/width/high-padding");
            if($sscanf(t_id,"%h",p_id)!=1 || $sscanf(t_radicand,"%h",p_radicand)!=1 || $sscanf(t_root_floor,"%h",p_root_floor)!=1 || $sscanf(t_remainder,"%h",p_remainder)!=1) fail("conversion");
            if(p_id!==count) fail("duplicate/reordered/missing ID");
            vec_radicand[count]=p_radicand;
            vec_root_floor[count]=p_root_floor;
            vec_remainder[count]=p_remainder;
            count++;
          end
        end
      end
      $fclose(fd); if(count!=ROWS || headers!=1) fail("exact fixture/header count");
    end
  endtask
  task automatic idle_check(input int cycles);
    logic [255:0] held, internal_held;
    begin
      held={root_floor,remainder}; internal_held={dut.count,dut.work_input,dut.work_result,dut.work_rem};
      repeat(cycles) begin
        @(negedge clk); input_valid=0;
        radicand=~radicand;
        @(posedge clk); #1;
        if(input_ready!==1 || output_valid!==0 || {root_floor,remainder}!==held) fail("idle output/ready hold");
        if({dut.count,dut.work_input,dut.work_result,dut.work_rem}!==internal_held) fail("idle working state changed");
      end
    end
  endtask
  task automatic transact(input logic [79:0] a,input logic [71:0] expected, input logic [40:0] expected_rem, input logic expected_error);
    logic [255:0] held;
    logic [159:0] wide_a,wide_q,wide_d,wide_rem;
    int k;
    begin
      @(negedge clk); if(input_ready!==1) fail("not ready before accept");
      radicand=a; input_valid=1; held={root_floor,remainder};
      @(posedge clk); #1; if(input_ready!==0 || output_valid!==0) fail("accept edge protocol");
      for(k=1;k<=LATENCY;k++) begin
        @(negedge clk); input_valid=1;
        radicand=~radicand;
        if(input_ready!==0) fail("ready before completion");
        @(posedge clk); #1;
        if(k<LATENCY) begin
          if(output_valid!==0 || input_ready!==0 || {root_floor,remainder}!==held) fail("early response/data change");
        end else begin
          if(output_valid!==1 || input_ready!==1) fail("fixed latency response");
          if(root_floor!==expected[39:0] || remainder!==expected_rem) fail("result mismatch");
          wide_a=a; wide_rem=remainder;
          wide_q=root_floor;
          if(wide_q*wide_q>wide_a || (wide_q+160'd1)*(wide_q+160'd1)<=wide_a || wide_q*wide_q+wide_rem!=wide_a) fail("sqrt invariant");
        end
      end
      transactions++;
      // Busy valid was high on completion; dropping before next edge must leave idle.
      idle_check(2);
    end
  endtask
  // Keep valid continuously high: completion edge is excluded, next edge accepts.
  task automatic held_valid_pair;
    int run,k;
    begin
      @(negedge clk); input_valid=1;
      radicand=9;
      for(run=0;run<2;run++) begin
        @(posedge clk); #1;
        if(input_ready!==0 || output_valid!==0) fail("earliest next-edge acceptance");
        for(k=1;k<=LATENCY;k++) begin
          @(negedge clk);
          if(input_ready!==0) fail("held-valid busy ready");
          @(posedge clk); #1;
          if(k<LATENCY && output_valid!==0) fail("held-valid early/duplicate response");
        end
        if(output_valid!==1 || input_ready!==1) fail("held-valid completion slot");
        if(root_floor!==40'd3 || remainder!==0) fail("held-valid arithmetic");
        transactions++;
        // First iteration leaves valid high for immediate next-edge acceptance.
        @(negedge clk);
      end
      input_valid=0;
      idle_check(LATENCY+2);
    end
  endtask
  task automatic abort_at(input int phase);
    begin
      @(negedge clk); input_valid=1;
      radicand=80'hffffffffffffffffffff;
      @(posedge clk); #1;
      repeat(phase) begin @(posedge clk); #1; end
      #2; reset_n=0; #1;
      if(input_ready!==0 || output_valid!==0 || {root_floor,remainder}!==0) fail("asynchronous abort/reset outputs");
      @(negedge clk); input_valid=0;
      @(posedge clk); #1; if(input_ready!==0 || output_valid!==0) fail("reset ready gating");
      @(negedge clk); reset_n=1;
      idle_check(LATENCY+2); aborts++;
    end
  endtask
  initial begin
    int i,j,r;
    logic [71:0] eq,er;
    load_vectors();
    #1; if(input_ready!==0) fail("initial reset ready");
    repeat(2) @(negedge clk); reset_n=1;
    idle_check(5000);
    for(i=0;i<ROWS;i++)
      transact(vec_radicand[i],vec_root_floor[i],vec_remainder[i],0);
    r=0; for(i=0;i<4096;i++) begin
      if((r+1)*(r+1)<=i) r++; transact(i,r,i-r*r,0);
    end
    // Replay identical accepted inputs with varied idle gaps.
    for(i=0;i<16;i++) begin
      idle_check(i%7);
      transact(vec_radicand[i],vec_root_floor[i],vec_remainder[i],0);
    end
    held_valid_pair();
    for(i=0;i<LATENCY;i++) abort_at(i);
    transact(80'hffffffffffffffffffff,40'hffffffffff,41'h1fffffffffe,0);
    $display("ALL STEP 6C2 ISQRT TESTS PASSED fixture_rows=%0d transactions=%0d aborts=%0d idle_clocks=5000",ROWS,transactions,aborts);
    $finish;
  end
  initial begin #20000000; fail("watchdog"); end
endmodule
