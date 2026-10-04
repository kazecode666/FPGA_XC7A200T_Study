// Verification only. No PI arithmetic: expected words come from frozen B1 SLX.
`timescale 1ns/1ps
module study_l1_generated_tb;
  logic clk=0, init_reset=1, clk_enable=1;
  always #10 clk=~clk; // one physical 50 MHz clock
  logic signed [31:0] v_ref_mmps=0, v_meas_mmps=0;
  logic enable=1, pi_reset=0, sample_tick=0, angle_init=0, test_mode=0;
  wire ce_out;
  wire signed [24:0] iq_ref_A;
  wire signed [41:0] iq_unlimited_A, iq_limited_A;
  wire signed [31:0] integrator_A, integrator_next_A;
  wire signed [39:0] previous_excess_A, excess_next_A, P_A, KiTs_A, AW_A;
  wire signed [32:0] error_mmps;
  wire saturation_active, hard_reset, int_reset;
  HDLCore dut(.*);
  string vector_path, trace_path;
  integer fd, trace_fd, fields, row=0, ticks=0;
  integer wave_fd;
  integer ref_raw, meas_raw, en_cmd, rst_cmd, tick_cmd, angle_cmd, test_cmd;
  longint signed expected [0:13];
  longint signed actual [0:13];
  longint signed old_x, old_excess;
  time epoch, first_tick, last_tick;
  time launch_time;
  logic epoch_ready=0;
  // The generated ce_out is global CE, not transaction valid. Delay a source
  // rising-edge event by the two boundary pipeline registers reported by Coder.
  logic source_tick_d=0;
  logic [1:0] valid_pipe=0;
  wire result_valid=valid_pipe[1] && clk_enable;
  always @(posedge clk) begin
    if (init_reset) begin source_tick_d<=0; valid_pipe<=0; end
    else if (clk_enable) begin
      source_tick_d<=sample_tick;
      valid_pipe<={valid_pipe[0],sample_tick && !source_tick_d};
    end
  end
  // Small real edge traces for learning: first command, saturated reset,
  // disable and overspeed reset. Full long-run checking remains below.
  always @(posedge clk or negedge clk) begin
    #2;
    if (epoch_ready && (row==49 || row==449 || row==509 || row==1959) &&
        $time-launch_time<160)
      $fdisplay(wave_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
        row,$time-launch_time,clk,init_reset,pi_reset,sample_tick,clk_enable,result_valid,
        $signed(v_ref_mmps),$signed(v_meas_mmps),$signed(iq_ref_A),
        $signed(dut.u_PI.Integrator_out1),$signed(dut.u_PI.PreviousExcess_out1),hard_reset);
  end
  task automatic read_actual;
    actual[0]=$signed(iq_ref_A); actual[1]=$signed(iq_unlimited_A);
    actual[2]=$signed(integrator_A); actual[3]=saturation_active;
    actual[4]=$signed(integrator_next_A); actual[5]=$signed(previous_excess_A);
    actual[6]=$signed(excess_next_A); actual[7]=hard_reset;
    actual[8]=int_reset; actual[9]=$signed(iq_limited_A);
    actual[10]=$signed(error_mmps); actual[11]=$signed(P_A);
    actual[12]=$signed(KiTs_A); actual[13]=$signed(AW_A);
  endtask
  initial begin
    if (!$value$plusargs("VECTORS=%s",vector_path)) $fatal(1,"Missing VECTORS");
    if (!$value$plusargs("TRACE=%s",trace_path)) $fatal(1,"Missing TRACE");
    fd=$fopen(vector_path,"r"); trace_fd=$fopen(trace_path,"w");
    wave_fd=$fopen({trace_path,".cycles.csv"},"w");
    if (fd==0 || trace_fd==0) $fatal(1,"Cannot open evidence files");
    $fdisplay(trace_fd,"row,time_ns,clk,init_reset,pi_reset,source_tick,sample_tick,clk_enable,result_valid,ref_raw,meas_raw,iq_ref_raw,integrator_old_raw,integrator_next_raw,previous_excess_raw,excess_next_raw,hard_reset,int_reset");
    $fdisplay(wave_fd,"row,offset_ns,clk,init_reset,pi_reset,sample_tick,clk_enable,result_valid,ref_raw,meas_raw,iq_ref_raw,integrator_register_raw,excess_register_raw,hard_reset");
    repeat(4) @(posedge clk);
    @(negedge clk); init_reset=0;
    // Tick_delayed initializes to one: give it a low tick before the epoch.
    repeat(3) @(posedge clk);
    epoch=$time; epoch_ready=1;
    while (!$feof(fd)) begin
      fields=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
        ref_raw,meas_raw,en_cmd,rst_cmd,tick_cmd,angle_cmd,test_cmd,
        expected[0],expected[1],expected[2],expected[3],expected[4],expected[5],expected[6],
        expected[7],expected[8],expected[9],expected[10],expected[11],expected[12],expected[13]);
      if (fields!=21) $fatal(1,"Malformed B1 vector row %0d fields=%0d",row,fields);
      launch_time=$time;
      // NBA drives after this launch edge; inputs are captured on the next edge.
      v_ref_mmps<=ref_raw; v_meas_mmps<=meas_raw; enable<=en_cmd;
      pi_reset<=rst_cmd; sample_tick<=tick_cmd; angle_init<=angle_cmd; test_mode<=test_cmd;
      old_x=$signed(dut.u_PI.Integrator_out1);
      old_excess=$signed(dut.u_PI.PreviousExcess_out1);
      if (tick_cmd) begin
        if (ticks==0) begin
          first_tick=$time-epoch;
          if (first_tick!=900000) $fatal(1,"First tick phase is not 0.9 ms");
        end else if ($time-last_tick!=1000000) $fatal(1,"Tick period is not 1 ms");
        last_tick=$time; ticks=ticks+1;
      end
      @(posedge clk);
      @(negedge clk); sample_tick=0;
      @(posedge clk); #1; read_actual();
      if (result_valid!==tick_cmd[0]) $fatal(1,"Latency/valid alignment failed row %0d",row);
      for (integer k=0;k<14;k=k+1)
        if (actual[k]!==expected[k])
          $fatal(1,"B1 mismatch row=%0d tick=%0d signal=%0d RTL=%0d B1=%0d",row,ticks,k,actual[k],expected[k]);
      if (ce_out!==clk_enable) $fatal(1,"Unexpected ce_out");
      if (!tick_cmd && ($signed(dut.u_PI.Integrator_out1)!==old_x ||
                         $signed(dut.u_PI.PreviousExcess_out1)!==old_excess))
        $fatal(1,"State changed without a sample event at row %0d",row);
      $fdisplay(trace_fd,"%0d,%0d,1,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
        row,$time-epoch,init_reset,pi_reset,tick_cmd,sample_tick,clk_enable,result_valid,
        ref_raw,meas_raw,actual[0],actual[2],actual[4],actual[5],actual[6],hard_reset,int_reset);
      // Two elapsed clock edges above + 4998 = 100 us / 5000 physical cycles.
      repeat(4998) @(posedge clk);
      row=row+1;
    end
    if (row!=2580 || ticks!=258) $fatal(1,"Wrong source-vector counts");
    // Global CE idle hold and repeated-high tick edge semantics.
    old_x=$signed(dut.u_PI.Integrator_out1); old_excess=$signed(dut.u_PI.PreviousExcess_out1);
    clk_enable=0; pi_reset=1; enable=0;
    repeat(8) @(posedge clk);
    #1;
    if ($signed(dut.u_PI.Integrator_out1)!==old_x || $signed(dut.u_PI.PreviousExcess_out1)!==old_excess)
      $fatal(1,"Global CE low changed state");
    @(negedge clk); clk_enable=1; pi_reset=0; enable=1; sample_tick=1;
    repeat(3) @(posedge clk); #1;
    old_x=$signed(dut.u_PI.Integrator_out1); old_excess=$signed(dut.u_PI.PreviousExcess_out1);
    repeat(8) @(posedge clk); #1;
    if ($signed(dut.u_PI.Integrator_out1)!==old_x || $signed(dut.u_PI.PreviousExcess_out1)!==old_excess)
      $fatal(1,"Sustained high tick retriggered PI");
    epoch_ready=0; $fclose(fd); $fclose(trace_fd); $fclose(wave_fd);
    $display("STUDY_L1_XSIM_PASS rows=%0d ticks=%0d fields=14 raw_mismatches=0 first_phase_ns=%0d update_period_ns=1000000 pipeline_cycles=2 launch_to_valid_ns=40",row,ticks,first_tick);
    $finish;
  end
  initial begin #260000000; $fatal(1,"Simulation watchdog"); end
endmodule
