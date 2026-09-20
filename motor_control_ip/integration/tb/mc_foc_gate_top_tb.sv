`timescale 1ns/1ps
module mc_foc_gate_top_tb #(parameter int PI_PROFILE=0,DEMO=1,DEADTIME_CYCLES=25);
  logic clk=0,reset_n=0,run_enable=0,sample_valid=0;
  logic signed [23:0] ia=0,ib=0,ic=0;
  logic [15:0] theta_e=0;
  logic signed [31:0] we=0;
  logic signed [24:0] id_ref=0,iq_ref=0,vdc=1572864;
  logic pi_reset=0,uq_zero_en=0;
  logic sample_request,sample_ready,pwm_u,pwm_v,pwm_w,needs_reset;
  logic [2:0] fault_code;
  logic trip_req=0,trip_latched,gate_uh,gate_ul,gate_vh,gate_vl,gate_wh,gate_wl;
  always #10 clk=~clk;
  mc_foc_gate_top #(.PI_PROFILE(PI_PROFILE),.DEADTIME_CYCLES(DEADTIME_CYCLES)) dut(.*);
  assign pwm_u=dut.pwm_u;
  assign pwm_v=dut.pwm_v;
  assign pwm_w=dut.pwm_w;
  longint signed vec[0:196][0:21];
  int sample_number=-1,accepted=0,loads=0,full_cycles=0,edge_number=0;
  int accept_edge=-1,command_edge=-1,command_row=-1,active_row=-1;
  int hu=0,hv=0,hw=0,period_count=0,last_accept=-1;
  bit checking=0;
  real ia_A,ib_A,ic_A,vdc_V,theta_rad,foc_mod_u,foc_mod_v,foc_mod_w;
  real high_duty_u,high_duty_v,high_duty_w;
  always_comb begin
    ia_A=real'($signed(ia))/32768.0;ib_A=real'($signed(ib))/32768.0;ic_A=real'($signed(ic))/32768.0;
    vdc_V=real'($signed(vdc))/32768.0;theta_rad=real'(theta_e)*6.283185307179586/65536.0;
    foc_mod_u=real'($signed(dut.control.foc_duty_u))/16777216.0;
    foc_mod_v=real'($signed(dut.control.foc_duty_v))/16777216.0;
    foc_mod_w=real'($signed(dut.control.foc_duty_w))/16777216.0;
    high_duty_u=real'(dut.control.adapter.high_u)/16777216.0;
    high_duty_v=real'(dut.control.adapter.high_v)/16777216.0;
    high_duty_w=real'(dut.control.adapter.high_w)/16777216.0;
  end
  task automatic fail(input string why);$fatal(1,"STEP6E_GATE_FAIL profile=%0d demo=%0d row=%0d edge=%0d %s",PI_PROFILE,DEMO,sample_number,edge_number,why);endtask
  task automatic eq(input string label,input longint signed a,b);if(a!==b)fail($sformatf("%s got=%0d expected=%0d",label,a,b));endtask
  task automatic read_vectors;
    string dir,line;int fd,status;longint extra;
    if(!$value$plusargs("VECTOR_DIR=%s",dir))dir=".";
    fd=$fopen({dir,"/step6d_pwm_vectors.txt"},"r");if(!fd)fail("fixture missing");
    status=$fgets(line,fd);if(status==0 || line[0]!=35)fail("fixture header");
    for(int r=0;r<197;r++)begin
      for(int c=0;c<22;c++)if($fscanf(fd,"%h",vec[r][c])!=1)fail("fixture field/count");
      if(r<162)begin eq("profile order",vec[r][1],r/81);eq("row order",vec[r][2],r%81);eq("kind",vec[r][0],r%81==80?1:0);end
      else if(r<172)begin eq("direction kind",vec[r][0],2);eq("direction index",vec[r][2],r-162);end
      else begin eq("demo kind",vec[r][0],3);eq("demo index",vec[r][2],r-172);end
    end
    if($fscanf(fd,"%h",extra)==1)fail("extra fixture row");$fclose(fd);
  endtask
  task automatic drive_row(input int r);
    sample_number=r;ia=vec[r][3];ib=vec[r][4];ic=vec[r][5];theta_e=vec[r][6];we=vec[r][7];
    id_ref=vec[r][8];iq_ref=vec[r][9];vdc=vec[r][10];pi_reset=vec[r][11];uq_zero_en=vec[r][12];
  endtask
  task automatic reset_hw;
    checking=0;@(negedge clk);run_enable=0;sample_valid=0;trip_req=0;#2;reset_n=0;#1;
    if(pwm_u || pwm_v || pwm_w || needs_reset || fault_code || dut.control.adapter_valid || dut.control.shadow_pending)fail("reset visible state");
    repeat(3)@(negedge clk);reset_n=1;
  endtask
  task automatic send_row(input int r);
    wait(sample_request);@(negedge clk);drive_row(r);sample_valid=1;
    @(posedge clk);if(!sample_ready)fail("peak response not accepted");
    @(negedge clk);sample_valid=0;
    // Other input fields deliberately stay stable until the next sample.
  endtask
  always @(posedge clk) begin : scoreboard
    bit accepted_now,handshake_now;int old_u,old_v,old_w;
    edge_number++;
    accepted_now=sample_valid && sample_ready;handshake_now=dut.control.cmp_handshake;
    old_u=dut.control.cmp_u_active;old_v=dut.control.cmp_v_active;old_w=dut.control.cmp_w_active;
    if(checking)begin
      if(accepted_now)begin
        if(last_accept>=0)eq("sample period",edge_number-last_accept,5000);
        last_accept=edge_number;accept_edge=edge_number;accepted++;
        if(!dut.control.carrier_peak || dut.control.transaction_pending)fail("accept window/slot");
      end
      if(handshake_now)begin
        eq("CMP latency",edge_number-accept_edge,516);
        if(edge_number-accept_edge>=2500 || dut.control.impending_zero)fail("late CMP");
        command_edge=edge_number;command_row=sample_number;
        eq("cmp u",dut.control.cmp_u_cmd,vec[command_row][16]);eq("cmp v",dut.control.cmp_v_cmd,vec[command_row][17]);eq("cmp w",dut.control.cmp_w_cmd,vec[command_row][18]);
      end
    end
    #1;
    if(checking)begin
      if(needs_reset || fault_code)fail("unexpected normal-flow fault");
      if(accepted_now)begin
        if(!dut.control.foc.busy)fail("C4 not accepted on same N");
        eq("captured angle",dut.control.foc.cap_theta,vec[sample_number][6]);
        eq("captured vdc",$signed(dut.control.foc.cap_vdc),vec[sample_number][10]);
      end
      if(dut.control.foc_result_valid)begin
        eq("FOC latency",edge_number-accept_edge,512);eq("FOC error",dut.control.foc_error_code,0);
        eq("FOC U",$signed(dut.control.foc_duty_u),vec[sample_number][13]);eq("FOC V",$signed(dut.control.foc_duty_v),vec[sample_number][14]);eq("FOC W",$signed(dut.control.foc_duty_w),vec[sample_number][15]);
      end
      if(dut.control.adapter_valid)eq("adapter valid latency",edge_number-accept_edge,515);
      if(handshake_now)begin
        if(!dut.control.shadow_pending)fail("no shadow after handshake");
        eq("shadow u",dut.control.cmp_u_shadow,vec[command_row][16]);eq("shadow v",dut.control.cmp_v_shadow,vec[command_row][17]);eq("shadow w",dut.control.cmp_w_shadow,vec[command_row][18]);
      end
      if(dut.control.carrier_zero)begin
        if(active_row>=0)begin
          eq("full period",period_count,5000);eq("HIGH U",hu,2*vec[active_row][16]);eq("HIGH V",hv,2*vec[active_row][17]);eq("HIGH W",hw,2*vec[active_row][18]);full_cycles++;

        end
        if(!dut.control.compare_load_event || command_row<0)fail("missing target ZERO load");
        eq("target ZERO",edge_number-accept_edge,2499);
        if(command_edge>=edge_number)fail("handshake not strictly before target ZERO");
        eq("active u",dut.control.cmp_u_active,vec[command_row][16]);eq("active v",dut.control.cmp_v_active,vec[command_row][17]);eq("active w",dut.control.cmp_w_active,vec[command_row][18]);
        if(!dut.control.transaction_pending)fail("slot released before load confirmation");
        active_row=command_row;loads++;hu=0;hv=0;hw=0;period_count=0;

      end else begin
        eq("held active u",dut.control.cmp_u_active,old_u);eq("held active v",dut.control.cmp_v_active,old_v);eq("held active w",dut.control.cmp_w_active,old_w);
        if(active_row<0 && (pwm_u || pwm_v || pwm_w))fail("startup not LOW");
      end
      if(active_row>=0)begin hu+=int'(pwm_u);hv+=int'(pwm_v);hw+=int'(pwm_w);period_count++;end
    end
  end
  // Independent edge-time model: no DUT countdown or target state is read.
  logic [2:0] raw_pwm,gate_h_vec,gate_l_vec;
  assign raw_pwm={pwm_w,pwm_v,pwm_u};
  assign gate_h_vec={gate_wh,gate_vh,gate_uh};
  assign gate_l_vec={gate_wl,gate_vl,gate_ul};
  int gate_edge=0,gate_checked=0,first_s=-1;
  int target_since[3]='{0,0,0},h_rises[3]='{0,0,0},l_rises[3]='{0,0,0};
  bit live[3]='{0,0,0},target[3]='{0,0,0};
  bit model_armed=0,model_trip=0,opened=0;
  bit [2:0] prev_h=0,prev_l=0;
  always @(posedge clk) begin : gate_reference
    bit allow_old,old_need;
    bit [2:0] req,eh,el;
    gate_edge++;req=raw_pwm;old_need=dut.control_needs_reset;
    allow_old=reset_n && run_enable && model_armed && !trip_req && !model_trip && !old_need;
    if(!reset_n)begin model_armed=0;model_trip=0;first_s=-1;opened=0;end
    else begin
      if(!run_enable || trip_req || model_trip || old_need)model_armed=0;
      else if(dut.pwm_command_loaded)model_armed=1;
      if(trip_req)model_trip=1;
    end
    for(int p=0;p<3;p++)begin
      if(!allow_old)live[p]=0;
      else if(!live[p] || req[p]!=target[p])begin live[p]=1;target[p]=req[p];target_since[p]=gate_edge;end
      eh[p]=live[p] && gate_edge-target_since[p]>=DEADTIME_CYCLES && target[p];
      el[p]=live[p] && gate_edge-target_since[p]>=DEADTIME_CYCLES && !target[p];
    end
    #1;
    if($isunknown({gate_h_vec,gate_l_vec}) || |(gate_h_vec & gate_l_vec))fail("overlap/unknown");
    if(gate_h_vec!==eh || gate_l_vec!==el)fail($sformatf("gate edge contract edge=%0d H=%b/%b L=%b/%b",gate_edge,gate_h_vec,eh,gate_l_vec,el));
    if(dut.armed!==model_armed || trip_latched!==model_trip)fail("arming/trip model");
    if(needs_reset!==(dut.control_needs_reset || trip_latched))fail("needs_reset aggregation");
    if(fault_code!==dut.control.fault_code)fail("fault code passthrough");
    if(first_s<0 && dut.pwm_command_loaded)first_s=gate_edge;
    if(!opened && |(gate_h_vec|gate_l_vec))begin
      if(first_s<0 || gate_edge-first_s!=DEADTIME_CYCLES+2)fail("first opening must be S+2+D");
      opened=1;
    end
    for(int p=0;p<3;p++)begin
      if(gate_h_vec[p] && !prev_h[p])begin
        eq("measured H deadtime",gate_edge-target_since[p],DEADTIME_CYCLES);h_rises[p]++;
      end
      if(gate_l_vec[p] && !prev_l[p])begin
        eq("measured L deadtime",gate_edge-target_since[p],DEADTIME_CYCLES);l_rises[p]++;
      end
    end
    prev_h=gate_h_vec;prev_l=gate_l_vec;gate_checked++;
  end
  task automatic all_off(input string label);
    if({gate_h_vec,gate_l_vec}!==6'b0)fail(label);
  endtask
  task automatic locked_check;
    repeat(5200)begin
      @(posedge clk);#2;all_off("stale gate after shutdown");
      if(dut.gate_enable || dut.armed || dut.control.pwm_cmd_valid || sample_request)fail("shutdown allowed stale work");
    end
  endtask
  task automatic start_zero;
    reset_hw();@(negedge clk);run_enable=1;send_row(PI_PROFILE*81);
    wait(dut.pwm_command_loaded);
  endtask
  task automatic protocol_tests;
    int trip_count=0,stop_count=0,early_trip=0,old_fault=0,recovery=0,held_trip=0,f_edge;
    // All trips are established before a sampling edge; no asynchronous claim.
    for(int mode=0;mode<4;mode++)begin
      start_zero();wait(gate_uh);
      if(mode==1)wait(gate_ul);
      if(mode>=2)begin
        wait(!pwm_u); // B: registered raw PWM changes after NBA.
        if(mode==2)repeat(2)@(posedge clk);
        else repeat(DEADTIME_CYCLES)@(posedge clk); // next edge is E+D.
        #2;
        if(gate_uh || gate_ul)fail("trip wait/terminal setup");
        if(mode==3)eq("trip exact terminal setup",gate_edge-target_since[0],DEADTIME_CYCLES-1);
      end
      @(negedge clk);trip_req=1;
      @(posedge clk);#2;all_off("trip sampling edge");
      if(!trip_latched || !needs_reset || dut.armed || fault_code!=0)fail("trip latch/code");
      @(negedge clk);trip_req=0;locked_check();
      @(negedge clk);run_enable=0;@(negedge clk);run_enable=1;
      @(posedge clk);#2;all_off("trip reopen");trip_count++;
    end
    start_zero();wait(gate_uh);wait(!pwm_u);@(posedge clk);#2;
    @(negedge clk);run_enable=0;@(posedge clk);#2;all_off("stop sampling edge");
    if(!needs_reset || dut.armed)fail("stop lock");
    @(negedge clk);run_enable=1;locked_check();stop_count++;
    // In-flight computation before first load: neither stop nor trip may arm L.
    for(int mode=0;mode<2;mode++)begin
      reset_hw();@(negedge clk);run_enable=1;send_row(PI_PROFILE*81);
      repeat(100)@(negedge clk);
      if(mode==0)run_enable=0;else trip_req=1;
      @(posedge clk);#2;all_off("pre-load shutdown");
      if(dut.armed || !needs_reset)fail("pre-load lock");
      @(negedge clk);run_enable=1;trip_req=0;locked_check();
      if(mode==0)stop_count++;else early_trip++;
    end
    // Missing next sample is a real old-control fault after gates are active.
    start_zero();wait(gate_ul);wait(dut.control_needs_reset);f_edge=gate_edge;
    @(posedge clk);#2;eq("control fault propagation",gate_edge-f_edge,1);
    all_off("old control F+1");if(fault_code!=3 || trip_latched)fail("old fault passthrough");
    locked_check();old_fault++;
    // Fresh hardware reset, fresh loaded command, full startup wait (model).
    start_zero();wait(gate_uh);if(needs_reset || trip_latched)fail("fresh recovery");
    @(negedge clk);run_enable=0;@(posedge clk);#2;all_off("recovery stop");recovery++;
    // trip is deliberately kept high across asynchronous reset and release.
    @(negedge clk);#2;reset_n=0;trip_req=1;run_enable=1;sample_valid=0;#1;all_off("async wrapper reset");
    repeat(3)@(negedge clk);reset_n=1;
    @(posedge clk);#2;all_off("trip held across reset");
    if(!trip_latched || !needs_reset)fail("held trip did not relatch");
    @(negedge clk);trip_req=0;locked_check();held_trip++;
    if(trip_count!=4 || stop_count!=2 || early_trip!=1 || old_fault!=1 || recovery!=1 || held_trip!=1)fail("protocol counts");
    $display("E6_SHUTDOWN_PASS trip_H_L_wait_terminal=4 stop=2 preload_trip=1 old_fault=1 fresh_reset=1 held_trip_reset=1 stop_trip_delay=0 control_fault_delay=1");
  endtask
  initial begin
    int count,start;read_vectors();reset_hw();
    if(DEMO && PI_PROFILE!=0)fail("demo is defined for profile0");
    count=DEMO?24:80;start=DEMO?172:PI_PROFILE*81;
    @(negedge clk);checking=1;run_enable=1;
    for(int n=0;n<=count;n++)send_row(start+n);
    wait(full_cycles==count);@(negedge clk);checking=0;run_enable=0;
    @(posedge clk);#1;if(pwm_u || pwm_v || pwm_w || !needs_reset || fault_code)fail("normal final stop");
    eq("normal accepts",accepted,count+1);eq("normal loads",loads,count+1);
    $display("E6_CHAIN_PASS profile=%0d demo=%0d base=%0d tail=1 accepts=%0d loads=%0d full_cycles=%0d foc_latency=512 cmp_latency=516 target_zero=2499",PI_PROFILE,DEMO,count,accepted,loads,full_cycles);
    for(int p=0;p<3;p++)if(h_rises[p]==0 || l_rises[p]==0)fail("no normal H/L conduction");
    $display("E6_GATE_EDGES checked=%0d H=%0d,%0d,%0d L=%0d,%0d,%0d first_open=S+%0d deadtime=%0d",gate_checked,h_rises[0],h_rises[1],h_rises[2],l_rises[0],l_rises[1],l_rises[2],DEADTIME_CYCLES+2,DEADTIME_CYCLES);
    if(DEMO)begin $display("STEP6E_DEMO_PASS samples=24 tail=1 full_cycles=24 stable_inputs=1 deadtime=%0d",DEADTIME_CYCLES);$finish;end
    protocol_tests();
    $display("ALL STEP 6E FOC GATE TESTS PASSED profile=%0d deadtime=%0d base=80 tail=1 full_cycles=80 shutdown=10",PI_PROFILE,DEADTIME_CYCLES);$finish;
  end
  initial begin #30000000;fail("watchdog");end
endmodule
