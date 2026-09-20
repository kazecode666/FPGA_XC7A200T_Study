`timescale 1ns/1ps
module mc_duty_to_cmp_tb;
  logic clk=0,reset_n=0,flush=0,input_valid=0,input_ready;
  logic signed [25:0] foc_duty_u=0,foc_duty_v=0,foc_duty_w=0;
  logic [11:0] cmp_u_cmd,cmp_v_cmd,cmp_w_cmd;
  logic cmp_cmd_valid,cmp_cmd_ready;
  logic pwm_enable=0,allow_cmd=1,pwm_ready,pwm_u,pwm_v,pwm_w;
  logic [11:0] tbctr,cmp_u_shadow,cmp_v_shadow,cmp_w_shadow,cmp_u_active,cmp_v_active,cmp_w_active;
  logic count_up,carrier_zero,carrier_peak,shadow_pending,compare_load_event;
  always #10 clk=~clk;
  assign cmp_cmd_ready=pwm_ready && allow_cmd;
  mc_duty_to_cmp dut(.*);
  motor_pwm_core pwm(.cmp_cmd_valid(cmp_cmd_valid && allow_cmd),.cmp_cmd_ready(pwm_ready),.*);
  task automatic fail(input string why);$fatal(1,"D6_ADAPTER_FAIL: %s",why);endtask
  task automatic convert(input int signed u,v,w,input int eu,ev,ew);
    @(negedge clk);if(!input_ready)fail("not ready");
    foc_duty_u=u;foc_duty_v=v;foc_duty_w=w;input_valid=1;
    @(posedge clk);#1;if(input_ready || cmp_cmd_valid)fail("Q capture");
    @(negedge clk);input_valid=0;foc_duty_u=-1;foc_duty_v=0;foc_duty_w=16777217;
    @(posedge clk);#1;if(input_ready || cmp_cmd_valid)fail("Q+1 product");
    @(posedge clk);#1;
    if(!cmp_cmd_valid || input_ready || cmp_u_cmd!=eu || cmp_v_cmd!=ev || cmp_w_cmd!=ew)fail("Q+2 compare");
  endtask
  int cycles=0,direction_cases=0,last_high_u,last_high_v,last_high_w;
  real max_error=0.0;
  task automatic wait_zero;
    do begin @(posedge clk);#1;end while(!carrier_zero);
  endtask
  task automatic measure(input int u,v,w);
    int hu,hv,hw;hu=0;hv=0;hw=0;
    // Enter on the initial ZERO after NBA; exclude the following ZERO.
    for(int n=0;n<5000;n++) begin
      if(cmp_u_active!=u || cmp_v_active!=v || cmp_w_active!=w)fail("active changed mid-cycle");
      hu+=int'(pwm_u);hv+=int'(pwm_v);hw+=int'(pwm_w);
      @(posedge clk);#1;
    end
    if(!carrier_zero || hu!=2*u || hv!=2*v || hw!=2*w)fail("HIGH count not 2*CMP over 5000 clocks");
    last_high_u=hu;last_high_v=hv;last_high_w=hw;
    cycles++;
  endtask
  task automatic applied_cycle(input int signed u,v,w,input int eu,ev,ew);
    int au,av,aw;au=cmp_u_active;av=cmp_v_active;aw=cmp_w_active;
    convert(u,v,w,eu,ev,ew);
    @(posedge clk);#1;
    if(!shadow_pending || cmp_u_shadow!=eu || cmp_v_shadow!=ev || cmp_w_shadow!=ew)fail("shadow tuple");
    while(!carrier_zero) begin
      if(cmp_u_active!=au || cmp_v_active!=av || cmp_w_active!=aw)fail("early active update");
      @(posedge clk);#1;
    end
    if(!compare_load_event)fail("missing ZERO load");
    measure(eu,ev,ew);
  endtask
  task automatic directions;
    string dir,line;int fd,status;longint signed r[0:21];real aa,bb,ea,eb;
    if(!$value$plusargs("VECTOR_DIR=%s",dir))dir=".";
    fd=$fopen({dir,"/step6d_pwm_vectors.txt"},"r");if(!fd)fail("fixture missing");
    status=$fgets(line,fd);if(status==0 || line[0]!=35)fail("header");
    for(int i=0;i<197;i++) begin
      for(int j=0;j<22;j++)if($fscanf(fd,"%h",r[j])!=1)fail("fixture field/count");
      if(r[0]==2) begin
        applied_cycle(r[13],r[14],r[15],r[16],r[17],r[18]);
        aa=48.0/3.0*(2.0*last_high_u/5000.0-last_high_v/5000.0-last_high_w/5000.0);
        bb=48.0/$sqrt(3.0)*(last_high_v/5000.0-last_high_w/5000.0);
        ea=aa-real'(r[19])/32768.0;eb=bb-real'(r[20])/32768.0;
        if(ea<0)ea=-ea;if(eb<0)eb=-eb;
        if(ea>0.0202 || eb>0.0202 || (r[19]!=0 && aa*real'(r[19])<=0) || (r[20]!=0 && bb*real'(r[20])<=0))fail("voltage magnitude/direction");
        if(ea>max_error)max_error=ea;if(eb>max_error)max_error=eb;
        direction_cases++;
      end
    end
    if($fscanf(fd,"%h",r[0])==1)fail("extra fixture data");$fclose(fd);
  endtask
  initial begin
    repeat(3)@(negedge clk);reset_n=1;pwm_enable=1;
    applied_cycle(16777216,8388608,0,0,1250,2500);
    applied_cycle(12582912,4194304,-1,625,1875,2500);
    applied_cycle(16777217,8960408,7816808,0,1165,1335);
    applied_cycle(14680064,-33554432,33554431,313,2500,0);
    // One held response, then consume the identical tuple.
    @(negedge clk);allow_cmd=0;
    convert(4194304,8388608,12582912,1875,1250,625);
    repeat(7) begin @(posedge clk);#1;if(!cmp_cmd_valid || input_ready || cmp_u_cmd!=1875 || cmp_v_cmd!=1250 || cmp_w_cmd!=625)fail("backpressure hold");end
    @(negedge clk);allow_cmd=1;
    @(posedge clk);#1;if(cmp_cmd_valid)fail("held command not consumed");
    wait_zero();measure(1875,1250,625);
    // Flush wins over input_valid and an available output receiver.
    @(negedge clk);allow_cmd=0;
    convert(0,0,0,2500,2500,2500);
    @(negedge clk);flush=1;allow_cmd=1;
    // Gate at the PWM boundary for this cancellation, as the integration must.
    force pwm.cmp_cmd_valid=0;
    @(posedge clk);#1;if(cmp_cmd_valid || input_ready)fail("flush did not cancel");
    @(negedge clk);flush=0;release pwm.cmp_cmd_valid;
    if(!input_ready)begin #1;if(!input_ready)fail("flush recovery");end
    wait_zero();measure(1875,1250,625);
    // Q old ctr4 ->3; Q+2 ->1; Q+3 handshake is the ZERO edge.
    do begin @(posedge clk);#1;end while(!(tbctr==4 && !count_up));
    convert(8388608,12582912,4194304,1250,625,1875);
    @(posedge clk);#1;
    if(!carrier_zero || compare_load_event || !shadow_pending || cmp_u_active!=1875)fail("same-ZERO bypass");
    measure(1875,1250,625);
    if(!compare_load_event)fail("same-ZERO command not deferred one period");
    measure(1250,625,1875);
    directions();
    if(cycles!=18 || direction_cases!=10)fail("test count");
    $display("ALL STEP 6D DUTY TO CMP TESTS PASSED cycles=18 direction=10 hold=1 flush=1 same_zero=1 max_voltage_error=%0.12f",max_error);$finish;
  end
  initial begin #10000000;fail("watchdog");end
endmodule
