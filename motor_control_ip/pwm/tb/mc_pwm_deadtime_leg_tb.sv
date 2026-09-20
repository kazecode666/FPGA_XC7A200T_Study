`timescale 1ns/1ps
module mc_pwm_deadtime_leg_tb #(parameter int DEADTIME_CYCLES=25);
  logic clk=0,reset_n=0,gate_enable=0,pwm_req=0,gate_h,gate_l;
  always #10 clk=~clk;
  mc_pwm_deadtime_leg #(.DEADTIME_CYCLES(DEADTIME_CYCLES)) dut(.*);
  int edge_no=0,since=0,checked=0,h_rises=0,l_rises=0;
  int duty_cases=0,short_cases=0,cancel_cases=0,async_resets=0;
  bit live=0,target=0,expected_h=0,expected_l=0,prev_h=0,prev_l=0;
  always @(posedge clk) begin
    bit en,req;
    edge_no++;en=gate_enable;req=pwm_req;
    if(!reset_n || !en) live=0;
    else if(!live || req!=target) begin live=1;target=req;since=edge_no;end
    expected_h=live && edge_no-since>=DEADTIME_CYCLES && target;
    expected_l=live && edge_no-since>=DEADTIME_CYCLES && !target;
    #1;
    assert (!$isunknown({gate_h,gate_l}) && !(gate_h && gate_l)) else $fatal(1,"STEP6E_LEG_FAIL overlap/unknown");
    assert ({gate_h,gate_l} === {expected_h,expected_l}) else $fatal(1,"STEP6E_LEG_FAIL edge=%0d since=%0d got=%b%b expected=%b%b",edge_no,since,gate_h,gate_l,expected_h,expected_l);
    checked++;if(gate_h && !prev_h)h_rises++;if(gate_l && !prev_l)l_rises++;
    prev_h=gate_h;prev_l=gate_l;
  end
  task automatic hold(input bit en,req,input int cycles);
    @(negedge clk);gate_enable=en;pwm_req=req;
    repeat(cycles)begin @(posedge clk);#2;end
  endtask
  initial begin
    int before_h,width,period,high_length;
    repeat(2)@(negedge clk);reset_n=1;
    hold(1,1,DEADTIME_CYCLES+3);hold(1,0,DEADTIME_CYCLES+3);
    // Steady duty requests, including the distinction between 0% and disabled.
    period=4*(DEADTIME_CYCLES+3);
    for(int q=0;q<=4;q++)begin
      high_length=q*(period/4);
      repeat(2)begin
        if(high_length>0)hold(1,1,high_length);
        if(high_length<period)hold(1,0,period-high_length);
      end
      duty_cases++;
    end
    for(int delta=-1;delta<=1;delta++)begin
      hold(1,0,DEADTIME_CYCLES+3);before_h=h_rises;width=DEADTIME_CYCLES+delta;
      if(width==0)begin @(negedge clk);pwm_req=1;#2;pwm_req=0;end
      else hold(1,1,width);
      hold(1,0,DEADTIME_CYCLES+3);
      if(h_rises-before_h!=(delta==1?1:0))$fatal(1,"STEP6E_LEG_FAIL short pulse width=%0d",width);
      short_cases++;
    end
    // Restart waiting on a reversal; D=1 reverses at its exact terminal edge.
    hold(1,1,DEADTIME_CYCLES);hold(1,0,1);hold(1,1,DEADTIME_CYCLES+2);cancel_cases++;
    hold(0,0,2);hold(1,1,DEADTIME_CYCLES);hold(0,1,DEADTIME_CYCLES+2);cancel_cases++;
    hold(1,0,1);hold(0,0,DEADTIME_CYCLES+2);cancel_cases++;
    hold(1,1,DEADTIME_CYCLES+2);
    @(negedge clk);#3;reset_n=0;#1;
    if({gate_h,gate_l}!==2'b00)$fatal(1,"STEP6E_LEG_FAIL asynchronous reset");
    async_resets++;repeat(2)@(negedge clk);reset_n=1;
    hold(1,0,DEADTIME_CYCLES+3);
    hold(0,0,2);
    if(h_rises==0 || l_rises==0)$fatal(1,"STEP6E_LEG_FAIL no actual conduction");
    if(duty_cases!=5 || short_cases!=3 || cancel_cases!=3 || async_resets!=1)$fatal(1,"STEP6E_LEG_FAIL coverage");
    $display("ALL STEP 6E DEADTIME LEG TESTS PASSED deadtime=%0d checked=%0d h_rises=%0d l_rises=%0d duty=5 short=3 cancel=3 async_reset=1",DEADTIME_CYCLES,checked,h_rises,l_rises);$finish;
  end
endmodule
