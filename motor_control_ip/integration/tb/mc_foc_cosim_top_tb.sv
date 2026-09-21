`timescale 1ns/1ps
module mc_foc_cosim_top_tb;
  logic clk=0,reset_n=0,run_enable=0;
  logic signed [23:0] ia=32768,ib=-16384,ic=-16384;
  logic [15:0] theta_e=0;
  logic signed [31:0] we=0;
  logic signed [24:0] id_ref=0,iq_ref=0,vdc=1572864;
  logic pi_reset=0,uq_zero_en=0;
  logic [11:0] cmp_u_active,cmp_v_active,cmp_w_active;
  logic [31:0] accepted_sample_id,active_command_id;
  logic active_valid,needs_reset;
  logic [2:0] fault_code;
  mc_foc_cosim_top dut(.*);
  always #10 clk=~clk;
  initial begin
    #500000; $fatal(1,"STEP7B_WRAPPER_FAIL timeout");
  end
  initial begin
    repeat(10) @(negedge clk);
    reset_n=1;run_enable=1;
    wait(active_command_id==1); #1;
    assert(accepted_sample_id>=1 && active_valid) else $fatal(1,"STEP7B_WRAPPER_FAIL valid");
    assert(cmp_u_active==1165 && cmp_v_active==1335 && cmp_w_active==1335)
      else $fatal(1,"STEP7B_WRAPPER_FAIL first CMP %d %d %d",cmp_u_active,cmp_v_active,cmp_w_active);
    assert(!needs_reset && fault_code==0) else $fatal(1,"STEP7B_WRAPPER_FAIL fault");
    @(negedge clk);run_enable=0; @(posedge clk);#1;
    assert(!active_valid) else $fatal(1,"STEP7B_WRAPPER_FAIL disable");
    @(negedge clk);run_enable=1; repeat(10) @(negedge clk);
    assert(!active_valid && needs_reset) else $fatal(1,"STEP7B_WRAPPER_FAIL stale recovery");
    reset_n=0;run_enable=0; repeat(5) @(negedge clk);
    assert(accepted_sample_id==0 && active_command_id==0 && !active_valid) else $fatal(1,"STEP7B_WRAPPER_FAIL reset");
    $display("STEP7B_FOC_WRAPPER_PASS first_cmp=1165,1335,1335 disable=1 reset_required=1 reset_ids=1");
    $finish;
  end
endmodule
