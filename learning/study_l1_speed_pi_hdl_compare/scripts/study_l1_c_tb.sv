// Common RTL scoreboard; expected numerical words come exclusively from B1 SLX.
`timescale 1ns/1ps
module study_l1_c_tb;
  logic clk=0, init_reset=1, clk_enable=1;
  always #10 clk=~clk;
  logic signed [31:0] v_ref_mmps=0, v_meas_mmps=0;
  logic enable=1, pi_reset=0, sample_tick=0, angle_init=0, test_mode=0;
  wire ce_out, result_valid;
  wire signed [24:0] iq_ref_A;
  wire signed [41:0] iq_unlimited_A, iq_limited_A;
  wire signed [31:0] integrator_A, integrator_next_A;
  wire signed [39:0] previous_excess_A, excess_next_A, P_A, KiTs_A, AW_A;
  wire signed [32:0] error_mmps;
  wire saturation_active, hard_reset, int_reset;
  speed_pi_compare dut(.*);
  string normal_path, stress_path, trace_path;
  integer trace_fd, rows=0, events=0, normal_events=0, stress_events=0;
  integer ce_stalls=0, idle_checks=0, sustained_checks=0;
  logic checking=0, previous=1, pending=0, expect_valid=0;
  longint signed expected[0:13], delayed[0:13], held[0:13], actual[0:13];
  longint signed row_id=0, delayed_row=0, committed_row=0;
  integer suite=0, last_valid_cycle=-999, cycle=0, consecutive_events=0;
  task automatic read_actual;
    actual[0]=$signed(iq_ref_A); actual[1]=$signed(iq_unlimited_A);
    actual[2]=$signed(integrator_A); actual[3]=saturation_active;
    actual[4]=$signed(integrator_next_A); actual[5]=$signed(previous_excess_A);
    actual[6]=$signed(excess_next_A); actual[7]=hard_reset;
    actual[8]=int_reset; actual[9]=$signed(iq_limited_A);
    actual[10]=$signed(error_mmps); actual[11]=$signed(P_A);
    actual[12]=$signed(KiTs_A); actual[13]=$signed(AW_A);
  endtask
  // Pre-edge event capture + known one-clock acceptance-to-output latency.
  // Expected state is NEVER computed from the RTL output or a PI reimplementation.
  always @(posedge clk) begin
    cycle=cycle+1;
    if (init_reset) begin
      previous=1; pending=0; expect_valid=0;
      for (integer k=0;k<14;k=k+1) begin held[k]=0; delayed[k]=0; end
    end else begin
      expect_valid=clk_enable && pending;
      if (clk_enable) begin
        if (pending) begin
          for (integer k=0;k<14;k=k+1) held[k]=delayed[k];
          committed_row=delayed_row;
        end
        pending=sample_tick && !previous;
        if (pending) begin
          for (integer k=0;k<14;k=k+1) delayed[k]=expected[k];
          delayed_row=row_id;
        end
        previous=sample_tick;
      end
    end
    #1;
    if (checking) begin
      if (result_valid!==expect_valid) $fatal(1,"VALID suite=%0d row=%0d",suite,row_id);
      if (ce_out!==clk_enable) $fatal(1,"CE mismatch");
      read_actual();
      for (integer k=0;k<14;k=k+1)
        if (actual[k]!==held[k])
          $fatal(1,"B1_RAW_MISMATCH suite=%0d row=%0d field=%0d actual=%0d expected=%0d",suite,committed_row,k,actual[k],held[k]);
      if (expect_valid) begin
        events=events+1;
        if (suite==0) normal_events=normal_events+1; else stress_events=stress_events+1;
        if (cycle-last_valid_cycle==2) consecutive_events=consecutive_events+1;
        last_valid_cycle=cycle;
        $fwrite(trace_fd,"%0d,%0d,%0t,%0d",suite,committed_row,$time,cycle);
        for (integer k=0;k<14;k=k+1) $fwrite(trace_fd,",%0d",actual[k]);
        $fwrite(trace_fd,"\n");
      end else begin
        idle_checks=idle_checks+1;
        if (sample_tick && previous) sustained_checks=sustained_checks+1;
      end
    end
  end
  task automatic boot;
    @(negedge clk); init_reset=1; clk_enable=0; sample_tick=0;
    repeat(3) @(negedge clk); // Synchronous init reset wins over CE low.
    init_reset=0; clk_enable=1;
    repeat(3) @(negedge clk);
  endtask
  task automatic run_vectors(input string path, input integer gap);
    integer fd, fields, count=0;
    integer ref_raw, meas_raw, en_cmd, rst_cmd, tick_cmd, angle_cmd, test_cmd;
    time epoch, last_tick;
    logic source_prev=0;
    begin
      fd=$fopen(path,"r"); if (!fd) $fatal(1,"Cannot open %s",path);
      epoch=$time;
      while (!$feof(fd)) begin
        fields=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
          ref_raw,meas_raw,en_cmd,rst_cmd,tick_cmd,angle_cmd,test_cmd,
          expected[0],expected[1],expected[2],expected[3],expected[4],expected[5],expected[6],
          expected[7],expected[8],expected[9],expected[10],expected[11],expected[12],expected[13]);
        if (fields!=21) $fatal(1,"Malformed row %0d",count);
        row_id=count;
        v_ref_mmps=ref_raw; v_meas_mmps=meas_raw; enable=en_cmd;
        pi_reset=rst_cmd; sample_tick=tick_cmd; angle_init=angle_cmd; test_mode=test_cmd;
        if (suite==0 && tick_cmd && !source_prev) begin
          if (normal_events==0 && $time-epoch!=900000) $fatal(1,"First phase");
          if (normal_events>0 && $time-last_tick!=1000000) $fatal(1,"Update interval");
          last_tick=$time;
        end
        source_prev=tick_cmd;
        repeat(gap) @(negedge clk);
        // Pause with a transaction in the carrier: check CE both idle and in flight.
        if (suite==1 && count==351) begin
          clk_enable=0; repeat(5) @(negedge clk); clk_enable=1; ce_stalls=ce_stalls+1;
        end
        count=count+1; rows=rows+1;
      end
      $fclose(fd); sample_tick=0; repeat(4) @(negedge clk);
      $display("SUITE_PASS suite=%0d rows=%0d gap_clocks=%0d",suite,count,gap);
    end
  endtask
  initial begin
    if (!$value$plusargs("NORMAL=%s",normal_path) || !$value$plusargs("STRESS=%s",stress_path) ||
        !$value$plusargs("TRACE=%s",trace_path)) $fatal(1,"Missing paths");
    trace_fd=$fopen(trace_path,"w"); if (!trace_fd) $fatal(1,"Cannot write trace");
    $fdisplay(trace_fd,"suite,row,time_ps,cycle,iq_ref,u,x_old,saturated,x_next,d_old,d_next,hard,int_reset,limited,error,P,KiTs,AW");
    boot(); checking=1; run_vectors(normal_path,5000);
    suite=1; boot(); run_vectors(stress_path,1);
    if (normal_events!=258 || consecutive_events<2000 || ce_stalls!=1 || idle_checks<12000000)
      $fatal(1,"Coverage gate normal=%0d continuous=%0d stalls=%0d idle=%0d",normal_events,consecutive_events,ce_stalls,idle_checks);
    boot(); // Also flush initialized state/valid under CE=0 after active histories.
    checking=0; $fclose(trace_fd);
    $display("STUDY_L1_C_XSIM_PASS rows=%0d events=%0d normal_events=%0d stress_events=%0d fields=14 raw_mismatches=0 continuous_pairs=%0d idle_clocks=%0d ce_inflight_stalls=%0d sustained_high_checks=%0d latency_clocks=2",rows,events,normal_events,stress_events,consecutive_events,idle_checks,ce_stalls,sustained_checks);
    $finish;
  end
  initial begin #270000000; $fatal(1,"Watchdog"); end
endmodule
