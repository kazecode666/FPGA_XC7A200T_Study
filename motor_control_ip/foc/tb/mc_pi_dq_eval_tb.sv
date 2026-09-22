`timescale 1ns/1ps
module mc_pi_dq_eval_tb #(parameter int PI_PROFILE=0);
  localparam int ROWS=1042, PER_PROFILE=521, LATENCY=16, EXTRA=16;
  logic clk=0, reset_n=0, input_valid=0;
  wire input_ready, output_valid;
  always #10 clk=~clk;
  logic signed [24:0] id_meas=0, iq_meas=0, id_ref=0, iq_ref=0, vdc=0;
  logic signed [31:0] we=0;
  logic pi_reset=0, uq_zero_en=0;
  logic signed [39:0] xd_old=0,xq_old=0,du_d_old=0,du_q_old=0;
  logic signed [39:0] ud_raw,uq_raw,xd_next,xq_next;
  logic [1:0] error_code;
  logic [39:0] vec[0:ROWS+2*EXTRA-1][0:19];
  int transactions=0,aborts=0, current_case=-1;
  mc_pi_dq_eval #(.PI_PROFILE(PI_PROFILE)) dut(.*);
  task automatic fail(input string msg);
    $fatal(1,"MC_PI_DQ_EVAL_FAIL profile=%0d case=%0d: %s",PI_PROFILE,current_case,msg);
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


  function automatic int width_for(input int col);
    case(col)
      0,8,9,14: width_for=1;
      1,6: width_for=32;
      2,3,4,5,7: width_for=25;
      15: width_for=2;
      default: width_for=40;
    endcase
  endfunction
  task automatic load_vectors;
    string dir,line,token;
    int fd,rc,count,headers,lineno,cols,idx,ch,width;
    logic [39:0] parsed;
    begin
      if(!$value$plusargs("VECTOR_DIR=%s",dir)) dir="motor_control_ip/foc/tb/vectors/step6c2";
      fd=$fopen({dir,"/evaluator_vectors.txt"},"r"); if(!fd) fail("fixture open");
      count=0; headers=0; lineno=0;
      while(!$feof(fd)) begin
        line=""; rc=$fgets(line,fd);
        if(rc!=0) begin
          lineno++;
          if(line.len()>0 && line[0]==35) begin
            headers++; if(lineno!=1 || headers!=1) fail("header position/count");
          end else begin
            if(count>=ROWS) fail("extra row");
            cols=0; token="";
            for(idx=0;idx<=line.len();idx++) begin
              ch=(idx==line.len()) ? 32 : line[idx];
              if(ch==32 || ch==9 || ch==10 || ch==13) begin
                if(token.len()!=0) begin
                  if(cols>=20) fail("extra column");
                  width=width_for(cols);
                  if(!valid_lower_hex(token,(width+3)/4,width)) fail("lexical/width/high-padding");
                  if($sscanf(token,"%h",parsed)!=1) fail("conversion");
                  vec[count][cols]=parsed;
                  cols++; token="";
                end
              end else token={token,8'(ch)};
            end
            if(cols!=20) fail("column count");
            if(vec[count][0]!==40'(count/PER_PROFILE) || vec[count][1]!==40'(count%PER_PROFILE)) fail("profile/duplicate/reordered/missing ID");
            count++;
          end
        end
      end
      $fclose(fd); if(count!=ROWS || headers!=1) fail("exact fixture/header count");
    end
  endtask
  task automatic drive(input int row);
    begin
      id_meas=vec[row][2]; iq_meas=vec[row][3]; id_ref=vec[row][4]; iq_ref=vec[row][5];
      we=vec[row][6]; vdc=vec[row][7]; pi_reset=vec[row][8]; uq_zero_en=vec[row][9];
      xd_old=vec[row][10]; xq_old=vec[row][11]; du_d_old=vec[row][12]; du_q_old=vec[row][13];
    end
  endtask
  task automatic check_result(input int row);
    begin
      if(error_code!==vec[row][15][1:0] || ud_raw!==vec[row][16] || uq_raw!==vec[row][17] || xd_next!==vec[row][18] || xq_next!==vec[row][19]) begin
        $display("actual err/d/q/x/y = %h %h %h %h %h expected = %h %h %h %h %h",error_code,ud_raw,uq_raw,xd_next,xq_next,vec[row][15],vec[row][16],vec[row][17],vec[row][18],vec[row][19]);
        fail("bit-exact result");
      end
    end
  endtask
  task automatic idle_check(input int cycles);
    logic [161:0] held;
    begin
      held={ud_raw,uq_raw,xd_next,xq_next,error_code};
      repeat(cycles) begin
        @(negedge clk); input_valid=0; id_ref=~id_ref; we=~we;
        @(posedge clk); #1;
        if(input_ready!==1 || output_valid!==0 || {ud_raw,uq_raw,xd_next,xq_next,error_code}!==held) fail("idle hold/ready/pulse");
      end
    end
  endtask
  task automatic transact(input int row);
    logic [161:0] held;
    int k;
    begin
      current_case=row;
      @(negedge clk); if(input_ready!==1) fail("not ready before accept");
      drive(row); input_valid=1; held={ud_raw,uq_raw,xd_next,xq_next,error_code};
      @(posedge clk); #1; if(input_ready!==0 || output_valid!==0) fail("accept edge protocol");
      for(k=1;k<=LATENCY;k++) begin
        @(negedge clk); input_valid=1;
        id_meas=~id_meas; iq_meas=~iq_meas; id_ref=~id_ref; iq_ref=~iq_ref; we=~we; vdc=~vdc;
        pi_reset=~pi_reset; uq_zero_en=~uq_zero_en; xd_old=~xd_old; xq_old=~xq_old; du_d_old=~du_d_old; du_q_old=~du_q_old;
        if(input_ready!==0) fail("ready before completion");
        @(posedge clk); #1;
        if(k<LATENCY) begin
          if(output_valid!==0 || input_ready!==0 || {ud_raw,uq_raw,xd_next,xq_next,error_code}!==held) fail("early response/data change");
        end else begin
          if(output_valid!==1 || input_ready!==1) fail("fixed +16 response");
          check_result(row);
        end
      end
      transactions++; idle_check(2);
    end
  endtask
  task automatic held_valid_pair(input int row);
    int run,k;
    begin
      current_case=row;
      @(negedge clk); input_valid=1; drive(row);
      for(run=0;run<2;run++) begin
        @(posedge clk); #1;
        if(input_ready!==0 || output_valid!==0) fail("next-edge acceptance");
        for(k=1;k<=LATENCY;k++) begin
          @(negedge clk); if(input_ready!==0) fail("held-valid busy ready");
          @(posedge clk); #1; if(k<LATENCY && output_valid!==0) fail("held-valid early/duplicate");
        end
        if(output_valid!==1 || input_ready!==1) fail("held-valid response");
        check_result(row); transactions++; @(negedge clk);
      end
      input_valid=0; idle_check(LATENCY+2);
    end
  endtask
  task automatic abort_at(input int phase);
    begin
      @(negedge clk); input_valid=1; drive(PI_PROFILE*PER_PROFILE);
      @(posedge clk); #1;
      repeat(phase) begin @(posedge clk); #1; end
      #2; reset_n=0; #1;
      if(input_ready!==0 || output_valid!==0 || {ud_raw,uq_raw,xd_next,xq_next,error_code}!==0) fail("asynchronous abort/reset");
      @(negedge clk); input_valid=0;
      @(posedge clk); #1; if(input_ready!==0 || output_valid!==0) fail("reset ready");
      @(negedge clk); reset_n=1;
      idle_check(LATENCY+2); aborts++;
    end
  endtask
  // Assert reset in the NBA of the exact acceptance/completion clock edge.
  // The asynchronous control/output reset must win over any scheduled update.
  task automatic reset_on_edge(input bit at_completion);
    begin
      @(negedge clk); drive(PI_PROFILE*PER_PROFILE); input_valid=1;
      if(at_completion) begin
        @(posedge clk); #1;
        repeat(LATENCY-1) begin @(posedge clk); #1; end
      end
      @(posedge clk); reset_n<=0; #1;
      if(input_ready!==0 || output_valid!==0 || {ud_raw,uq_raw,xd_next,xq_next,error_code}!==0) fail("same-edge reset priority");
      @(negedge clk); input_valid=0;
      @(posedge clk); #1;
      @(negedge clk); reset_n=1;
      idle_check(LATENCY+2); aborts++;
    end
  endtask
  task automatic directed_vectors;
    begin
      // profile 0: one_amp_1
      vec[1042][0]=40'h0000000000;
      vec[1042][1]=40'h0000000000;
      vec[1042][2]=40'h0000000000;
      vec[1042][3]=40'h0000000000;
      vec[1042][4]=40'h0000008000;
      vec[1042][5]=40'h0000000000;
      vec[1042][6]=40'h0000000000;
      vec[1042][7]=40'h0000180000;
      vec[1042][8]=40'h0000000000;
      vec[1042][9]=40'h0000000000;
      vec[1042][10]=40'h0000000000;
      vec[1042][11]=40'h0000000000;
      vec[1042][12]=40'h0000000000;
      vec[1042][13]=40'h0000000000;
      vec[1042][14]=40'h0000000000;
      vec[1042][15]=40'h0000000000;
      vec[1042][16]=40'h0008b9999a;
      vec[1042][17]=40'h0000000000;
      vec[1042][18]=40'h00012f5c29;
      vec[1042][19]=40'h0000000000;
      // profile 0: one_amp_2
      vec[1043][0]=40'h0000000000;
      vec[1043][1]=40'h0000000001;
      vec[1043][2]=40'h0000000000;
      vec[1043][3]=40'h0000000000;
      vec[1043][4]=40'h0000008000;
      vec[1043][5]=40'h0000000000;
      vec[1043][6]=40'h0000000000;
      vec[1043][7]=40'h0000180000;
      vec[1043][8]=40'h0000000000;
      vec[1043][9]=40'h0000000000;
      vec[1043][10]=40'h00004bd70a;
      vec[1043][11]=40'h0000000000;
      vec[1043][12]=40'h0000000000;
      vec[1043][13]=40'h0000000000;
      vec[1043][14]=40'h0000000000;
      vec[1043][15]=40'h0000000000;
      vec[1043][16]=40'h00090570a4;
      vec[1043][17]=40'h0000000000;
      vec[1043][18]=40'h00017b3333;
      vec[1043][19]=40'h0000000000;
      // profile 0: one_amp_3
      vec[1044][0]=40'h0000000000;
      vec[1044][1]=40'h0000000002;
      vec[1044][2]=40'h0000000000;
      vec[1044][3]=40'h0000000000;
      vec[1044][4]=40'h0000008000;
      vec[1044][5]=40'h0000000000;
      vec[1044][6]=40'h0000000000;
      vec[1044][7]=40'h0000180000;
      vec[1044][8]=40'h0000000000;
      vec[1044][9]=40'h0000000000;
      vec[1044][10]=40'h000097ae14;
      vec[1044][11]=40'h0000000000;
      vec[1044][12]=40'h0000000000;
      vec[1044][13]=40'h0000000000;
      vec[1044][14]=40'h0000000000;
      vec[1044][15]=40'h0000000000;
      vec[1044][16]=40'h00095147ae;
      vec[1044][17]=40'h0000000000;
      vec[1044][18]=40'h0001c70a3d;
      vec[1044][19]=40'h0000000000;
      // profile 0: old_du
      vec[1045][0]=40'h0000000000;
      vec[1045][1]=40'h0000000003;
      vec[1045][2]=40'h0000000000;
      vec[1045][3]=40'h0000000000;
      vec[1045][4]=40'h0000000000;
      vec[1045][5]=40'h0000000000;
      vec[1045][6]=40'h0000000000;
      vec[1045][7]=40'h0000180000;
      vec[1045][8]=40'h0000000000;
      vec[1045][9]=40'h0000000000;
      vec[1045][10]=40'h00000003e8;
      vec[1045][11]=40'h00000007d0;
      vec[1045][12]=40'h0000000bb8;
      vec[1045][13]=40'hfffffff060;
      vec[1045][14]=40'h0000000001;
      vec[1045][15]=40'h0000000000;
      vec[1045][16]=40'h00000003e8;
      vec[1045][17]=40'h00000007d0;
      vec[1045][18]=40'h0000000190;
      vec[1045][19]=40'h0000000af0;
      // profile 0: ff_positive
      vec[1046][0]=40'h0000000000;
      vec[1046][1]=40'h0000000004;
      vec[1046][2]=40'h0000008000;
      vec[1046][3]=40'h0000010000;
      vec[1046][4]=40'h0000008000;
      vec[1046][5]=40'h0000010000;
      vec[1046][6]=40'h0000010000;
      vec[1046][7]=40'h0000180000;
      vec[1046][8]=40'h0000000000;
      vec[1046][9]=40'h0000000000;
      vec[1046][10]=40'h0000000000;
      vec[1046][11]=40'h0000000000;
      vec[1046][12]=40'h0000000000;
      vec[1046][13]=40'h0000000000;
      vec[1046][14]=40'h0000000000;
      vec[1046][15]=40'h0000000000;
      vec[1046][16]=40'hffffff1b48;
      vec[1046][17]=40'h0000248af0;
      vec[1046][18]=40'h0000000000;
      vec[1046][19]=40'h0000000000;
      // profile 0: ff_negative
      vec[1047][0]=40'h0000000000;
      vec[1047][1]=40'h0000000005;
      vec[1047][2]=40'h0000008000;
      vec[1047][3]=40'h0000010000;
      vec[1047][4]=40'h0000008000;
      vec[1047][5]=40'h0000010000;
      vec[1047][6]=40'h00ffff0000;
      vec[1047][7]=40'h0000180000;
      vec[1047][8]=40'h0000000000;
      vec[1047][9]=40'h0000000000;
      vec[1047][10]=40'h0000000000;
      vec[1047][11]=40'h0000000000;
      vec[1047][12]=40'h0000000000;
      vec[1047][13]=40'h0000000000;
      vec[1047][14]=40'h0000000000;
      vec[1047][15]=40'h0000000000;
      vec[1047][16]=40'h000000e4b8;
      vec[1047][17]=40'hffffdb7510;
      vec[1047][18]=40'h0000000000;
      vec[1047][19]=40'h0000000000;
      // profile 0: wide_cancel_positive
      vec[1048][0]=40'h0000000000;
      vec[1048][1]=40'h0000000006;
      vec[1048][2]=40'h0000ffffff;
      vec[1048][3]=40'h0000000000;
      vec[1048][4]=40'h0000ffffff;
      vec[1048][5]=40'h0000000000;
      vec[1048][6]=40'h007fffffff;
      vec[1048][7]=40'h0000180000;
      vec[1048][8]=40'h0000000000;
      vec[1048][9]=40'h0000000000;
      vec[1048][10]=40'h0000000000;
      vec[1048][11]=40'hf830000000;
      vec[1048][12]=40'h0000000000;
      vec[1048][13]=40'h0000000000;
      vec[1048][14]=40'h0000000000;
      vec[1048][15]=40'h0000000000;
      vec[1048][16]=40'h0000000000;
      vec[1048][17]=40'h7c9885469b;
      vec[1048][18]=40'h0000000000;
      vec[1048][19]=40'hf830000000;
      // profile 0: wide_cancel_negative
      vec[1049][0]=40'h0000000000;
      vec[1049][1]=40'h0000000007;
      vec[1049][2]=40'h0000ffffff;
      vec[1049][3]=40'h0000000000;
      vec[1049][4]=40'h0000ffffff;
      vec[1049][5]=40'h0000000000;
      vec[1049][6]=40'h0080000000;
      vec[1049][7]=40'h0000180000;
      vec[1049][8]=40'h0000000000;
      vec[1049][9]=40'h0000000000;
      vec[1049][10]=40'h0000000000;
      vec[1049][11]=40'h07d0000000;
      vec[1049][12]=40'h0000000000;
      vec[1049][13]=40'h0000000000;
      vec[1049][14]=40'h0000000000;
      vec[1049][15]=40'h0000000000;
      vec[1049][16]=40'h0000000000;
      vec[1049][17]=40'h83677ab85c;
      vec[1049][18]=40'h0000000000;
      vec[1049][19]=40'h07d0000000;
      // profile 0: q_reset_masks_q_overflow
      vec[1050][0]=40'h0000000000;
      vec[1050][1]=40'h0000000008;
      vec[1050][2]=40'h0000000000;
      vec[1050][3]=40'h0000008000;
      vec[1050][4]=40'h0000000000;
      vec[1050][5]=40'h0000000000;
      vec[1050][6]=40'h0000010000;
      vec[1050][7]=40'h0000180000;
      vec[1050][8]=40'h0000000000;
      vec[1050][9]=40'h0000000001;
      vec[1050][10]=40'h0000000000;
      vec[1050][11]=40'h7fffffffff;
      vec[1050][12]=40'h0000000000;
      vec[1050][13]=40'h8000000000;
      vec[1050][14]=40'h0000000000;
      vec[1050][15]=40'h0000000000;
      vec[1050][16]=40'hffffff8da4;
      vec[1050][17]=40'h0000000000;
      vec[1050][18]=40'h0000000000;
      vec[1050][19]=40'h0000000000;
      // profile 0: q_reset_keeps_d_overflow
      vec[1051][0]=40'h0000000000;
      vec[1051][1]=40'h0000000009;
      vec[1051][2]=40'h0000000000;
      vec[1051][3]=40'h0000000000;
      vec[1051][4]=40'h0000008000;
      vec[1051][5]=40'h0000000000;
      vec[1051][6]=40'h0000000000;
      vec[1051][7]=40'h0000180000;
      vec[1051][8]=40'h0000000000;
      vec[1051][9]=40'h0000000001;
      vec[1051][10]=40'h7fffffffff;
      vec[1051][11]=40'h0000000000;
      vec[1051][12]=40'h0000000000;
      vec[1051][13]=40'h0000000000;
      vec[1051][14]=40'h0000000000;
      vec[1051][15]=40'h0000000002;
      vec[1051][16]=40'h0000000000;
      vec[1051][17]=40'h0000000000;
      vec[1051][18]=40'h7fffffffff;
      vec[1051][19]=40'h0000000000;
      // profile 0: all_reset_masks_overflow
      vec[1052][0]=40'h0000000000;
      vec[1052][1]=40'h000000000a;
      vec[1052][2]=40'h0000000000;
      vec[1052][3]=40'h0000000000;
      vec[1052][4]=40'h0000ffffff;
      vec[1052][5]=40'h0001000000;
      vec[1052][6]=40'h0080000000;
      vec[1052][7]=40'h0000180000;
      vec[1052][8]=40'h0000000001;
      vec[1052][9]=40'h0000000000;
      vec[1052][10]=40'h7fffffffff;
      vec[1052][11]=40'h8000000000;
      vec[1052][12]=40'h8000000000;
      vec[1052][13]=40'h7fffffffff;
      vec[1052][14]=40'h0000000001;
      vec[1052][15]=40'h0000000000;
      vec[1052][16]=40'h0000000000;
      vec[1052][17]=40'h0000000000;
      vec[1052][18]=40'h0000000000;
      vec[1052][19]=40'h0000000000;
      // profile 0: invalid_priority
      vec[1053][0]=40'h0000000000;
      vec[1053][1]=40'h000000000b;
      vec[1053][2]=40'h0000000000;
      vec[1053][3]=40'h0000000000;
      vec[1053][4]=40'h0000000000;
      vec[1053][5]=40'h0000000000;
      vec[1053][6]=40'h0000000000;
      vec[1053][7]=40'h0001ffffff;
      vec[1053][8]=40'h0000000001;
      vec[1053][9]=40'h0000000000;
      vec[1053][10]=40'h7fffffffff;
      vec[1053][11]=40'h8000000000;
      vec[1053][12]=40'h8000000000;
      vec[1053][13]=40'h7fffffffff;
      vec[1053][14]=40'h0000000001;
      vec[1053][15]=40'h0000000001;
      vec[1053][16]=40'h0000000000;
      vec[1053][17]=40'h0000000000;
      vec[1053][18]=40'h7fffffffff;
      vec[1053][19]=40'h8000000000;
      // profile 0: next_state_only_overflow
      vec[1054][0]=40'h0000000000;
      vec[1054][1]=40'h000000000c;
      vec[1054][2]=40'h0000000000;
      vec[1054][3]=40'h0000000000;
      vec[1054][4]=40'h0000000000;
      vec[1054][5]=40'h0000000000;
      vec[1054][6]=40'h0000000000;
      vec[1054][7]=40'h0000180000;
      vec[1054][8]=40'h0000000000;
      vec[1054][9]=40'h0000000000;
      vec[1054][10]=40'h7fffffffff;
      vec[1054][11]=40'h0000000000;
      vec[1054][12]=40'h8000000000;
      vec[1054][13]=40'h0000000000;
      vec[1054][14]=40'h0000000000;
      vec[1054][15]=40'h0000000002;
      vec[1054][16]=40'h0000000000;
      vec[1054][17]=40'h0000000000;
      vec[1054][18]=40'h7fffffffff;
      vec[1054][19]=40'h0000000000;
      // profile 0: s26_difference
      vec[1055][0]=40'h0000000000;
      vec[1055][1]=40'h000000000d;
      vec[1055][2]=40'h0001000000;
      vec[1055][3]=40'h0000ffffff;
      vec[1055][4]=40'h0000ffffff;
      vec[1055][5]=40'h0001000000;
      vec[1055][6]=40'h0000000000;
      vec[1055][7]=40'h0000180000;
      vec[1055][8]=40'h0000000000;
      vec[1055][9]=40'h0000000000;
      vec[1055][10]=40'h0000000000;
      vec[1055][11]=40'h0000000000;
      vec[1055][12]=40'h0000000000;
      vec[1055][13]=40'h0000000000;
      vec[1055][14]=40'h0000000000;
      vec[1055][15]=40'h0000000000;
      vec[1055][16]=40'h22e666568d;
      vec[1055][17]=40'hdd1999a973;
      vec[1055][18]=40'h04bd70a1a1;
      vec[1055][19]=40'hfb428f5e5f;
      // profile 0: min_operands
      vec[1056][0]=40'h0000000000;
      vec[1056][1]=40'h000000000e;
      vec[1056][2]=40'h0001000000;
      vec[1056][3]=40'h0001000000;
      vec[1056][4]=40'h0000000000;
      vec[1056][5]=40'h0000000000;
      vec[1056][6]=40'h0080000000;
      vec[1056][7]=40'h0000180000;
      vec[1056][8]=40'h0000000000;
      vec[1056][9]=40'h0000000000;
      vec[1056][10]=40'h0000000000;
      vec[1056][11]=40'h0000000000;
      vec[1056][12]=40'h8000000000;
      vec[1056][13]=40'h8000000000;
      vec[1056][14]=40'h0000000000;
      vec[1056][15]=40'h0000000000;
      vec[1056][16]=40'h9f16f73400;
      vec[1056][17]=40'h71c3257a00;
      vec[1056][18]=40'h1bf851d200;
      vec[1056][19]=40'h1bf851d200;
      // profile 0: negative_exact_aw
      vec[1057][0]=40'h0000000000;
      vec[1057][1]=40'h000000000f;
      vec[1057][2]=40'h0000000000;
      vec[1057][3]=40'h0000000000;
      vec[1057][4]=40'h0000000000;
      vec[1057][5]=40'h0000000000;
      vec[1057][6]=40'h0000000000;
      vec[1057][7]=40'h0000180000;
      vec[1057][8]=40'h0000000000;
      vec[1057][9]=40'h0000000000;
      vec[1057][10]=40'hffffcccccd;
      vec[1057][11]=40'h0000333333;
      vec[1057][12]=40'hffff000000;
      vec[1057][13]=40'h0001000000;
      vec[1057][14]=40'h0000000000;
      vec[1057][15]=40'h0000000000;
      vec[1057][16]=40'hffffcccccd;
      vec[1057][17]=40'h0000333333;
      vec[1057][18]=40'h0000000000;
      vec[1057][19]=40'h0000000000;
      // profile 1: one_amp_1
      vec[1058][0]=40'h0000000001;
      vec[1058][1]=40'h0000000000;
      vec[1058][2]=40'h0000000000;
      vec[1058][3]=40'h0000000000;
      vec[1058][4]=40'h0000008000;
      vec[1058][5]=40'h0000000000;
      vec[1058][6]=40'h0000000000;
      vec[1058][7]=40'h0000180000;
      vec[1058][8]=40'h0000000000;
      vec[1058][9]=40'h0000000000;
      vec[1058][10]=40'h0000000000;
      vec[1058][11]=40'h0000000000;
      vec[1058][12]=40'h0000000000;
      vec[1058][13]=40'h0000000000;
      vec[1058][14]=40'h0000000000;
      vec[1058][15]=40'h0000000000;
      vec[1058][16]=40'h00045ccccd;
      vec[1058][17]=40'h0000000000;
      vec[1058][18]=40'h000097ae14;
      vec[1058][19]=40'h0000000000;
      // profile 1: one_amp_2
      vec[1059][0]=40'h0000000001;
      vec[1059][1]=40'h0000000001;
      vec[1059][2]=40'h0000000000;
      vec[1059][3]=40'h0000000000;
      vec[1059][4]=40'h0000008000;
      vec[1059][5]=40'h0000000000;
      vec[1059][6]=40'h0000000000;
      vec[1059][7]=40'h0000180000;
      vec[1059][8]=40'h0000000000;
      vec[1059][9]=40'h0000000000;
      vec[1059][10]=40'h000097ae14;
      vec[1059][11]=40'h0000000000;
      vec[1059][12]=40'h0000000000;
      vec[1059][13]=40'h0000000000;
      vec[1059][14]=40'h0000000000;
      vec[1059][15]=40'h0000000000;
      vec[1059][16]=40'h0004f47ae1;
      vec[1059][17]=40'h0000000000;
      vec[1059][18]=40'h00012f5c28;
      vec[1059][19]=40'h0000000000;
      // profile 1: one_amp_3
      vec[1060][0]=40'h0000000001;
      vec[1060][1]=40'h0000000002;
      vec[1060][2]=40'h0000000000;
      vec[1060][3]=40'h0000000000;
      vec[1060][4]=40'h0000008000;
      vec[1060][5]=40'h0000000000;
      vec[1060][6]=40'h0000000000;
      vec[1060][7]=40'h0000180000;
      vec[1060][8]=40'h0000000000;
      vec[1060][9]=40'h0000000000;
      vec[1060][10]=40'h00012f5c28;
      vec[1060][11]=40'h0000000000;
      vec[1060][12]=40'h0000000000;
      vec[1060][13]=40'h0000000000;
      vec[1060][14]=40'h0000000000;
      vec[1060][15]=40'h0000000000;
      vec[1060][16]=40'h00058c28f5;
      vec[1060][17]=40'h0000000000;
      vec[1060][18]=40'h0001c70a3c;
      vec[1060][19]=40'h0000000000;
      // profile 1: old_du
      vec[1061][0]=40'h0000000001;
      vec[1061][1]=40'h0000000003;
      vec[1061][2]=40'h0000000000;
      vec[1061][3]=40'h0000000000;
      vec[1061][4]=40'h0000000000;
      vec[1061][5]=40'h0000000000;
      vec[1061][6]=40'h0000000000;
      vec[1061][7]=40'h0000180000;
      vec[1061][8]=40'h0000000000;
      vec[1061][9]=40'h0000000000;
      vec[1061][10]=40'h00000003e8;
      vec[1061][11]=40'h00000007d0;
      vec[1061][12]=40'h0000000bb8;
      vec[1061][13]=40'hfffffff060;
      vec[1061][14]=40'h0000000001;
      vec[1061][15]=40'h0000000000;
      vec[1061][16]=40'h00000003e8;
      vec[1061][17]=40'h00000007d0;
      vec[1061][18]=40'h0000000190;
      vec[1061][19]=40'h0000000af0;
      // profile 1: ff_positive
      vec[1062][0]=40'h0000000001;
      vec[1062][1]=40'h0000000004;
      vec[1062][2]=40'h0000008000;
      vec[1062][3]=40'h0000010000;
      vec[1062][4]=40'h0000008000;
      vec[1062][5]=40'h0000010000;
      vec[1062][6]=40'h0000010000;
      vec[1062][7]=40'h0000180000;
      vec[1062][8]=40'h0000000000;
      vec[1062][9]=40'h0000000000;
      vec[1062][10]=40'h0000000000;
      vec[1062][11]=40'h0000000000;
      vec[1062][12]=40'h0000000000;
      vec[1062][13]=40'h0000000000;
      vec[1062][14]=40'h0000000000;
      vec[1062][15]=40'h0000000000;
      vec[1062][16]=40'hffffff1b48;
      vec[1062][17]=40'h0000248af0;
      vec[1062][18]=40'h0000000000;
      vec[1062][19]=40'h0000000000;
      // profile 1: ff_negative
      vec[1063][0]=40'h0000000001;
      vec[1063][1]=40'h0000000005;
      vec[1063][2]=40'h0000008000;
      vec[1063][3]=40'h0000010000;
      vec[1063][4]=40'h0000008000;
      vec[1063][5]=40'h0000010000;
      vec[1063][6]=40'h00ffff0000;
      vec[1063][7]=40'h0000180000;
      vec[1063][8]=40'h0000000000;
      vec[1063][9]=40'h0000000000;
      vec[1063][10]=40'h0000000000;
      vec[1063][11]=40'h0000000000;
      vec[1063][12]=40'h0000000000;
      vec[1063][13]=40'h0000000000;
      vec[1063][14]=40'h0000000000;
      vec[1063][15]=40'h0000000000;
      vec[1063][16]=40'h000000e4b8;
      vec[1063][17]=40'hffffdb7510;
      vec[1063][18]=40'h0000000000;
      vec[1063][19]=40'h0000000000;
      // profile 1: wide_cancel_positive
      vec[1064][0]=40'h0000000001;
      vec[1064][1]=40'h0000000006;
      vec[1064][2]=40'h0000ffffff;
      vec[1064][3]=40'h0000000000;
      vec[1064][4]=40'h0000ffffff;
      vec[1064][5]=40'h0000000000;
      vec[1064][6]=40'h007fffffff;
      vec[1064][7]=40'h0000180000;
      vec[1064][8]=40'h0000000000;
      vec[1064][9]=40'h0000000000;
      vec[1064][10]=40'h0000000000;
      vec[1064][11]=40'hf830000000;
      vec[1064][12]=40'h0000000000;
      vec[1064][13]=40'h0000000000;
      vec[1064][14]=40'h0000000000;
      vec[1064][15]=40'h0000000000;
      vec[1064][16]=40'h0000000000;
      vec[1064][17]=40'h7c9885469b;
      vec[1064][18]=40'h0000000000;
      vec[1064][19]=40'hf830000000;
      // profile 1: wide_cancel_negative
      vec[1065][0]=40'h0000000001;
      vec[1065][1]=40'h0000000007;
      vec[1065][2]=40'h0000ffffff;
      vec[1065][3]=40'h0000000000;
      vec[1065][4]=40'h0000ffffff;
      vec[1065][5]=40'h0000000000;
      vec[1065][6]=40'h0080000000;
      vec[1065][7]=40'h0000180000;
      vec[1065][8]=40'h0000000000;
      vec[1065][9]=40'h0000000000;
      vec[1065][10]=40'h0000000000;
      vec[1065][11]=40'h07d0000000;
      vec[1065][12]=40'h0000000000;
      vec[1065][13]=40'h0000000000;
      vec[1065][14]=40'h0000000000;
      vec[1065][15]=40'h0000000000;
      vec[1065][16]=40'h0000000000;
      vec[1065][17]=40'h83677ab85c;
      vec[1065][18]=40'h0000000000;
      vec[1065][19]=40'h07d0000000;
      // profile 1: q_reset_masks_q_overflow
      vec[1066][0]=40'h0000000001;
      vec[1066][1]=40'h0000000008;
      vec[1066][2]=40'h0000000000;
      vec[1066][3]=40'h0000008000;
      vec[1066][4]=40'h0000000000;
      vec[1066][5]=40'h0000000000;
      vec[1066][6]=40'h0000010000;
      vec[1066][7]=40'h0000180000;
      vec[1066][8]=40'h0000000000;
      vec[1066][9]=40'h0000000001;
      vec[1066][10]=40'h0000000000;
      vec[1066][11]=40'h7fffffffff;
      vec[1066][12]=40'h0000000000;
      vec[1066][13]=40'h8000000000;
      vec[1066][14]=40'h0000000000;
      vec[1066][15]=40'h0000000000;
      vec[1066][16]=40'hffffff8da4;
      vec[1066][17]=40'h0000000000;
      vec[1066][18]=40'h0000000000;
      vec[1066][19]=40'h0000000000;
      // profile 1: q_reset_keeps_d_overflow
      vec[1067][0]=40'h0000000001;
      vec[1067][1]=40'h0000000009;
      vec[1067][2]=40'h0000000000;
      vec[1067][3]=40'h0000000000;
      vec[1067][4]=40'h0000008000;
      vec[1067][5]=40'h0000000000;
      vec[1067][6]=40'h0000000000;
      vec[1067][7]=40'h0000180000;
      vec[1067][8]=40'h0000000000;
      vec[1067][9]=40'h0000000001;
      vec[1067][10]=40'h7fffffffff;
      vec[1067][11]=40'h0000000000;
      vec[1067][12]=40'h0000000000;
      vec[1067][13]=40'h0000000000;
      vec[1067][14]=40'h0000000000;
      vec[1067][15]=40'h0000000002;
      vec[1067][16]=40'h0000000000;
      vec[1067][17]=40'h0000000000;
      vec[1067][18]=40'h7fffffffff;
      vec[1067][19]=40'h0000000000;
      // profile 1: all_reset_masks_overflow
      vec[1068][0]=40'h0000000001;
      vec[1068][1]=40'h000000000a;
      vec[1068][2]=40'h0000000000;
      vec[1068][3]=40'h0000000000;
      vec[1068][4]=40'h0000ffffff;
      vec[1068][5]=40'h0001000000;
      vec[1068][6]=40'h0080000000;
      vec[1068][7]=40'h0000180000;
      vec[1068][8]=40'h0000000001;
      vec[1068][9]=40'h0000000000;
      vec[1068][10]=40'h7fffffffff;
      vec[1068][11]=40'h8000000000;
      vec[1068][12]=40'h8000000000;
      vec[1068][13]=40'h7fffffffff;
      vec[1068][14]=40'h0000000001;
      vec[1068][15]=40'h0000000000;
      vec[1068][16]=40'h0000000000;
      vec[1068][17]=40'h0000000000;
      vec[1068][18]=40'h0000000000;
      vec[1068][19]=40'h0000000000;
      // profile 1: invalid_priority
      vec[1069][0]=40'h0000000001;
      vec[1069][1]=40'h000000000b;
      vec[1069][2]=40'h0000000000;
      vec[1069][3]=40'h0000000000;
      vec[1069][4]=40'h0000000000;
      vec[1069][5]=40'h0000000000;
      vec[1069][6]=40'h0000000000;
      vec[1069][7]=40'h0001ffffff;
      vec[1069][8]=40'h0000000001;
      vec[1069][9]=40'h0000000000;
      vec[1069][10]=40'h7fffffffff;
      vec[1069][11]=40'h8000000000;
      vec[1069][12]=40'h8000000000;
      vec[1069][13]=40'h7fffffffff;
      vec[1069][14]=40'h0000000001;
      vec[1069][15]=40'h0000000001;
      vec[1069][16]=40'h0000000000;
      vec[1069][17]=40'h0000000000;
      vec[1069][18]=40'h7fffffffff;
      vec[1069][19]=40'h8000000000;
      // profile 1: next_state_only_overflow
      vec[1070][0]=40'h0000000001;
      vec[1070][1]=40'h000000000c;
      vec[1070][2]=40'h0000000000;
      vec[1070][3]=40'h0000000000;
      vec[1070][4]=40'h0000000000;
      vec[1070][5]=40'h0000000000;
      vec[1070][6]=40'h0000000000;
      vec[1070][7]=40'h0000180000;
      vec[1070][8]=40'h0000000000;
      vec[1070][9]=40'h0000000000;
      vec[1070][10]=40'h7fffffffff;
      vec[1070][11]=40'h0000000000;
      vec[1070][12]=40'h8000000000;
      vec[1070][13]=40'h0000000000;
      vec[1070][14]=40'h0000000000;
      vec[1070][15]=40'h0000000002;
      vec[1070][16]=40'h0000000000;
      vec[1070][17]=40'h0000000000;
      vec[1070][18]=40'h7fffffffff;
      vec[1070][19]=40'h0000000000;
      // profile 1: s26_difference
      vec[1071][0]=40'h0000000001;
      vec[1071][1]=40'h000000000d;
      vec[1071][2]=40'h0001000000;
      vec[1071][3]=40'h0000ffffff;
      vec[1071][4]=40'h0000ffffff;
      vec[1071][5]=40'h0001000000;
      vec[1071][6]=40'h0000000000;
      vec[1071][7]=40'h0000180000;
      vec[1071][8]=40'h0000000000;
      vec[1071][9]=40'h0000000000;
      vec[1071][10]=40'h0000000000;
      vec[1071][11]=40'h0000000000;
      vec[1071][12]=40'h0000000000;
      vec[1071][13]=40'h0000000000;
      vec[1071][14]=40'h0000000000;
      vec[1071][15]=40'h0000000000;
      vec[1071][16]=40'h1173332b46;
      vec[1071][17]=40'hee8cccd4ba;
      vec[1071][18]=40'h025eb84ed1;
      vec[1071][19]=40'hfda147b12f;
      // profile 1: min_operands
      vec[1072][0]=40'h0000000001;
      vec[1072][1]=40'h000000000e;
      vec[1072][2]=40'h0001000000;
      vec[1072][3]=40'h0001000000;
      vec[1072][4]=40'h0000000000;
      vec[1072][5]=40'h0000000000;
      vec[1072][6]=40'h0080000000;
      vec[1072][7]=40'h0000180000;
      vec[1072][8]=40'h0000000000;
      vec[1072][9]=40'h0000000000;
      vec[1072][10]=40'h0000000000;
      vec[1072][11]=40'h0000000000;
      vec[1072][12]=40'h8000000000;
      vec[1072][13]=40'h8000000000;
      vec[1072][14]=40'h0000000000;
      vec[1072][15]=40'h0000000000;
      vec[1072][16]=40'h965d5d9a00;
      vec[1072][17]=40'h69098be000;
      vec[1072][18]=40'h1ac8f5a800;
      vec[1072][19]=40'h1ac8f5a800;
      // profile 1: negative_exact_aw
      vec[1073][0]=40'h0000000001;
      vec[1073][1]=40'h000000000f;
      vec[1073][2]=40'h0000000000;
      vec[1073][3]=40'h0000000000;
      vec[1073][4]=40'h0000000000;
      vec[1073][5]=40'h0000000000;
      vec[1073][6]=40'h0000000000;
      vec[1073][7]=40'h0000180000;
      vec[1073][8]=40'h0000000000;
      vec[1073][9]=40'h0000000000;
      vec[1073][10]=40'hffffcccccd;
      vec[1073][11]=40'h0000333333;
      vec[1073][12]=40'hffff000000;
      vec[1073][13]=40'h0001000000;
      vec[1073][14]=40'h0000000000;
      vec[1073][15]=40'h0000000000;
      vec[1073][16]=40'hffffcccccd;
      vec[1073][17]=40'h0000333333;
      vec[1073][18]=40'h0000000000;
      vec[1073][19]=40'h0000000000;
    end
  endtask
  initial begin
    int i;
    load_vectors(); directed_vectors();
    #1; if(input_ready!==0) fail("initial reset ready");
    repeat(2) @(negedge clk); reset_n=1;
    idle_check(5000);
    // Literal one-amp and old-du cases run before the seeded corpus.
    for(i=0;i<EXTRA;i++) transact(ROWS+PI_PROFILE*EXTRA+i);
    for(i=0;i<PER_PROFILE;i++) transact(PI_PROFILE*PER_PROFILE+i);
    for(i=0;i<16;i++) begin idle_check(i%7); transact(ROWS+PI_PROFILE*EXTRA+i); end
    held_valid_pair(ROWS+PI_PROFILE*EXTRA+3);
    for(i=0;i<LATENCY;i++) abort_at(i);
    reset_on_edge(0); reset_on_edge(1);
    transact(ROWS+PI_PROFILE*EXTRA);
    $display("ALL STEP 6C2 PI EVAL TESTS PASSED profile=%0d fixture_rows=%0d total_fixture_rows=%0d directed=%0d transactions=%0d aborts=%0d idle_clocks=5000",PI_PROFILE,PER_PROFILE,ROWS,EXTRA,transactions,aborts);
    $finish;
  end
  initial begin #2000000; fail("watchdog"); end
endmodule

// Separate elaborated tops ensure each profile is an independent simulation.
module mc_pi_dq_eval_p0_tb;
  mc_pi_dq_eval_tb #(.PI_PROFILE(0)) tests();
endmodule
module mc_pi_dq_eval_p1_tb;
  mc_pi_dq_eval_tb #(.PI_PROFILE(1)) tests();
endmodule
