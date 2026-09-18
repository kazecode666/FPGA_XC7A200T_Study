`timescale 1ns/1ps
module mc_park_tb;
  logic clk=0, reset_n=0, input_valid=0;
  logic signed [24:0] a=0,b=0,d,q,ia,ib,ra,rb;
  logic signed [17:0] s=0,c=0;
  logic pv,iv,rv;
  logic signed [17:0] sd[0:2],cd[0:2];
  logic [2:0] cv=0;
  integer mode=0, edge_index=0, head=0,tail=0,checked=0,next_id=0;
  integer ea[0:8191], eb[0:8191], due[0:8191], ids[0:8191];
  integer orig_a[0:8191],orig_b[0:8191];
  integer max_error=0, trip_checked=0, counts[0:2];
  string vector_dir;
  mc_park park(.clk(clk),.reset_n(reset_n),.input_valid(input_valid && mode!=1),
    .i_alpha(a),.i_beta(b),.sin_theta(s),.cos_theta(c),.output_valid(pv),.id(d),.iq(q));
  mc_inv_park inverse(.clk(clk),.reset_n(reset_n),.input_valid(input_valid && mode==1),
    .vd(a),.vq(b),.sin_theta(s),.cos_theta(c),.output_valid(iv),.v_alpha(ia),.v_beta(ib));
  // Real RTL cascade. Coefficients reach the inverse's acceptance edge with Park data.
  mc_inv_park roundtrip(.clk(clk),.reset_n(reset_n),.input_valid(pv),
    .vd(d),.vq(q),.sin_theta(sd[2]),.cos_theta(cd[2]),.output_valid(rv),.v_alpha(ra),.v_beta(rb));
  always #10 clk=~clk;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) cv<=0;
    else begin
      cv<={cv[1:0],input_valid && mode!=1};
      if(input_valid && mode!=1) begin sd[0]<=s;cd[0]<=c;end
      if(cv[0]) begin sd[1]<=sd[0];cd[1]<=cd[0];end
      if(cv[1]) begin sd[2]<=sd[1];cd[2]<=cd[1];end
    end
  end
  task automatic fail(input string message);
    $fatal(1,"PARK_TB_FAIL: %s",message);
  endtask
  task automatic drive(input bit valid,input integer x,y,si,co,ex,ey);
    @(negedge clk);
    input_valid=valid; a=x;b=y;s=si;c=co;
    if(valid) begin
      ea[tail]=ex;eb[tail]=ey;orig_a[tail]=x;orig_b[tail]=y;
      due[tail]=edge_index+1+((mode==2)?5:2); ids[tail]=next_id;
      tail++;next_id++;
    end
  endtask
  task automatic drain;
    repeat(7) drive(0,123,-987,321,-456,0,0);
    if(head!=tail) fail("queue not drained");
  endtask
  always @(posedge clk) begin : monitor
    bit ov;
    integer xa,xb,error_a,error_b;
    edge_index++;
    #1;
    if(!reset_n) begin
      if(pv!==0 || iv!==0 || rv!==0) fail("reset valid");
    end else begin
      ov=(mode==0)?pv:((mode==1)?iv:rv);
      xa=(mode==0)?$signed(d):((mode==1)?$signed(ia):$signed(ra));
      xb=(mode==0)?$signed(q):((mode==1)?$signed(ib):$signed(rb));
      if(ov) begin
        if(head>=tail) fail("unexpected valid");
        if(edge_index!=due[head]) fail($sformatf("id %0d latency expected %0d actual %0d",ids[head],due[head],edge_index));
        if(xa!==ea[head] || xb!==eb[head]) fail($sformatf("mode %0d id %0d actual %0d,%0d expected %0d,%0d",mode,ids[head],xa,xb,ea[head],eb[head]));
        if(mode==2) begin
          if(xa==16777215 || xa==-16777216 || xb==16777215 || xb==-16777216) fail("safe roundtrip saturated");
          error_a=xa-orig_a[head]; if(error_a<0) error_a=-error_a;
          error_b=xb-orig_b[head]; if(error_b<0) error_b=-error_b;
          if(error_a>max_error) max_error=error_a;
          if(error_b>max_error) max_error=error_b;
          trip_checked++;
        end
        head++; checked++;
      end else if(head<tail && edge_index>=due[head]) fail("missing fixed-latency output");
    end
  end
  task automatic fixtures(input integer which);
    string name,line;
    integer fd,status,n,x,y,theta,si,co,ex,ey,dx,qx;
    mode=which;
    name=(which==0)?"park_vectors.txt":((which==1)?"inv_park_vectors.txt":"park_roundtrip_vectors.txt");
    fd=$fopen({vector_dir,"/",name},"r");
    if(!fd) fail({"cannot read ",name});
    counts[which]=0;
    while(!$feof(fd)) begin
      status=$fgets(line,fd);
      if(which==2) n=$sscanf(line,"%d %d %d %d %d %d %d %d",x,y,si,co,dx,qx,ex,ey);
      else n=$sscanf(line,"%d %d %d %d %d %d %d",x,y,theta,si,co,ex,ey);
      if(n==((which==2)?8:7)) begin
        drive(1,x,y,si,co,ex,ey); counts[which]++;
        if(counts[which]%17==0) drive(0,-333,777,-888,999,0,0);
      end
    end
    $fclose(fd);drain();
    if(counts[which]<100) fail("insufficient deterministic fixtures");
  endtask
  initial begin
    if(!$value$plusargs("VECTOR_DIR=%s",vector_dir)) vector_dir="motor_control_ip/foc/tb/vectors";
    repeat(2) @(negedge clk); reset_n=1;
    for(integer m=0;m<3;m++) begin
      mode=m;
      // Independent, explicit identity and pi/2 sign checks in addition to Python fixtures.
      drive(1,32768,-65536,0,65536,32768,-65536);
      if(m==0) drive(1,32768,-65536,65536,0,-65536,-32768);
      else if(m==1) drive(1,32768,-65536,65536,0,65536,32768);
      else drive(1,32768,-65536,65536,0,32768,-65536);
      drain(); fixtures(m);
      // Reset with pipeline occupied and output valid: assertion occurs between clock edges.
      repeat(6) drive(1,32768,-65536,0,65536,32768,-65536);
      #3; reset_n=0;input_valid=0;head=0;tail=0;
      #1; if(pv!==0 || iv!==0 || rv!==0) fail("asynchronous reset failed");
      repeat(2) @(negedge clk);reset_n=1;
      drain();
      drive(1,32768,-65536,0,65536,32768,-65536);drain();
    end
    $display("Park rows=%0d inverse rows=%0d safe cascade rows=%0d checked=%0d",counts[0],counts[1],counts[2],checked);
    $display("Unsaturated RTL roundtrip max raw LSB=%0d physical error=%0.12f (saturation excluded)",max_error,max_error/32768.0);
    $display("Latency acceptance N -> standalone N+2, RTL cascade N+5");
    $display("ALL STEP 6C1 PARK TESTS PASSED");$finish;
  end
  initial begin #1000000;fail("timeout");end
endmodule
