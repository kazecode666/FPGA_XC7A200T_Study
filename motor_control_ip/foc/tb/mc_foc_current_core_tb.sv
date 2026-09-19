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
  initial begin
    repeat(3) @(negedge clk); reset_n=1;
    @(negedge clk); sample_valid=1;
    @(posedge clk); if(!sample_ready) $fatal(1,"ZERO: not ready");
    @(negedge clk); sample_valid=0;
    for(int n=1;n<=512;n++) begin
      @(posedge clk); #1;
      if(result_valid !== (n==512)) $fatal(1,"ZERO: latency n=%0d",n);
    end
    if(error_code!==0 || !command_valid || duty_u!==26'sd8388608 ||
       duty_v!==26'sd8388608 || duty_w!==26'sd8388608)
      $fatal(1,"ZERO: result mismatch");
    $display("STEP6C4_ZERO_CHAIN_PASS latency=512 duty=8388608");
    $finish;
  end
  initial begin #200000; $fatal(1,"ZERO timeout"); end
endmodule
