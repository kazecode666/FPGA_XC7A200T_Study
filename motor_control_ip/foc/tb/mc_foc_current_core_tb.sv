`timescale 1ns/1ps
module mc_foc_current_core_tb #(parameter int PI_PROFILE=0);
  logic clk=0,reset_n=0,enable=1,sample_valid=0,sample_ready;
  logic signed [23:0] ia=0,ib=0,ic=0;
  logic [15:0] theta_e=0;
  logic signed [31:0] we=0;
  logic signed [24:0] id_ref=0,iq_ref=0,vdc=25'sd1572864;
  logic pi_reset=0,uq_zero_en=0;
  logic signed [25:0] duty_u,duty_v,duty_w;
  logic result_valid,command_valid;
  logic [1:0] error_code;
  always #10 clk=~clk;
  mc_foc_current_core #(.PI_PROFILE(PI_PROFILE)) dut(.*);
  localparam int ROWS=672,FIELDS=51;
  longint signed vec[0:ROWS-1][0:FIELDS-1];
  int accepted=0,responses=0,aborted=0,base_rows=0,earliest=0;
  int stage_launches[0:3]='{0,0,0,0};
  int edge_number=0,last_accept=-1,current_row=-1;
  int poisoned=0,blocked=0,errors=0,reset_probes=0;
  string vector_dir;
  always @(posedge clk) edge_number=edge_number+1;
  task automatic fail(input string why);
    $fatal(1,"C4_FAIL profile=%0d row=%0d edge=%0d: %s",PI_PROFILE,current_row,edge_number,why);
  endtask
  task automatic eq(input string label,input longint signed actual,expected);
    if(actual!==expected) fail($sformatf("%s got=%0d expected=%0d",label,actual,expected));
  endtask
  task automatic state_eq(input longint signed xd,xq,dd,dq,st);
    eq("state xd",$signed(dut.pi_core.xd_state),xd);
    eq("state xq",$signed(dut.pi_core.xq_state),xq);
    eq("state dd",$signed(dut.pi_core.du_d_state),dd);
    eq("state dq",$signed(dut.pi_core.du_q_state),dq);
    eq("state sat",dut.pi_core.sat_state,st);
  endtask
  task automatic row_state(input int r,input bit next_state);
    int k; k=next_state?33:13;
    state_eq(vec[r][k],vec[r][k+1],vec[r][k+2],vec[r][k+3],vec[r][k+4]);
  endtask
  task automatic read_vectors;
    int fd,status,rows,fields,ch,n; string line,token; longint signed parsed;
    fd=$fopen({vector_dir,"/foc_vectors.txt"},"r");
    if(!fd) fail("missing vector file");
    status=$fgets(line,fd);
    if(status==0 || line[0]!=35) fail("missing fixture header");
    rows=0;
    while(!$feof(fd)) begin
      status=$fgets(line,fd);
      if(status) begin
        if(rows>=ROWS) fail("extra fixture row");
        fields=0;token="";
        for(int i=0;i<=line.len();i++) begin
          ch=i==line.len()?32:line[i];
          if(ch==32 || ch==9 || ch==10 || ch==13) begin
            if(token.len()) begin
              if(fields>=FIELDS || token.len()!=16) fail("fixture field count/width");
              for(n=0;n<16;n++)
                if(!((token[n]>=48 && token[n]<=57)||(token[n]>=97 && token[n]<=102))) fail("fixture hex");
              if($sscanf(token,"%h",parsed)!=1) fail("fixture numeric parse");
              vec[rows][fields]=parsed;fields++;token="";
            end
          end else token={token,8'(ch)};
        end
        if(fields!=FIELDS) fail("fixture exact field count");
        if(vec[rows][0]!=rows || vec[rows][1]!=rows/336 || vec[rows][2]!=rows%336) fail("fixture identity/order");
        rows++;
      end
    end
    $fclose(fd);eq("fixture rows",rows,ROWS);
  endtask
  task automatic drive_row(input int r);
    current_row=r;
    ia=vec[r][3];ib=vec[r][4];ic=vec[r][5];theta_e=vec[r][6];we=vec[r][7];
    id_ref=vec[r][8];iq_ref=vec[r][9];vdc=vec[r][10];pi_reset=vec[r][11];uq_zero_en=vec[r][12];
  endtask
  task automatic reset_hw;
    @(negedge clk);sample_valid=0;enable=1;
    #3;reset_n=0;#1;
    if(result_valid || command_valid || sample_ready || duty_u!==0 || duty_v!==0 || duty_w!==0) fail("asynchronous visible reset");
    state_eq(0,0,0,0,0);
    repeat(3) @(negedge clk);reset_n=1;
    last_accept=-1;
  endtask
  task automatic launch(input int r,input int expected_spacing=0);
    @(negedge clk);drive_row(r);enable=1;sample_valid=1;
    @(posedge clk);
    if(!sample_ready) fail("expected actual sample acceptance");
    accepted++;#1;
    if(expected_spacing && last_accept>=0) eq("accept spacing",edge_number-last_accept,expected_spacing);
    last_accept=edge_number;
    if(sample_ready || result_valid) fail("capture must become busy");
  endtask
  task automatic check_transform(input int r);
    eq("alpha",$signed(dut.transform_alpha),vec[r][18]);eq("beta",$signed(dut.transform_beta),vec[r][19]);
    eq("sin",$signed(dut.transform_sin),vec[r][20]);eq("cos",$signed(dut.transform_cos),vec[r][21]);
    eq("id",$signed(dut.transform_id),vec[r][22]);eq("iq",$signed(dut.transform_iq),vec[r][23]);
  endtask
  task automatic check_pi(input int r);
    eq("PI error",dut.pi_error,0);
    eq("xd OLD",$signed(dut.pi_core.dbg_xd_old),vec[r][13]);eq("xq OLD",$signed(dut.pi_core.dbg_xq_old),vec[r][14]);
    eq("dd OLD",$signed(dut.pi_core.dbg_du_d_old),vec[r][15]);eq("dq OLD",$signed(dut.pi_core.dbg_du_q_old),vec[r][16]);
    eq("sat OLD",dut.pi_core.dbg_sat_old,vec[r][17]);
    eq("ud raw",$signed(dut.pi_core.dbg_ud_raw),vec[r][24]);eq("uq raw",$signed(dut.pi_core.dbg_uq_raw),vec[r][25]);
    eq("ud hi",$signed(dut.pi_core.dbg_ud_hi),vec[r][26]);eq("uq hi",$signed(dut.pi_core.dbg_uq_hi),vec[r][27]);
    eq("ud lim",$signed(dut.pi_ud),vec[r][28]);eq("uq lim",$signed(dut.pi_uq),vec[r][29]);
    eq("scale",dut.pi_core.dbg_scale,vec[r][30]);eq("limited",dut.pi_limited,vec[r][31]);eq("sat",dut.pi_sat,vec[r][32]);
    eq("xd NEXT",$signed(dut.pi_core.dbg_xd_next),vec[r][33]);eq("xq NEXT",$signed(dut.pi_core.dbg_xq_next),vec[r][34]);
    eq("dd NEXT",$signed(dut.pi_core.dbg_du_d_next),vec[r][35]);eq("dq NEXT",$signed(dut.pi_core.dbg_du_q_next),vec[r][36]);
  endtask
  task automatic check_svpwm(input int r);
    eq("sector",dut.svpwm_sector,vec[r][40]);eq("overmod",dut.svpwm_overmodulated,vec[r][41]);
    eq("T1",$signed(dut.svpwm.t1_debug),vec[r][42]);eq("T2",$signed(dut.svpwm.t2_debug),vec[r][43]);
    eq("L",$signed(dut.svpwm.l_debug),vec[r][44]);eq("M",$signed(dut.svpwm.m_debug),vec[r][45]);eq("H",$signed(dut.svpwm.h_debug),vec[r][46]);
    eq("SVPWM U",$signed(dut.svpwm_u),vec[r][47]);eq("SVPWM V",$signed(dut.svpwm_v),vec[r][48]);eq("SVPWM W",$signed(dut.svpwm_w),vec[r][49]);
    eq("SVPWM error",dut.svpwm_error,vec[r][50]);
  endtask
  task automatic transaction(input int r,input int period=5000,input bit disable_busy=0,input int spacing=0);
    launch(r,spacing);
    for(int n=1;n<=512;n++) begin
      @(negedge clk);
      // Poison every external input, including commands/angle/bus, while valid stays high.
      ia=n*713;ib=-n*811;ic=n*97;theta_e=n*153;we=-n*11119;
      id_ref=-n*257;iq_ref=n*397;vdc=-n;pi_reset=n[0];uq_zero_en=~n[0];sample_valid=1;
      if(disable_busy && n>=30) enable=0;
      @(posedge clk);
      if(sample_ready) fail("busy/completion edge accepted poison");
      eq("transform launch",dut.transform_start,n==1);eq("PI launch",dut.pi_start,n==8);
      eq("inverse launch",dut.inv_start,n==266);eq("SVPWM launch",dut.svpwm_start,n==270);
      if(dut.transform_start) stage_launches[0]++;
      if(dut.pi_start) stage_launches[1]++;
      if(dut.inv_start) stage_launches[2]++;
      if(dut.svpwm_start) stage_launches[3]++;
      #1;poisoned++;
      eq("transform output edge",dut.transform_valid,n==6);eq("PI output edge",dut.pi_valid,n==264);
      eq("inverse output edge",dut.inv_valid,n==268);eq("SVPWM output edge",dut.svpwm_valid,n==398);
      eq("result latency",result_valid,n==512);
      eq("command timing",command_valid,n==512);
      row_state(r,n>=264);
      if(n==6) check_transform(r);
      if(n==264) check_pi(r);
      if(n==268) begin
        eq("V alpha",$signed(dut.inv_alpha),vec[r][38]);eq("V beta",$signed(dut.inv_beta),vec[r][39]);
        eq("angle coherence sin",$signed(dut.saved_sin),vec[r][20]);eq("angle coherence cos",$signed(dut.saved_cos),vec[r][21]);
        eq("bus coherence",$signed(dut.cap_vdc),vec[r][10]);
      end
      if(n==398) check_svpwm(r);
    end
    responses++;
    eq("duty U",$signed(duty_u),vec[r][47]);eq("duty V",$signed(duty_v),vec[r][48]);eq("duty W",$signed(duty_w),vec[r][49]);eq("error",error_code,vec[r][50]);
    if(period>513) begin
      @(negedge clk);sample_valid=0;enable=1;
      repeat(period-513) begin
        @(posedge clk);#1;
        if(result_valid || command_valid) fail("idle duplicate result");
        row_state(r,1);
        eq("held U",$signed(duty_u),vec[r][47]);eq("held V",$signed(duty_v),vec[r][48]);eq("held W",$signed(duty_w),vec[r][49]);
      end
    end
  endtask
  task automatic invalid_bus(input int r,input int bus);
    @(negedge clk);drive_row(r);vdc=bus;pi_reset=1;enable=1;sample_valid=1;
    @(posedge clk);if(!sample_ready) fail("invalid bus acceptance");accepted++;#1;
    for(int n=1;n<=512;n++) begin
      @(negedge clk);sample_valid=0;
      @(posedge clk);
      if(dut.transform_start || dut.pi_start || dut.inv_start || dut.svpwm_start) fail("invalid bus launched child");
      #1;row_state(r,1);eq("invalid latency",result_valid,n==512);
    end
    responses++;errors++;
    if(error_code!==1 || command_valid || duty_u!==0 || duty_v!==0 || duty_w!==0 || dut.needs_reset) fail("invalid bus response");
  endtask
  task automatic reset_during(input int r,input int offset);
    reset_hw();launch(r);
    @(negedge clk);sample_valid=0;
    repeat(offset) @(posedge clk);
    #1;if(offset>264) row_state(r,1);
    reset_hw();aborted++;reset_probes++;
    repeat(520) begin @(posedge clk);#1;if(result_valid || command_valid) fail("stale result after reset");state_eq(0,0,0,0,0);end
  endtask
  task automatic downstream_fault(input int r,input bit missing);
    reset_hw();launch(r);
    for(int n=1;n<=512;n++) begin
      @(negedge clk);sample_valid=0;
      if(n==399) begin
        if(missing) force dut.svpwm_valid=0;
        else force dut.svpwm_error=2'b10;
      end
      @(posedge clk);#1;
      if(n==399) begin release dut.svpwm_valid;release dut.svpwm_error;end
      if(n>=264) row_state(r,1);
      eq("fault latency",result_valid,n==512);
    end
    responses++;errors++;
    eq("fault code",error_code,missing?3:2);
    if(command_valid || duty_u!==0 || duty_v!==0 || duty_w!==0) fail("error became duty command");
    eq("reset lock",dut.needs_reset,missing);
    @(negedge clk);sample_valid=missing;enable=1;
    repeat(20) begin
      @(posedge clk);if(missing && sample_ready) fail("internal fault accepted without reset");
      #1;row_state(r,1);if(result_valid) fail("duplicate error");
    end
  endtask
  initial begin
    if(!$value$plusargs("VECTOR_DIR=%s",vector_dir)) vector_dir=".";
    read_vectors();reset_hw();
    for(int i=0;i<336;i++) begin transaction(PI_PROFILE*336+i,5000,0,i?5000:0);base_rows++;end
    $display("C4_BASE_PASS profile=%0d historical=80 seeded=256 rows=336 spacing=5000",PI_PROFILE);
    reset_hw();
    for(int i=0;i<6;i++) begin transaction(PI_PROFILE*336+i,513,i==5,i?513:0);if(i)earliest++;end
    // The last d-current transaction has nonzero state and completed even with enable low.
    @(negedge clk);sample_valid=1;enable=0;
    repeat(20) begin @(posedge clk);if(sample_ready)fail("disabled accepted");#1;row_state(PI_PROFILE*336+5,1);blocked++;end
    invalid_bus(PI_PROFILE*336+5,0);invalid_bus(PI_PROFILE*336+5,-32768);
    reset_during(PI_PROFILE*336+5,100);reset_during(PI_PROFILE*336+5,300);
    downstream_fault(PI_PROFILE*336+5,0);
    downstream_fault(PI_PROFILE*336+5,1);
    reset_hw();transaction(PI_PROFILE*336,513);
    eq("base count",base_rows,336);eq("accepted count",accepted,349);eq("responses",responses,347);eq("aborts",aborted,2);
    eq("earliest count",earliest,5);eq("error count",errors,4);eq("reset probes",reset_probes,2);
    for(int i=0;i<4;i++) eq("normal launch count",stage_launches[i],343);
    $display("C4_PROTOCOL_PASS profile=%0d earliest=5 enable_blocked=20 busy_disable_complete=1 invalid_bus=2 reset_aborts=2 downstream_error=1 missing_valid=1 needs_reset_recovery=1",PI_PROFILE);
    $display("ALL STEP 6C4 FOC CURRENT TESTS PASSED profile=%0d base=336 accepted=%0d responses=%0d aborted=%0d latency=512 poisoned=%0d",PI_PROFILE,accepted,responses,aborted,poisoned);
    $finish;
  end
  initial begin #100000000;fail("watchdog");end
endmodule
