`timescale 1ns/1ps
module mc_dq_limiter_tb;
  localparam int ROWS=4246, LATENCY=160;
  logic clk=0, reset_n=0, input_valid=0;
  wire input_ready, output_valid;
  always #10 clk=~clk;
  logic signed [39:0] ud_raw=0,uq_raw=0;
  logic signed [24:0] vdc=0;
  logic signed [39:0] ud_hi,uq_hi,du_d_next,du_q_next;
  logic signed [24:0] ud_lim,uq_lim;
  logic [32:0] scale;
  logic limited,sat_flag;
  logic [1:0] error_code;
  logic [39:0] vec[0:ROWS-1][0:13];
  wire [246:0] response={ud_hi,uq_hi,du_d_next,du_q_next,ud_lim,uq_lim,scale,limited,sat_flag,error_code};
  int transactions=0,aborts=0,errors=0,injected_errors=0,current_case=-1,ideal_checks=0;
  int max_d_case=-1,max_q_case=-1,max_norm_case=-1;
  real max_d_error=0.0,max_q_error=0.0,max_norm_excess=0.0;
  mc_dq_limiter dut(.*);
  task automatic fail(input string msg);
    $fatal(1,"MC_DQ_LIMITER_FAIL case=%0d: %s",current_case,msg);
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


  task automatic load_vectors;
    string dir,line,token;
    logic [39:0] parsed;
    int fd,rc,count,headers,lineno,cols,idx,ch,width,digits;
    begin
      if(!$value$plusargs("VECTOR_DIR=%s",dir)) dir="motor_control_ip/foc/tb/vectors/step6c2";
      fd=$fopen({dir,"/limiter_vectors.txt"},"r"); if(!fd) fail("fixture open");
      count=0; headers=0; lineno=0;
      while(!$feof(fd)) begin
        line=""; rc=$fgets(line,fd);
        if(rc!=0) begin
          lineno++;
          if(line.len()>0 && line[0]==35) begin
            headers++; if(lineno!=1 || headers!=1) fail("header position/count");
          end else begin
            // Indexed bytes avoid XSim getc/many-string sscanf kernel crashes.
            cols=0; token="";
            for(idx=0;idx<=line.len();idx++) begin
              ch=(idx==line.len())?32:line[idx];
              if(ch==32 || ch==9 || ch==10 || ch==13) begin
                if(token.len()!=0) begin
                  if(cols>=14 || count>=ROWS) fail("extra columns/rows");
                  case(cols)
                    0:width=32;
                    3,9,10:width=25;
                    4:width=2;
                    11:width=33;
                    12,13:width=1;
                    default:width=40;
                  endcase
                  digits=(width+3)/4;
                  if(!valid_lower_hex(token,digits,width)) fail("lexical/width/high-padding");
                  if($sscanf(token,"%h",parsed)!=1) fail("conversion");
                  if(cols==0 && parsed!==count) fail("duplicate/reordered/missing ID");
                  vec[count][cols]=parsed;
                  cols++; token="";
                end
              end else token={token,8'(ch)};
            end
            if(cols!=14) fail("exact fourteen columns");
            count++;
          end
        end
      end
      $fclose(fd); if(count!=ROWS || headers!=1) fail("exact 4246 rows/header count");
    end
  endtask
  function automatic real magnitude(input real x); magnitude=(x<0.0)?-x:x; endfunction
  task automatic ideal_check(input int row);
    real d,q,bus,radius,umax,s,expected_d,expected_q,out_d,out_q,de,qe,ne;
    begin
      if($signed(vec[row][3][24:0])>0) begin
        // Convert the full signed S40 operand directly to real, without int truncation.
        d=$signed(vec[row][1])/16777216.0;
        q=$signed(vec[row][2])/16777216.0;
        bus=$signed(vec[row][3][24:0])/32768.0;
        radius=$sqrt(d*d+q*q); umax=0.9*bus/$sqrt(3.0);
        s=umax/(radius+0.000001); if(s>1.0) s=1.0;
        expected_d=s*d; expected_q=s*q;
        out_d=$signed(ud_lim)/32768.0; out_q=$signed(uq_lim)/32768.0;
        de=magnitude(out_d-expected_d); qe=magnitude(out_q-expected_q);
        ne=$sqrt(out_d*out_d+out_q*out_q)-umax;
        if(!(de>=0.0) || !(qe>=0.0) || !(ne<1.0e100)) fail("nonfinite ideal comparison");
        if(de>2.0/32768.0 || qe>2.0/32768.0 || ne>1.0/32768.0) fail("independent ideal component/norm bound");
        if((d>0.0 && out_d<0.0)||(d<0.0 && out_d>0.0)||(q>0.0 && out_q<0.0)||(q<0.0 && out_q>0.0)) fail("output sign");
        if(d==0.0 && out_d!=0.0 || q==0.0 && out_q!=0.0) fail("zero-axis sign preservation");
        if(de>max_d_error) begin max_d_error=de; max_d_case=row; end
        if(qe>max_q_error) begin max_q_error=qe; max_q_case=row; end
        if(ne>max_norm_excess) begin max_norm_excess=ne; max_norm_case=row; end
        ideal_checks++;
      end
    end
  endtask
  task automatic check_response(input int row);
    logic [246:0] expected;
    begin
      expected={vec[row][5],vec[row][6],vec[row][7],vec[row][8],vec[row][9][24:0],vec[row][10][24:0],vec[row][11][32:0],vec[row][12][0],vec[row][13][0],vec[row][4][1:0]};
      if($isunknown(response)) fail("unknown response data");
      if(response!==expected) begin
        $display("actual=%h expected=%h scale=%h expected_scale=%h",response,expected,scale,vec[row][11]);
        fail("bit-exact independent oracle mismatch");
      end
      if(error_code!=0) begin
        if(response[246:2]!==0) fail("error output must zero");
        errors++;
      end else ideal_check(row);
      transactions++;
    end
  endtask
  task automatic drive_row(input int row);
    begin ud_raw=vec[row][1]; uq_raw=vec[row][2]; vdc=vec[row][3][24:0]; end
  endtask
  task automatic idle_check(input int cycles);
    logic [246:0] held;
    begin
      held=response;
      repeat(cycles) begin
        @(negedge clk); input_valid=0; ud_raw=~ud_raw; uq_raw=~uq_raw; vdc=~vdc;
        @(posedge clk); #1;
        if(input_ready!==1 || output_valid!==0 || response!==held) fail("idle response/ready hold");
      end
    end
  endtask
  task automatic transact(input int row);
    logic [246:0] held;
    int k;
    begin
      current_case=row;
      @(negedge clk); if(input_ready!==1) fail("not ready at request");
      drive_row(row); input_valid=1; held=response;
      @(posedge clk); #1;
      if(input_ready!==0 || output_valid!==0) fail("accept protocol");
      for(k=1;k<=LATENCY;k++) begin
        @(negedge clk); input_valid=1;
        ud_raw=~ud_raw; uq_raw=~uq_raw; vdc=~vdc;
        if(input_ready!==0) fail("ready before completion");
        @(posedge clk); #1;
        if(k<LATENCY) begin
          if(output_valid!==0 || input_ready!==0 || response!==held) fail("early/unknown valid/data change");
        end else begin
          if(output_valid!==1 || input_ready!==1) fail("fixed +160 response");
          check_response(row);
        end
      end
      // Valid was high on completion. No acceptance there; drop before next edge.
      idle_check(2);
    end
  endtask
  task automatic held_valid_pair;
    logic [246:0] held;
    int run,k,row;
    begin
      @(negedge clk); input_valid=1;
      for(run=0;run<2;run++) begin
        row=5+run; current_case=row; drive_row(row); held=response;
        @(posedge clk); #1;
        if(input_ready!==0 || output_valid!==0) fail("earliest next edge accept");
        for(k=1;k<=LATENCY;k++) begin
          @(negedge clk); ud_raw=~ud_raw; uq_raw=~uq_raw; vdc=~vdc;
          if(input_ready!==0) fail("held-valid busy ready");
          @(posedge clk); #1;
          if(k<LATENCY && (output_valid!==0 || response!==held)) fail("held-valid early/duplicate/data change");
        end
        if(output_valid!==1 || input_ready!==1) fail("held-valid completion");
        check_response(row);
        @(negedge clk);
      end
      input_valid=0; idle_check(LATENCY+2);
    end
  endtask
  task automatic abort_at(input int phase);
    begin
      current_case=-1;
      @(negedge clk); input_valid=1; ud_raw=40'sh8000000000; uq_raw=40'sh8000000000; vdc=25'd1572864;
      @(posedge clk); #1;
      repeat(phase) begin @(posedge clk); #1; end
      #2; reset_n=0; #1;
      if(input_ready!==0 || output_valid!==0 || response!==0) fail("asynchronous abort/reset outputs");
      @(negedge clk); input_valid=0;
      @(posedge clk); #1; if(input_ready!==0 || output_valid!==0) fail("ready while reset");
      @(negedge clk); reset_n=1;
      idle_check(LATENCY+2); aborts++;
    end
  endtask
  // Fault injection checks otherwise-unreachable invariant/range rejection.
  // These are TB forces only; production RTL has no test or injection ports.
  task automatic injected_fault(input int kind);
    int k,phase;
    logic [1:0] expected_error;
    logic [246:0] held;
    begin
      current_case=-100-kind;
      case(kind)
        0:phase=3; 1:phase=4; 2:phase=45; 3:phase=46;
        4:phase=47; 5,6:phase=120; 7:phase=121;
        8,9:phase=124; default:phase=160;
      endcase
      expected_error=(kind==8 || kind==9)?2'b10:2'b11;
      @(negedge clk); drive_row(5); input_valid=1; held=response;
      @(posedge clk); #1;
      if(input_ready!==0 || output_valid!==0) fail("fault accept");
      for(k=1;k<=LATENCY;k++) begin
        @(negedge clk); input_valid=1; ud_raw=~ud_raw; uq_raw=~uq_raw; vdc=~vdc;
        if(input_ready!==0) fail("fault busy ready");
        if(k==phase) begin
          case(kind)
            0:force dut.norm_sum=81'h100000000000000000000;
            1:force dut.sqrt_ready=0;
            2:force dut.sqrt_output_valid=0;
            3:force dut.denom=0;
            4:force dut.div_ready=0;
            5:force dut.div_by_zero=1;
            6:force dut.quotient=72'h000000000100000000;
            7:force dut.work_scale=33'd4294967297;
            8:force dut.high_d=96'sd549755813888;
            9:force dut.external_q=96'sd16777216;
            default:force dut.result_done=0;
          endcase
        end
        @(posedge clk); #1;
        if(k<LATENCY) begin
          if(output_valid!==0 || input_ready!==0 || response!==held) fail("fault early/change");
        end else begin
          if(output_valid!==1 || input_ready!==1 || error_code!==expected_error || response[246:2]!==0) fail("fault fixed-slot zero error response");
        end
        if(k==phase) begin
          case(kind)
            0:release dut.norm_sum;
            1:release dut.sqrt_ready;
            2:release dut.sqrt_output_valid;
            3:release dut.denom;
            4:release dut.div_ready;
            5:release dut.div_by_zero;
            6:release dut.quotient;
            7:release dut.work_scale;
            8:release dut.high_d;
            9:release dut.external_q;
            default:release dut.result_done;
          endcase
        end
      end
      transactions++; errors++; injected_errors++;
      idle_check(2);
      // Fresh acceptance must fully replace poisoned intermediate state.
      transact(5);
    end
  endtask
  initial begin
    int i;
    load_vectors();
    #1; if(input_ready!==0) fail("initial reset ready");
    repeat(2) @(negedge clk); reset_n=1;
    idle_check(5000);
    for(i=0;i<ROWS;i++) transact(i);
    for(i=0;i<16;i++) begin idle_check(i%7); transact(i); end
    held_valid_pair();
    for(i=0;i<LATENCY;i++) abort_at(i);
    transact(ROWS-1);
    for(i=0;i<11;i++) injected_fault(i);
    $display("IDEAL maxima volts: d=%0.12f row=%0d q=%0.12f row=%0d norm_excess=%0.12f row=%0d checks=%0d",max_d_error,max_d_case,max_q_error,max_q_case,max_norm_excess,max_norm_case,ideal_checks);
    $display("ALL STEP 6C2 LIMITER TESTS PASSED fixture_rows=%0d transactions=%0d errors=%0d injected_errors=%0d aborts=%0d latency=160 idle_clocks=5000",ROWS,transactions,errors,injected_errors,aborts);
    $finish;
  end
  initial begin #50000000; fail("watchdog"); end
endmodule
