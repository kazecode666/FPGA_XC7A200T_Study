`timescale 1ns/1ps
module mc_foc_pwm_top_tb #(parameter int PI_PROFILE=0,DEMO=1);
  logic clk=0,reset_n=0,run_enable=0,sample_valid=0;
  logic signed [23:0] ia=0,ib=0,ic=0;
  logic [15:0] theta_e=0;
  logic signed [31:0] we=0;
  logic signed [24:0] id_ref=0,iq_ref=0,vdc=1572864;
  logic pi_reset=0,uq_zero_en=0;
  logic sample_request,sample_ready,pwm_u,pwm_v,pwm_w,needs_reset;
  logic [2:0] fault_code;
  logic pwm_command_loaded;
  always #10 clk=~clk;
  mc_foc_pwm_top #(.PI_PROFILE(PI_PROFILE)) dut(.*);
  longint signed vec[0:196][0:21];
  int sample_number=-1,accepted=0,loads=0,full_cycles=0,edge_number=0;
  int accept_edge=-1,command_edge=-1,command_row=-1,active_row=-1;
  int hu=0,hv=0,hw=0,period_count=0,last_accept=-1;
  bit checking=0;
  real ia_A,ib_A,ic_A,vdc_V,theta_rad,foc_mod_u,foc_mod_v,foc_mod_w;
  real high_duty_u,high_duty_v,high_duty_w;
  real active_vdc_V,active_alpha_V,active_beta_V,reconstructed_alpha_V,reconstructed_beta_V;
  real max_alpha_error=0.0,max_beta_error=0.0;
  always_comb begin
    ia_A=real'($signed(ia))/32768.0;ib_A=real'($signed(ib))/32768.0;ic_A=real'($signed(ic))/32768.0;
    vdc_V=real'($signed(vdc))/32768.0;theta_rad=real'(theta_e)*6.283185307179586/65536.0;
    foc_mod_u=real'($signed(dut.foc_duty_u))/16777216.0;
    foc_mod_v=real'($signed(dut.foc_duty_v))/16777216.0;
    foc_mod_w=real'($signed(dut.foc_duty_w))/16777216.0;
    high_duty_u=real'(dut.adapter.high_u)/16777216.0;
    high_duty_v=real'(dut.adapter.high_v)/16777216.0;
    high_duty_w=real'(dut.adapter.high_w)/16777216.0;
  end
  task automatic fail(input string why);$fatal(1,"D6_TOP_FAIL profile=%0d demo=%0d row=%0d edge=%0d %s",PI_PROFILE,DEMO,sample_number,edge_number,why);endtask
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
    checking=0;@(negedge clk);run_enable=0;sample_valid=0;#2;reset_n=0;#1;
    if(pwm_u || pwm_v || pwm_w || needs_reset || fault_code || dut.adapter_valid || dut.shadow_pending)fail("reset visible state");
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
    real alpha_error,beta_error;
    edge_number++;
    accepted_now=sample_valid && sample_ready;handshake_now=dut.cmp_handshake;
    old_u=dut.cmp_u_active;old_v=dut.cmp_v_active;old_w=dut.cmp_w_active;
    if(checking)begin
      if(accepted_now)begin
        if(last_accept>=0)eq("sample period",edge_number-last_accept,5000);
        last_accept=edge_number;accept_edge=edge_number;accepted++;
        if(!dut.carrier_peak || dut.transaction_pending)fail("accept window/slot");
      end
      if(handshake_now)begin
        eq("CMP latency",edge_number-accept_edge,516);
        if(edge_number-accept_edge>=2500 || dut.impending_zero)fail("late CMP");
        command_edge=edge_number;command_row=sample_number;
        eq("cmp u",dut.cmp_u_cmd,vec[command_row][16]);eq("cmp v",dut.cmp_v_cmd,vec[command_row][17]);eq("cmp w",dut.cmp_w_cmd,vec[command_row][18]);
      end
    end
    #1;
    if(checking)begin
      if(needs_reset || fault_code)fail("unexpected normal-flow fault");
      if(accepted_now)begin
        if(!dut.foc.busy)fail("C4 not accepted on same N");
        eq("captured angle",dut.foc.cap_theta,vec[sample_number][6]);
        eq("captured vdc",$signed(dut.foc.cap_vdc),vec[sample_number][10]);
      end
      if(dut.foc_result_valid)begin
        eq("FOC latency",edge_number-accept_edge,512);eq("FOC error",dut.foc_error_code,0);
        eq("FOC U",$signed(dut.foc_duty_u),vec[sample_number][13]);eq("FOC V",$signed(dut.foc_duty_v),vec[sample_number][14]);eq("FOC W",$signed(dut.foc_duty_w),vec[sample_number][15]);
      end
      if(dut.adapter_valid)eq("adapter valid latency",edge_number-accept_edge,515);
      if(handshake_now)begin
        if(!dut.shadow_pending)fail("no shadow after handshake");
        eq("shadow u",dut.cmp_u_shadow,vec[command_row][16]);eq("shadow v",dut.cmp_v_shadow,vec[command_row][17]);eq("shadow w",dut.cmp_w_shadow,vec[command_row][18]);
      end
      if(dut.carrier_zero)begin
        if(active_row>=0)begin
          eq("full period",period_count,5000);eq("HIGH U",hu,2*vec[active_row][16]);eq("HIGH V",hv,2*vec[active_row][17]);eq("HIGH W",hw,2*vec[active_row][18]);full_cycles++;
          reconstructed_alpha_V=active_vdc_V/3.0*(2.0*hu-hv-hw)/5000.0;
          reconstructed_beta_V=active_vdc_V/$sqrt(3.0)*(hv-hw)/5000.0;
          alpha_error=reconstructed_alpha_V-active_alpha_V;beta_error=reconstructed_beta_V-active_beta_V;
          if(alpha_error<0)alpha_error=-alpha_error;if(beta_error<0)beta_error=-beta_error;
          if(alpha_error>max_alpha_error)max_alpha_error=alpha_error;
          if(beta_error>max_beta_error)max_beta_error=beta_error;
          if(vec[active_row][2]==5 && PI_PROFILE==0)
            $display("D6_D_CURRENT active_row=%0d cmp=%0d,%0d,%0d high=%0d,%0d,%0d alpha_foc=%0.12f alpha_pwm=%0.12f",active_row,vec[active_row][16],vec[active_row][17],vec[active_row][18],hu,hv,hw,active_alpha_V,reconstructed_alpha_V);
        end
        if(!dut.compare_load_event || command_row<0)fail("missing target ZERO load");
        eq("target ZERO",edge_number-accept_edge,2499);
        if(command_edge>=edge_number)fail("handshake not strictly before target ZERO");
        eq("active u",dut.cmp_u_active,vec[command_row][16]);eq("active v",dut.cmp_v_active,vec[command_row][17]);eq("active w",dut.cmp_w_active,vec[command_row][18]);
        if(!dut.transaction_pending)fail("slot released before load confirmation");
        active_row=command_row;loads++;hu=0;hv=0;hw=0;period_count=0;
        active_vdc_V=real'(vec[active_row][10])/32768.0;
        active_alpha_V=real'(vec[active_row][19])/32768.0;active_beta_V=real'(vec[active_row][20])/32768.0;
      end else begin
        eq("held active u",dut.cmp_u_active,old_u);eq("held active v",dut.cmp_v_active,old_v);eq("held active w",dut.cmp_w_active,old_w);
        if(active_row<0 && (pwm_u || pwm_v || pwm_w))fail("startup not LOW");
      end
      if(active_row>=0)begin hu+=int'(pwm_u);hv+=int'(pwm_v);hw+=int'(pwm_w);period_count++;end
    end
  end
  task automatic expect_fault(input int code);
    repeat(3)begin @(posedge clk);#1;end
    if(!needs_reset || fault_code!=code || pwm_u || pwm_v || pwm_w || dut.pwm_cmd_valid || sample_request)fail("fault did not stop/gate");
    repeat(5100)begin @(posedge clk);#1;if(dut.pwm_cmd_valid || dut.compare_load_event || dut.shadow_pending || pwm_u || pwm_v || pwm_w)fail("stale command after fault");end
  endtask
  task automatic protocol_tests;
    int r;r=PI_PROFILE*81+5;
    reset_hw();@(negedge clk);run_enable=1;send_row(r);
    repeat(100)@(negedge clk);run_enable=0;
    @(posedge clk);#1;if(pwm_u || pwm_v || pwm_w || !needs_reset || dut.pwm_cmd_valid)fail("stop must act on clock edge");
    @(negedge clk);run_enable=1;expect_fault(0);
    reset_hw();@(negedge clk);run_enable=1;
    wait(sample_request);@(negedge clk);drive_row(r);vdc=0;sample_valid=1;
    @(posedge clk);@(negedge clk);sample_valid=0;
    wait(needs_reset);expect_fault(1);eq("FOC error retained",dut.last_foc_error,1);
    reset_hw();@(negedge clk);run_enable=1;send_row(r);repeat(100)@(negedge clk);reset_hw();
    repeat(600)begin @(posedge clk);#1;if(dut.pwm_cmd_valid || dut.shadow_pending || dut.compare_load_event)fail("reset stale");end
    // Deliberately hold the real PWM handshake beyond the target ZERO.
    @(negedge clk);run_enable=1;send_row(r);force dut.pwm.cmp_cmd_ready=0;
    wait(dut.impending_zero);@(posedge clk);
    if(dut.pwm_cmd_valid)fail("late command offered at target ZERO");
    #1;if(!needs_reset || fault_code!=2 || dut.compare_load_event)fail("deadline not detected");
    release dut.pwm.cmp_cmd_ready;expect_fault(2);
    reset_hw();@(negedge clk);run_enable=1;wait(dut.carrier_peak);
    @(posedge clk);#1;expect_fault(3);
    // Resource failure must be detected even if sample_request is suppressed.
    reset_hw();@(negedge clk);run_enable=1;wait(dut.carrier_peak);
    @(negedge clk);force dut.transaction_pending=1;sample_valid=1;
    @(posedge clk);#1;release dut.transaction_pending;
    @(negedge clk);sample_valid=0;expect_fault(3);
    $display("D6_PROTOCOL_PASS profile=%0d stop=1 invalid_bus=1 reset_abort=1 deadline=1 missing_sample=1 occupied_peak=1",PI_PROFILE);
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
    $display("D6_CHAIN_PASS profile=%0d demo=%0d base=%0d tail=1 accepts=%0d loads=%0d full_cycles=%0d foc_latency=512 cmp_latency=516 target_zero=2499",PI_PROFILE,DEMO,count,accepted,loads,full_cycles);
    $display("D6_ACTIVE_VOLTAGE_OBSERVATION profile=%0d demo=%0d max_alpha_error=%0.12f max_beta_error=%0.12f (all cases including clamp; no linearity claim)",PI_PROFILE,DEMO,max_alpha_error,max_beta_error);
    if(DEMO)begin $display("STEP6D_DEMO_PASS samples=24 tail=1 full_cycles=24 stable_inputs=1");$finish;end
    protocol_tests();
    $display("ALL STEP 6D FOC PWM TESTS PASSED profile=%0d base=80 tail=1 full_cycles=80 protocols=6",PI_PROFILE);$finish;
  end
  initial begin #30000000;fail("watchdog");end
endmodule
