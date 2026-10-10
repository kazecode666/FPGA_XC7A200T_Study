// Study-L1 Checkpoint D simulation carrier. No FOC or PI arithmetic here.
// Both speed cores observe the same inputs; speed_backend is constant per run:
//   0 = Checkpoint B HDL Coder baseline shadow, 1 = Checkpoint C hand SV shadow.
// The original Simulink PI case observes backend 0 as a shadow only. In every
// case FOC iq_ref remains the external common Reference_Manager output.
// Speed words are raw codes: velocity S32/F20; iq S25/F15; other FLs below.
// Core output banks already update/hold all 14 fields on their valid event.
// The carrier selects those banks without an extra output register or delay.
`timescale 1ns/1ps
module study_l1_system_cosim_top (
  input wire clk, reset_n, run_enable,
  input wire signed [23:0] ia, ib, ic,
  input wire [15:0] theta_e,
  input wire signed [31:0] we,
  input wire signed [24:0] id_ref, iq_ref, vdc,
  input wire pi_reset, uq_zero_en,

  input wire speed_backend,
  input wire signed [31:0] speed_v_ref_mmps, speed_v_meas_mmps,
  input wire speed_enable, speed_pi_reset, speed_sample_tick,
  input wire speed_angle_init, speed_test_mode,

  output wire [11:0] cmp_u_active, cmp_v_active, cmp_w_active,
  output wire [31:0] accepted_sample_id, active_command_id,
  output wire active_valid, needs_reset,
  output wire [2:0] fault_code,

  output wire signed [24:0] speed_iq_ref_A,                 // S25/F15
  output wire signed [41:0] speed_iq_unlimited_A,           // S42/F30
  output wire signed [31:0] speed_integrator_A,             // S32/F30, old
  output wire speed_saturation_active,
  output wire signed [31:0] speed_integrator_next_A,        // S32/F30
  output wire signed [39:0] speed_previous_excess_A,         // S40/F30
  output wire signed [39:0] speed_excess_next_A,             // S40/F30
  output wire speed_hard_reset, speed_int_reset,
  output wire signed [41:0] speed_iq_limited_A,             // S42/F30
  output wire signed [32:0] speed_error_mmps,               // S33/F20
  output wire signed [39:0] speed_P_A, speed_KiTs_A, speed_AW_A, // S40/F30

  output logic speed_result_valid,
  output logic [31:0] speed_result_count, speed_source_count,
  output logic [63:0] speed_result_cycle, speed_source_cycle,
  output wire [63:0] speed_fabric_cycle,
  output logic [63:0] speed_first_edge_time_ns = 64'd0
);
  typedef struct packed {
    logic signed [24:0] iq_ref_A;
    logic signed [41:0] iq_unlimited_A;
    logic signed [31:0] integrator_A;
    logic saturation_active;
    logic signed [31:0] integrator_next_A;
    logic signed [39:0] previous_excess_A, excess_next_A;
    logic hard_reset, int_reset;
    logic signed [41:0] iq_limited_A;
    logic signed [32:0] error_mmps;
    logic signed [39:0] P_A, KiTs_A, AW_A;
  } speed_snapshot_t;

  wire speed_snapshot_t baseline, hand, selected;
  wire baseline_ce, hand_ce;
  wire speed_init_reset = !reset_n;
  logic tick_q, tick_previous, source_previous, backend_q, selected_backend;
  wire commit_event = tick_q && !tick_previous;
  wire source_event = speed_sample_tick && !source_previous;

  // Global simulator clock ordinal, not time since reset release. Ordinal 1
  // identifies the first rising clk edge. It keeps counting during reset;
  // captured event ordinals are therefore unambiguous across reset intervals.
  // Initial value is simulation bookkeeping, not a speed PI numerical state.
  logic [63:0] fabric_cycle = 64'd0;
  assign speed_fabric_cycle = fabric_cycle;
  always_ff @(posedge clk) begin
    fabric_cycle <= fabric_cycle + 64'd1;
    if (fabric_cycle == 0) speed_first_edge_time_ns <= $time;
  end

  mc_foc_cosim_top foc (
    .clk(clk), .reset_n(reset_n), .run_enable(run_enable),
    .ia(ia), .ib(ib), .ic(ic), .theta_e(theta_e), .we(we),
    .id_ref(id_ref), .iq_ref(iq_ref), .vdc(vdc),
    .pi_reset(pi_reset), .uq_zero_en(uq_zero_en),
    .cmp_u_active(cmp_u_active), .cmp_v_active(cmp_v_active), .cmp_w_active(cmp_w_active),
    .accepted_sample_id(accepted_sample_id), .active_command_id(active_command_id),
    .active_valid(active_valid), .needs_reset(needs_reset), .fault_code(fault_code)
  );

  HDLCore coder_baseline (
    .clk(clk), .init_reset(speed_init_reset), .clk_enable(1'b1),
    .v_ref_mmps(speed_v_ref_mmps), .v_meas_mmps(speed_v_meas_mmps),
    .enable(speed_enable), .pi_reset(speed_pi_reset), .sample_tick(speed_sample_tick),
    .angle_init(speed_angle_init), .test_mode(speed_test_mode), .ce_out(baseline_ce),
    .iq_ref_A(baseline.iq_ref_A), .iq_unlimited_A(baseline.iq_unlimited_A),
    .integrator_A(baseline.integrator_A), .saturation_active(baseline.saturation_active),
    .integrator_next_A(baseline.integrator_next_A), .previous_excess_A(baseline.previous_excess_A),
    .excess_next_A(baseline.excess_next_A), .hard_reset(baseline.hard_reset),
    .int_reset(baseline.int_reset), .iq_limited_A(baseline.iq_limited_A),
    .error_mmps(baseline.error_mmps), .P_A(baseline.P_A), .KiTs_A(baseline.KiTs_A), .AW_A(baseline.AW_A)
  );

  speed_pi_sv hand_sv (
    .clk(clk), .init_reset(speed_init_reset), .clk_enable(1'b1),
    .v_ref_mmps(speed_v_ref_mmps), .v_meas_mmps(speed_v_meas_mmps),
    .enable(speed_enable), .pi_reset(speed_pi_reset), .sample_tick(speed_sample_tick),
    .angle_init(speed_angle_init), .test_mode(speed_test_mode), .ce_out(hand_ce),
    .iq_ref_A(hand.iq_ref_A), .iq_unlimited_A(hand.iq_unlimited_A),
    .integrator_A(hand.integrator_A), .saturation_active(hand.saturation_active),
    .integrator_next_A(hand.integrator_next_A), .previous_excess_A(hand.previous_excess_A),
    .excess_next_A(hand.excess_next_A), .hard_reset(hand.hard_reset),
    .int_reset(hand.int_reset), .iq_limited_A(hand.iq_limited_A),
    .error_mmps(hand.error_mmps), .P_A(hand.P_A), .KiTs_A(hand.KiTs_A), .AW_A(hand.AW_A)
  );

  assign selected = selected_backend ? hand : baseline;
  assign speed_iq_ref_A = selected.iq_ref_A;
  assign speed_iq_unlimited_A = selected.iq_unlimited_A;
  assign speed_integrator_A = selected.integrator_A;
  assign speed_saturation_active = selected.saturation_active;
  assign speed_integrator_next_A = selected.integrator_next_A;
  assign speed_previous_excess_A = selected.previous_excess_A;
  assign speed_excess_next_A = selected.excess_next_A;
  assign speed_hard_reset = selected.hard_reset;
  assign speed_int_reset = selected.int_reset;
  assign speed_iq_limited_A = selected.iq_limited_A;
  assign speed_error_mmps = selected.error_mmps;
  assign speed_P_A = selected.P_A;
  assign speed_KiTs_A = selected.KiTs_A;
  assign speed_AW_A = selected.AW_A;

  // Mirror only the baseline/hand common input tick carrier and trigger memory.
  // This event is true BEFORE their output-bank commit edge, avoiding the extra
  // cycle that capturing an already-registered result_valid would introduce.
  // Source driven after edge k is captured on k+1 and commits on k+2 (40 ns).
  // Thus result_cycle-source_cycle=1: source_cycle denotes input capture, not
  // the preceding source-drive boundary. Hold tick low through reset/warmup;
  // the real first 0.9 ms event provides many low cycles before the first rise.
  always_ff @(posedge clk) begin
    if (speed_init_reset) begin
      tick_q<=0; tick_previous<=1; source_previous<=1;
      backend_q<=0; selected_backend<=0;
      speed_result_valid<=0;
      speed_result_count<=0; speed_source_count<=0;
      speed_result_cycle<=0; speed_source_cycle<=0;
    end else begin
      tick_q<=speed_sample_tick; tick_previous<=tick_q;
      source_previous<=speed_sample_tick; backend_q<=speed_backend;
      speed_result_valid<=commit_event;
      if (source_event) begin
        speed_source_count<=speed_source_count+32'd1;
        speed_source_cycle<=fabric_cycle+64'd1;
      end
      if (commit_event) begin
        selected_backend<=backend_q;
        speed_result_count<=speed_result_count+32'd1;
        speed_result_cycle<=fabric_cycle+64'd1;
      end
    end
  end

`ifndef SYNTHESIS
  // Behavioral XSI shadow check after both cores' nonblocking output commits.
  // It neither changes FOC timing nor adds any numerical correction path.
  always @(negedge clk) begin
    if (reset_n && speed_result_valid) begin
      if (baseline !== hand)
        $fatal(1,"STUDY_L1_D_SPEED_SHADOW_MISMATCH cycle=%0d",speed_result_cycle);
      if (baseline_ce !== 1'b1 || hand_ce !== 1'b1)
        $fatal(1,"STUDY_L1_D_SPEED_CE_MISMATCH cycle=%0d",speed_result_cycle);
      if (speed_result_count !== speed_source_count || speed_result_cycle !== speed_source_cycle+64'd1)
        $fatal(1,"STUDY_L1_D_SPEED_EVENT_MAPPING_MISMATCH cycle=%0d",speed_result_cycle);
    end
  end
`endif
endmodule
