`timescale 1ns/1ps
module mc_pi_dq_core_tb #(parameter int PI_PROFILE=0);
  localparam int GOLDEN=160, SEEDED=2048, ERRORS=258, BASE=2466;
  localparam int DIRECTED=13, TOTAL=BASE+2*DIRECTED, LATENCY=256;
  logic clk=0, reset_n=0, input_valid=0;
  always #10 clk=~clk;
  logic signed [24:0] id_meas=0,iq_meas=0,id_ref=0,iq_ref=0,vdc=0;
  logic signed [31:0] we=0;
  logic pi_reset=0,uq_zero_en=0;
  wire input_ready,output_valid,limited,sat_flag;
  wire signed [24:0] ud_lim,uq_lim;
  wire [1:0] error_code;
  mc_pi_dq_core #(.PI_PROFILE(PI_PROFILE)) dut(.*);
  logic [39:0] vec[0:TOTAL-1][0:33];
  int edge_number=0,accepted=0,completed=0,aborted=0,successes=0;
  int invalids=0,ranges=0,internals=0, driven_row=-1,current_case=-1;
  int abort_eval=0,abort_sqrt=0,abort_div=0,abort_padding=0;
  int head=0,tail=0,queue_row[0:8191],queue_edge[0:8191],queue_id[0:8191];
  logic [160:0] queue_old[0:8191];
  logic [160:0] expected_state=0;
  logic [567:0] held_visible=0;
  bit accepted_now;
  int rr;
  task automatic fail(input string why);
    $fatal(1,"MC_PI_DQ_CORE_FAIL profile=%0d row=%0d edge=%0d accepted=%0d completed=%0d aborted=%0d: %s",PI_PROFILE,current_case,edge_number,accepted,completed,aborted,why);
  endtask
  function automatic logic [160:0] state_now;
    state_now={dut.xd_state,dut.xq_state,dut.du_d_state,dut.du_q_state,dut.sat_state};
  endfunction
  function automatic logic [567:0] visible_now;
    visible_now={ud_lim,uq_lim,error_code,limited,sat_flag,
      dut.dbg_xd_old,dut.dbg_xq_old,dut.dbg_du_d_old,dut.dbg_du_q_old,dut.dbg_sat_old,
      dut.dbg_ud_raw,dut.dbg_uq_raw,dut.dbg_xd_next,dut.dbg_xq_next,
      dut.dbg_ud_hi,dut.dbg_uq_hi,dut.dbg_du_d_next,dut.dbg_du_q_next,dut.dbg_scale};
  endfunction
  function automatic logic [160:0] old_for(input int r);
    old_for={vec[r][12],vec[r][13],vec[r][14],vec[r][15],vec[r][16][0]};
  endfunction
  function automatic logic [160:0] next_for(input int r);
    next_for={vec[r][29],vec[r][30],vec[r][31],vec[r][32],vec[r][33][0]};
  endfunction
  function automatic logic [567:0] visible_for(input int r);
    visible_for={vec[r][24][24:0],vec[r][25][24:0],vec[r][19][1:0],vec[r][27][0],vec[r][28][0],
      vec[r][12],vec[r][13],vec[r][14],vec[r][15],vec[r][16][0],
      vec[r][17],vec[r][18],vec[r][29],vec[r][30],
      vec[r][20],vec[r][21],vec[r][22],vec[r][23],vec[r][26][32:0]};
  endfunction
  // Queue entries arise ONLY from pre-NBA valid && ready edges, never driver calls.
  // Every busy and idle edge checks all persistent state and every held snapshot.
  always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      aborted=aborted+(tail-head); head=tail;
      expected_state=0; held_visible=0;
      #1;
      if(input_ready!==0 || output_valid!==0 || state_now()!==0 || visible_now()!==0)
        fail("asynchronous reset/abort outputs/state/debug/ready");
    end else begin
      edge_number++;
      if((^{input_ready,output_valid,input_valid})===1'bx) fail("unknown handshake");
      if(input_ready!==(head==tail)) fail("pre-edge ready/pending mismatch");
      accepted_now=input_valid && input_ready;
      if(accepted_now) begin
        if(head!=tail) fail("accepted while pending/completion-edge acceptance");
        if(driven_row<0 || tail>=8192) fail("unexpected acceptance/queue overflow");
        current_case=driven_row;
        if(state_now()!==expected_state || old_for(driven_row)!==expected_state)
          fail("accepted OLD state continuity");
        queue_row[tail]=driven_row; queue_edge[tail]=edge_number;
        queue_id[tail]=accepted; queue_old[tail]=state_now();
        tail++; accepted++;
      end
      #1;
      // A reset asserted in this clock's NBA wins over its scheduled response.
      if(!reset_n) begin
        aborted=aborted+(tail-head); head=tail;
        expected_state=0; held_visible=0;
        if(input_ready!==0 || output_valid!==0 || state_now()!==0 || visible_now()!==0)
          fail("same-edge reset priority");
      end else begin
      if((^{input_ready,output_valid,visible_now(),state_now()})===1'bx) fail("unknown meaningful output/state/debug");
      if(output_valid) begin
        if(head==tail) fail("extra/duplicate/unaccepted response");
        rr=queue_row[head]; current_case=rr;
        if(accepted_now || edge_number-queue_edge[head]!=LATENCY) fail("early/late/acceptance-edge response");
        if(queue_id[head]!=completed+aborted) fail("reordered response ID");
        if(queue_old[head]!==old_for(rr)) fail("OLD snapshot queue mismatch");
        if(visible_now()!==visible_for(rr)) begin
          $display("got err=%h raw=%h/%h xd=%h xq=%h du=%h/%h expected err=%h raw=%h/%h xd=%h xq=%h du=%h/%h",error_code,dut.dbg_ud_raw,dut.dbg_uq_raw,dut.dbg_xd_next,dut.dbg_xq_next,dut.dbg_du_d_next,dut.dbg_du_q_next,vec[rr][19],vec[rr][17],vec[rr][18],vec[rr][29],vec[rr][30],vec[rr][22],vec[rr][23]);
          fail("bit-exact functional or response-aligned OLD/NEXT debug mismatch");
        end
        expected_state=next_for(rr); held_visible=visible_for(rr);
        case(error_code)
          0: successes++;
          1: invalids++;
          2: ranges++;
          3: internals++;
        endcase
        head++; completed++;
      end else begin
        if(visible_now()!==held_visible) fail("premature/unstable held functional/debug outputs");
        if(head!=tail && edge_number-queue_edge[head]>=LATENCY) fail("missing response");
      end
      if(state_now()!==expected_state) fail("premature/repeated/non-atomic/error state commit");
      if(input_ready!==(head==tail)) fail("post-edge ready/pending mismatch");
      if(accepted!=completed+aborted+(tail-head)) fail("accepted/completed/aborted accounting");
      end
    end
  end
  function automatic bit valid_lower_hex(input string token,input int digits,input int bits);
    int i,c;
    begin
      valid_lower_hex=(token.len()==digits);
      if(valid_lower_hex) begin
        for(i=0;i<token.len();i++) begin
          c=token[i];
          if(!((c>=48 && c<=57)||(c>=97 && c<=102))) valid_lower_hex=0;
        end
        c=token[0]; c=(c<=57)?c-48:c-87;
        if(c>=(1<<(bits-4*(digits-1)))) valid_lower_hex=0;
      end
    end
  endfunction
  function automatic int width_for(input int col);
    case(col)
      0,3,10,11,16,27,28,33: width_for=1;
      1: width_for=16;
      2,8: width_for=32;
      4,5,6,7,9,24,25: width_for=25;
      19: width_for=2;
      26: width_for=33;
      default: width_for=40;
    endcase
  endfunction
  task automatic load_file(input string name,input int offset,input int rows,input int per_profile,input int sequence_id);
    string dir,line,token;
    int fd,rc,count,headers,lineno,cols,idx,ch,width;
    logic [39:0] parsed;
    begin
      if(!$value$plusargs("VECTOR_DIR=%s",dir)) dir="motor_control_ip/foc/tb/vectors/step6c2";
      fd=$fopen({dir,"/",name},"r"); if(!fd) fail("fixture open");
      count=0; headers=0; lineno=0;
      while(!$feof(fd)) begin
        line=""; rc=$fgets(line,fd);
        if(rc!=0) begin
          lineno++;
          if(line.len()>0 && line[0]==35) begin
            headers++; if(lineno!=1 || headers!=1) fail("header position/count");
          end else begin
            if(count>=rows) fail("extra fixture row");
            cols=0; token="";
            for(idx=0;idx<=line.len();idx++) begin
              ch=(idx==line.len())?32:line[idx];
              if(ch==32 || ch==9 || ch==10 || ch==13) begin
                if(token.len()!=0) begin
                  if(cols>=34) fail("extra column");
                  width=width_for(cols);
                  if(!valid_lower_hex(token,(width+3)/4,width)) fail("lexical/width/high-padding");
                  if($sscanf(token,"%h",parsed)!=1) fail("conversion");
                  vec[offset+count][cols]=parsed; cols++; token="";
                end
              end else token={token,8'(ch)};
            end
            if(cols!=34) fail("exact 34-column count");
            if(vec[offset+count][0]!==40'(count/per_profile) || vec[offset+count][1]!==40'(sequence_id) ||
               vec[offset+count][2]!==40'(count%per_profile) || vec[offset+count][3]!==40'(count%per_profile==0))
              fail("profile/sequence/duplicate/reordered/missing ID/reset_before");
            count++;
          end
        end
      end
      $fclose(fd);
      if(count!=rows || headers!=1) fail("independent exact fixture/header count");
    end
  endtask
  task automatic drive(input int row);
    begin
      driven_row=row;
      id_meas=vec[row][4]; iq_meas=vec[row][5]; id_ref=vec[row][6]; iq_ref=vec[row][7];
      we=vec[row][8]; vdc=vec[row][9]; pi_reset=vec[row][10]; uq_zero_en=vec[row][11];
    end
  endtask
  task automatic poison;
    begin
      id_meas=~id_meas; iq_meas=~iq_meas; id_ref=~id_ref; iq_ref=~iq_ref;
      we=~we; vdc=~vdc; pi_reset=~pi_reset; uq_zero_en=~uq_zero_en;
    end
  endtask
  task automatic idle(input int clocks);
    begin
      @(negedge clk); input_valid=0; driven_row=-1;
      repeat(clocks) begin poison(); @(posedge clk); #2; @(negedge clk); end
    end
  endtask
  task automatic reset_hw;
    begin
      @(negedge clk); input_valid=0; reset_n=0; #2;
      @(negedge clk); reset_n=1;
    end
  endtask
  task automatic transact(input int row);
    int k;
    begin
      @(negedge clk); drive(row); input_valid=1;
      @(posedge clk); #2;
      for(k=1;k<=LATENCY;k++) begin
        @(negedge clk); poison(); driven_row=-1; // valid remains asserted throughout busy
        @(posedge clk); #2;
      end
      @(negedge clk); input_valid=0;
    end
  endtask
  task automatic replay(input int offset,input int count,input int gap_mode);
    int i,r;
    begin
      for(i=0;i<count;i++) begin
        r=offset+PI_PROFILE*count+i;
        if(vec[r][3]) reset_hw();
        transact(r);
        if(gap_mode) idle((i*7+3)%11);
        if(gap_mode && i==count/2) idle(5000);
      end
    end
  endtask
  task automatic abort_at(input int phase,input int row);
    begin
      reset_hw();
      @(negedge clk); drive(row); input_valid=1;
      @(posedge clk); #2;
      repeat(phase) begin @(negedge clk); poison(); @(posedge clk); #2; end
      if(dut.eval_engine.busy) abort_eval++;
      if(dut.limiter_engine.sqrt_engine.busy) abort_sqrt++;
      if(dut.limiter_engine.div_engine.busy) abort_div++;
      if(dut.result_done && dut.work_error==0) abort_padding++;
      // Includes phase 255, immediately before the completion clock.
      #2; reset_n=0; #2;
      @(negedge clk); input_valid=0;
      @(negedge clk); reset_n=1;
      idle(LATENCY+2);
    end
  endtask
  task automatic held_pair(input int row);
    int i,k;
    begin
      reset_hw();
      @(negedge clk); input_valid=1; drive(row);
      for(i=0;i<2;i++) begin
        @(posedge clk); #2;
        for(k=1;k<=LATENCY;k++) begin
          @(negedge clk); poison(); driven_row=-1;
          @(posedge clk); #2;
        end
        // Never lower valid: the second request is accepted at N+257.
        @(negedge clk); drive(row+i+1);
      end
      input_valid=0; idle(LATENCY+2);
    end
  endtask
  task automatic missed_engine(input int which,input int row);
    begin
      reset_hw();
      // A successful saturation preamble makes every OLD register nonzero,
      // including both corrections and sat, so error hold is observable.
      transact(BASE+PI_PROFILE*DIRECTED+12);
      @(negedge clk); drive(row); input_valid=1;
      if(which==0) force dut.eval_output_valid=0;
      if(which==1) force dut.limit_output_valid=0;
      if(which==2) force dut.eval_ready=0;
      if(which==3) force dut.limit_ready=0;
      @(posedge clk); #2;
      @(negedge clk); input_valid=0;
      if(which<4) repeat(LATENCY) begin @(posedge clk); #2; end
      else begin
        repeat(LATENCY-1) begin @(posedge clk); #2; end
        @(negedge clk);
        if(which==4) force dut.result_done=0;
        if(which==5) force dut.eval_output_valid=1;
        if(which==6) force dut.limit_output_valid=1;
        @(posedge clk); #2;
      end
      release dut.eval_output_valid; release dut.limit_output_valid;
      release dut.eval_ready; release dut.limit_ready; release dut.result_done;
      idle(LATENCY+2);
    end
  endtask
  task automatic reset_on_edge(input bit at_completion,input int row);
    begin
      reset_hw();
      @(negedge clk); drive(row); input_valid=1;
      if(at_completion) begin
        @(posedge clk); #2;
        @(negedge clk); input_valid=0;
        repeat(LATENCY-1) begin @(posedge clk); #2; end
      end
      @(posedge clk); reset_n<=0; #2;
      if(output_valid!==0 || state_now()!==0 || visible_now()!==0) fail("edge reset did not win");
      @(negedge clk); input_valid=0;
      @(negedge clk); reset_n=1;
      idle(LATENCY+2);
    end
  endtask
  task automatic set_directed(input int row,input logic [1359:0] packed_row);
    for(int col=0;col<34;col++) vec[row][col]=packed_row[(33-col)*40+:40];
  endtask
  // Literal directed rows below are generated independently with Python pi_step.
  task automatic directed_vectors;
    begin
      set_directed(2466,1360'h0000000000000000000300000000000000000001000000000000000000000000008000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000022e66660000000000000000000000022e66660000000000000000000000000000000000011733000000000001000000000000000000000000000000004bd70a0000000000000000000000000000000000000000);
      set_directed(2467,1360'h00000000000000000003000000000100000000000000000000000000000000000080000000000000000000000000001800000000000000000000000000004bd70a000000000000000000000000000000000000000000027a3d700000000000000000000000027a3d700000000000000000000000000000000000013d1f0000000000010000000000000000000000000000000097ae140000000000000000000000000000000000000000);
      set_directed(2468,1360'h000000000000000000030000000002000000000000000000000000000000000000800000000000000000000000000018000000000000000000000000000097ae1400000000000000000000000000000000000000000002c6147a000000000000000000000002c6147a000000000000000000000000000000000001630a00000000000100000000000000000000000000000000e3851e0000000000000000000000000000000000000000);
      set_directed(2469,1360'h0000000000000000000300000000030000000000000000000000000000000000320000000032000000000000000000180000000000000000000000000000e3851e000000000000000000000000000000000000000000db0384f600da1fffd800000000000011ac11c4001199b5fc00c957733200c88649dc000008d609000008ccdb0014a813f300000000010000000001001e838506001d9fffe800c957733200c88649dc0000000001);
      set_directed(2470,1360'h0000000000000000000300000000040000000000000000000000000100000000008000000000000000000a0000000018000000000000000000000001001e838506001d9fffe800c957733200c88649dc00000000010020a8fc37000000000000000000000018f1082a00000000000007b7f40d000000000000000c7884000000000000c37fdd2800000000010000000001fff68aab9500000000000007b7f40d00000000000000000001);
      set_directed(2471,1360'h0000000000000000000300000000050000000000000000000000000000000001ce00000001ce00000000000000000018000000000000000000000000fff68aab9500000000000007b7f40d00000000000000000001ff1c6aabbdff25e000280000000000ffedfe5407ffeebde7c3ff2e6c57b6ff372218650001f6ff2a0001f75ef40014413f8600000000010000000001ffd75f7adfffe2600018ff2e6c57b6ff372218650000000001);
      set_directed(2472,1360'h000000000000000000030000000006000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000ffd75f7adfffe2600018ff2e6c57b6ff37221865000000000100000000000000000000000000000100000000000000000000ff2e6c57b6ff3722186500000000000000000000000000000000000000000000000000ffd75f7adfffe2600018ff2e6c57b6ff372218650000000001);
      set_directed(2473,1360'h000000000000000000030000000007000000000000000000000000000000000000000000000000000000000000000018000000000000010000000000ffd75f7adfffe2600018ff2e6c57b6ff37221865000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000);
      set_directed(2474,1360'h00000000000000000003000000000800000000000000000000000000000000000000010001ffffff000000000000001800000000000000000000000000000000000000000000000000000000000000000000000000000000045dfffffffba30000000000000000045dfffffffba30000000000000000000000000000020001fffffe0100000000000000000000000000000000000098ffffffff68000000000000000000000000000000);
      set_directed(2475,1360'h0000000000000000000300000000090000000000000000000000000000000001ff8000000000000000ffec00000000180000000000000000000000000000000098ffffffff68000000000000000000000000000000fffdd19a32fffd2e13e30000000000fffdd19a32fffd2e13e3000000000000000000000001fee8cd0001fe970a010000000000000000000000000000ffffb4298effffffff68000000000000000000000000000000);
      set_directed(2476,1360'h00000000000000000003000000000a000000000100000000000000000000000000800000000000000000000000000018000000000000000000000000001d9fffe8001d9fffe800c87d199400c87d199400000000010000000000000000000000000000030000000000000000000000c87d199400c87d199400000000000000000000000000000000000000000000000000001d9fffe8001d9fffe800c87d199400c87d19940000000001);
      set_directed(2477,1360'h00000000000000000003000000000b000000000100000000000000000000000000800000000000000000000000000018000000000000000000000000001d9fffe8001d9fffe800c87d199400c87d199400000000010000000000000000000000000000030000000000000000000000c87d199400c87d199400000000000000000000000000000000000000000000000000001d9fffe8001d9fffe800c87d199400c87d19940000000001);
      set_directed(2478,1360'h00000000000000000003000000000c0000000001000000000000000000000000320000000032000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000da1fffd800da1fffd800000000000011a2e6440011a2e64400c87d199400c87d1994000008d173000008d1730014b2dcad00000000010000000001001d9fffe8001d9fffe800c87d199400c87d19940000000001);
      set_directed(2479,1360'h0000000001000000000300000000000000000001000000000000000000000000008000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000045ccccd0000000000000000000000045ccccd0000000000000000000000000000000000022e660000000000010000000000000000000000000000000097ae140000000000000000000000000000000000000000);
      set_directed(2480,1360'h000000000100000000030000000001000000000000000000000000000000000000800000000000000000000000000018000000000000000000000000000097ae1400000000000000000000000000000000000000000004f47ae1000000000000000000000004f47ae10000000000000000000000000000000000027a3d000000000001000000000000000000000000000000012f5c280000000000000000000000000000000000000000);
      set_directed(2481,1360'h00000000010000000003000000000200000000000000000000000000000000000080000000000000000000000000001800000000000000000000000000012f5c28000000000000000000000000000000000000000000058c28f50000000000000000000000058c28f5000000000000000000000000000000000002c61400000000000100000000000000000000000000000001c70a3c0000000000000000000000000000000000000000);
      set_directed(2482,1360'h0000000001000000000300000000030000000000000000000000000000000000320000000032000000000000000000180000000000000000000000000001c70a3c000000000000000000000000000000000000000001b6070a5001b440001400000000000011ac11c3001199b5fc01a45af88d01a2a64a18000008d609000008ccdb000a5409f700000000010000000001003d070a0c003b3fffd001a45af88d01a2a64a180000000001);
      set_directed(2483,1360'h0000000001000000000300000000040000000000000000000000000100000000008000000000000000000a0000000018000000000000000000000001003d070a0c003b3fffd001a45af88d01a2a64a18000000000100415ae7a4000000000000000000000018f108300000000000002869df74000000000000000c788400000000000061b291c300000000010000000001ffe98c86be0000000000002869df7400000000000000000001);
      set_directed(2484,1360'h0000000001000000000300000000050000000000000000000000000000000001ce00000001ce00000000000000000018000000000000000000000000ffe98c86be0000000000002869df7400000000000000000001fe354c86aafe4bbfffec0000000000ffeded4b33ffeecfbf51fe475f3b77fe5cf0409b0001f6f6a60001f767e0000a16276c00000000010000000001ffa6375a45ffc4c00030fe475f3b77fe5cf0409b0000000001);
      set_directed(2485,1360'h000000000100000000030000000006000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000ffa6375a45ffc4c00030fe475f3b77fe5cf0409b000000000100000000000000000000000000000100000000000000000000fe475f3b77fe5cf0409b00000000000000000000000000000000000000000000000000ffa6375a45ffc4c00030fe475f3b77fe5cf0409b0000000001);
      set_directed(2486,1360'h000000000100000000030000000007000000000000000000000000000000000000000000000000000000000000000018000000000000010000000000ffa6375a45ffc4c00030fe475f3b77fe5cf0409b000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000);
      set_directed(2487,1360'h00000000010000000003000000000800000000000000000000000000000000000000010001ffffff00000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000000008bafffffff746000000000000000008bafffffff7460000000000000000000000000000040001fffffc010000000000000000000000000000000000012ffffffffed1000000000000000000000000000000);
      set_directed(2488,1360'h0000000001000000000300000000090000000000000000000000000000000001ff8000000000000000ffec0000000018000000000000000000000000000000012ffffffffed1000000000000000000000000000000fffba33462fffd2e134c0000000000fffba33462fffd2e134c000000000000000000000001fdd19a0001fe970a010000000000000000000000000000ffff68531bfffffffed1000000000000000000000000000000);
      set_directed(2489,1360'h00000000010000000003000000000a000000000100000000000000000000000000800000000000000000000000000018000000000000000000000000003b3fffd0003b3fffd001a29d19d101a29d19d100000000010000000000000000000000000000030000000000000000000001a29d19d101a29d19d100000000000000000000000000000000000000000000000000003b3fffd0003b3fffd001a29d19d101a29d19d10000000001);
      set_directed(2490,1360'h00000000010000000003000000000b000000000100000000000000000000000000800000000000000000000000000018000000000000000000000000003b3fffd0003b3fffd001a29d19d101a29d19d100000000010000000000000000000000000000030000000000000000000001a29d19d101a29d19d100000000000000000000000000000000000000000000000000003b3fffd0003b3fffd001a29d19d101a29d19d10000000001);
      set_directed(2491,1360'h00000000010000000003000000000c0000000001000000000000000000000000320000000032000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000001b440001401b440001400000000000011a2e6430011a2e64301a29d19d101a29d19d1000008d173000008d173000a596e5400000000010000000001003b3fffd0003b3fffd001a29d19d101a29d19d10000000001);
    end
  endtask
  initial begin
    load_file("golden_core_vectors.txt",0,GOLDEN,80,0);
    load_file("seeded_core_vectors.txt",GOLDEN,SEEDED,1024,1);
    load_file("error_core_vectors.txt",GOLDEN+SEEDED,ERRORS,129,2);
    directed_vectors();
    reset_hw(); idle(2);
    // Stateful one-amp updates and saturated/q-reset/full-reset/error priority.
    for(int r=BASE+PI_PROFILE*DIRECTED;r<BASE+PI_PROFILE*DIRECTED+10;r++) begin
      if(vec[r][3]) reset_hw();
      transact(r);
    end
    idle(5000);
    for(int mode=0;mode<2;mode++) begin
      replay(0,80,mode); replay(GOLDEN,1024,mode); replay(GOLDEN+SEEDED,129,mode);
    end
    held_pair(BASE+PI_PROFILE*DIRECTED);
    for(int phase=0;phase<LATENCY;phase++) abort_at(phase,BASE+PI_PROFILE*DIRECTED+12);
    reset_on_edge(0,BASE+PI_PROFILE*DIRECTED);
    reset_on_edge(1,BASE+PI_PROFILE*DIRECTED);
    for(int fault=0;fault<7;fault++) missed_engine(fault,BASE+PI_PROFILE*DIRECTED+10+(fault%2));
    reset_hw(); transact(BASE+PI_PROFILE*DIRECTED); idle(LATENCY+2);
    if(head!=tail || accepted!=completed+aborted || aborted!=258 || invalids!=129 || ranges!=128 || internals!=7 || completed!=2493)
      fail("independent final transaction/error/abort counts");
    if(abort_eval!=16 || abort_sqrt!=40 || abort_div!=72 || abort_padding!=75)
      fail("independent active evaluator/sqrt/divider/final-padding abort coverage");
    $display("CORE_ABORT_COVERAGE evaluator=%0d sqrt=%0d divider=%0d completed-private-padding=%0d phases=0..255 plus two simultaneous-edge resets",abort_eval,abort_sqrt,abort_div,abort_padding);
    $display("CORE_COUNTS profile=%0d accepted=%0d completed=%0d successful=%0d invalid_vdc=%0d range=%0d internal=%0d aborted=%0d latency=256 golden=80x2 seeded=1024x2 errors=128x2",PI_PROFILE,accepted,completed,successes,invalids,ranges,internals,aborted);
    $display("ALL STEP 6C2 PI DQ CORE TESTS PASSED"); $finish;
  end
  initial begin #100000000; fail("watchdog missing response/deadlock"); end
endmodule
module mc_pi_dq_core_p0_tb; mc_pi_dq_core_tb #(.PI_PROFILE(0)) test(); endmodule
module mc_pi_dq_core_p1_tb; mc_pi_dq_core_tb #(.PI_PROFILE(1)) test(); endmodule
