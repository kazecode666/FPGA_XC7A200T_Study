`timescale 1ns/1ps
module mc_udiv_u72_u41_tb;
  localparam int ROWS=2058, LATENCY=72;
  logic clk=0, reset_n=0, input_valid=0;
  wire input_ready, output_valid;
  always #10 clk=~clk;
  int transactions=0, aborts=0;
  logic [71:0] numerator=0;
  logic [71:0] vec_numerator[0:ROWS-1];
  logic [40:0] denominator=0;
  logic [40:0] vec_denominator[0:ROWS-1];
  logic [71:0] quotient;
  logic [71:0] vec_quotient[0:ROWS-1];
  logic [40:0] remainder;
  logic [40:0] vec_remainder[0:ROWS-1];
  logic [0:0] div_by_zero;
  logic [0:0] vec_div_by_zero[0:ROWS-1];
  mc_udiv_u72_u41 dut(.*);
  task automatic fail(input string msg); $fatal(1,"MC_UDIV_U72_U41_FAIL: %s",msg); endtask
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
    string dir,line,extra,token;
    string t_id; logic [31:0] p_id;
    string t_numerator; logic [71:0] p_numerator;
    string t_denominator; logic [40:0] p_denominator;
    string t_quotient; logic [71:0] p_quotient;
    string t_remainder; logic [40:0] p_remainder;
    string t_div_by_zero; logic [0:0] p_div_by_zero;
    int fd,rc,count,headers,lineno,cols,idx,ch;
    begin
      if (!$value$plusargs("VECTOR_DIR=%s",dir)) dir="motor_control_ip/foc/tb/vectors/step6c2";
      fd=$fopen({dir,"/divider_vectors.txt"},"r"); if(!fd) fail("fixture open");
      count=0; headers=0; lineno=0;
      while(!$feof(fd)) begin
        line=""; rc=$fgets(line,fd);
        if(rc!=0) begin
          lineno++;
          if(line.len()>0 && line[0]==35) begin
            headers++; if(lineno!=1 || headers!=1) fail("header position/count");
          end else begin
            t_id=""; t_numerator=""; t_denominator=""; t_quotient=""; t_remainder=""; t_div_by_zero=""; extra="";
            // XSim 2026.1 crashes with seven string destinations in sscanf.
            // Tokenize whitespace explicitly; lexical checks below remain strict.
            cols=0; token="";
            for(idx=0;idx<=line.len();idx++) begin
              ch=(idx==line.len()) ? 32 : line[idx];
              if(ch==32 || ch==9 || ch==10 || ch==13) begin
                if(token.len()!=0) begin
                  case(cols)
                    0:t_id=token;
                    1:t_numerator=token;
                    2:t_denominator=token;
                    3:t_quotient=token;
                    4:t_remainder=token;
                    5:t_div_by_zero=token;
                    default:extra=token;
                  endcase
                  cols++; token="";
                end
              end else token={token,8'(ch)};
            end
            if(cols!=6 || count>=ROWS) fail("column/extra row count");
            if(!valid_lower_hex(t_id,8,32) || !valid_lower_hex(t_numerator,18,72) || !valid_lower_hex(t_denominator,11,41) || !valid_lower_hex(t_quotient,18,72) || !valid_lower_hex(t_remainder,11,41) || !valid_lower_hex(t_div_by_zero,1,1)) fail("lexical/width/high-padding");
            if($sscanf(t_id,"%h",p_id)!=1 || $sscanf(t_numerator,"%h",p_numerator)!=1 || $sscanf(t_denominator,"%h",p_denominator)!=1 || $sscanf(t_quotient,"%h",p_quotient)!=1 || $sscanf(t_remainder,"%h",p_remainder)!=1 || $sscanf(t_div_by_zero,"%h",p_div_by_zero)!=1) fail("conversion");
            if(p_id!==count) fail("duplicate/reordered/missing ID");
            vec_numerator[count]=p_numerator;
            vec_denominator[count]=p_denominator;
            vec_quotient[count]=p_quotient;
            vec_remainder[count]=p_remainder;
            vec_div_by_zero[count]=p_div_by_zero;
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
      held={quotient,remainder,div_by_zero}; internal_held={dut.count,dut.work_input,dut.work_result,dut.work_rem};
      repeat(cycles) begin
        @(negedge clk); input_valid=0;
        numerator=~numerator;
        denominator=~denominator;
        @(posedge clk); #1;
        if(input_ready!==1 || output_valid!==0 || {quotient,remainder,div_by_zero}!==held) fail("idle output/ready hold");
        if({dut.count,dut.work_input,dut.work_result,dut.work_rem}!==internal_held) fail("idle working state changed");
      end
    end
  endtask
  task automatic transact(input logic [71:0] a,input logic [40:0] b,input logic [71:0] expected, input logic [40:0] expected_rem, input logic expected_error);
    logic [255:0] held;
    logic [159:0] wide_a,wide_q,wide_d,wide_rem;
    int k;
    begin
      @(negedge clk); if(input_ready!==1) fail("not ready before accept");
      numerator=a; denominator=b; input_valid=1; held={quotient,remainder,div_by_zero};
      @(posedge clk); #1; if(input_ready!==0 || output_valid!==0) fail("accept edge protocol");
      for(k=1;k<=LATENCY;k++) begin
        @(negedge clk); input_valid=1;
        numerator=~numerator;
        denominator=~denominator;
        if(input_ready!==0) fail("ready before completion");
        @(posedge clk); #1;
        if(k<LATENCY) begin
          if(output_valid!==0 || input_ready!==0 || {quotient,remainder,div_by_zero}!==held) fail("early response/data change");
        end else begin
          if(output_valid!==1 || input_ready!==1) fail("fixed latency response");
          if(quotient!==expected || remainder!==expected_rem || div_by_zero!==expected_error) fail("result mismatch");
          wide_a=a; wide_rem=remainder;
          wide_q=quotient; wide_d=b;
          if(b!=0 && (wide_q*wide_d+wide_rem!=wide_a || wide_rem>=wide_d)) fail("division invariant");
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
      numerator=100; denominator=7;
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
        if(quotient!==72'd14 || remainder!==41'd2 || div_by_zero!==0) fail("held-valid arithmetic");
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
      numerator=72'hffffffffffffffffff; denominator=41'd17;
      @(posedge clk); #1;
      repeat(phase) begin @(posedge clk); #1; end
      #2; reset_n=0; #1;
      if(input_ready!==0 || output_valid!==0 || {quotient,remainder,div_by_zero}!==0) fail("asynchronous abort/reset outputs");
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
      transact(vec_numerator[i],vec_denominator[i],vec_quotient[i],vec_remainder[i],vec_div_by_zero[i]);
    for(i=0;i<64;i++) for(j=0;j<32;j++) begin
      eq=(j==0)?0:i/j; er=(j==0)?0:i%j; transact(i,j,eq,er,j==0);
    end
    // Replay identical accepted inputs with varied idle gaps.
    for(i=0;i<16;i++) begin
      idle_check(i%7);
      transact(vec_numerator[i],vec_denominator[i],vec_quotient[i],vec_remainder[i],vec_div_by_zero[i]);
    end
    held_valid_pair();
    for(i=0;i<LATENCY;i++) abort_at(i);
    transact(72'hffffffffffffffffff,41'd1,72'hffffffffffffffffff,0,0);
    $display("ALL STEP 6C2 DIVIDER TESTS PASSED fixture_rows=%0d transactions=%0d aborts=%0d idle_clocks=5000",ROWS,transactions,aborts);
    $finish;
  end
  initial begin #20000000; fail("watchdog"); end
endmodule
