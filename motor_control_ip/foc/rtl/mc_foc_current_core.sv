`timescale 1ns/1ps
// Integration only: the accepted math blocks and C2's state owner are unchanged.
module mc_foc_current_core #(parameter int PI_PROFILE=0) (
  input logic clk,reset_n,enable,sample_valid,
  output logic sample_ready,
  input logic signed [23:0] ia,ib,ic,
  input logic [15:0] theta_e,
  input logic signed [31:0] we,
  input logic signed [24:0] id_ref,iq_ref,vdc,
  input logic pi_reset,uq_zero_en,
  output logic signed [25:0] duty_u,duty_v,duty_w,
  output logic result_valid,command_valid,
  output logic [1:0] error_code
);
  logic busy,needs_reset,result_done;
  logic [8:0] age;
  logic [1:0] work_error;
  logic [2:0] error_stage;
  logic signed [23:0] cap_ia,cap_ib,cap_ic;
  logic [15:0] cap_theta;
  logic signed [31:0] cap_we;
  logic signed [24:0] cap_id_ref,cap_iq_ref,cap_vdc;
  logic cap_pi_reset,cap_uq_zero;
  logic transform_start,transform_valid,pi_start,pi_ready,pi_valid;
  logic inv_start,inv_valid,svpwm_start,svpwm_ready,svpwm_valid;
  logic transform_sent,pi_sent,inv_sent,svpwm_sent;
  logic transform_done,pi_done,inv_done;
  logic signed [24:0] transform_alpha,transform_beta,transform_id,transform_iq;
  logic signed [17:0] transform_sin,transform_cos;
  logic signed [24:0] saved_alpha,saved_beta,saved_id,saved_iq;
  logic signed [17:0] saved_sin,saved_cos;
  logic signed [24:0] pi_ud,pi_uq,saved_ud,saved_uq;
  logic pi_limited,pi_sat;
  logic [1:0] pi_error,svpwm_error;
  logic signed [24:0] inv_alpha,inv_beta,saved_v_alpha,saved_v_beta;
  logic signed [25:0] svpwm_u,svpwm_v,svpwm_w,pending_u,pending_v,pending_w;
  logic [2:0] svpwm_sector;
  logic svpwm_overmodulated;
  logic stage_timing_error;

  assign sample_ready=reset_n && enable && !busy && !needs_reset;
  assign command_valid=result_valid && error_code==2'b00;
  // Age is zero just after top acceptance N. These pulses are already high
  // BEFORE the child acceptance edges N+1/N+8/N+266/N+270.
  assign transform_start=busy && age==0 && work_error==0;
  assign pi_start=busy && age==7 && transform_done && work_error==0 && pi_ready;
  assign inv_start=busy && age==265 && pi_done && work_error==0;
  assign svpwm_start=busy && age==269 && inv_done && work_error==0 && svpwm_ready;
  assign stage_timing_error=
    (transform_valid && (!transform_sent || age!=6)) ||
    (pi_valid && (!pi_sent || age!=264)) ||
    (inv_valid && (!inv_sent || age!=268)) ||
    (svpwm_valid && (!svpwm_sent || age!=398));

  mc_current_transform current_transform(
    .clk(clk),.reset_n(reset_n),.input_valid(transform_start),
    .ia(cap_ia),.ib(cap_ib),.ic(cap_ic),.theta_e(cap_theta),
    .output_valid(transform_valid),.i_alpha_dbg(transform_alpha),.i_beta_dbg(transform_beta),
    .sin_theta_dbg(transform_sin),.cos_theta_dbg(transform_cos),.id(transform_id),.iq(transform_iq));
  mc_pi_dq_core #(.PI_PROFILE(PI_PROFILE)) pi_core(
    .clk(clk),.reset_n(reset_n),.input_valid(pi_start),.input_ready(pi_ready),
    .id_meas(saved_id),.iq_meas(saved_iq),.id_ref(cap_id_ref),.iq_ref(cap_iq_ref),
    .we(cap_we),.vdc(cap_vdc),.pi_reset(cap_pi_reset),.uq_zero_en(cap_uq_zero),
    .output_valid(pi_valid),.ud_lim(pi_ud),.uq_lim(pi_uq),.error_code(pi_error),
    .limited(pi_limited),.sat_flag(pi_sat));
  mc_inv_park inverse_park(
    .clk(clk),.reset_n(reset_n),.input_valid(inv_start),.vd(saved_ud),.vq(saved_uq),
    .sin_theta(saved_sin),.cos_theta(saved_cos),.output_valid(inv_valid),
    .v_alpha(inv_alpha),.v_beta(inv_beta));
  mc_sector_svpwm svpwm(
    .clk(clk),.reset_n(reset_n),.input_valid(svpwm_start),.input_ready(svpwm_ready),
    .v_alpha(saved_v_alpha),.v_beta(saved_v_beta),.vdc(cap_vdc),
    .output_valid(svpwm_valid),.duty_u(svpwm_u),.duty_v(svpwm_v),.duty_w(svpwm_w),
    .sector(svpwm_sector),.overmodulated(svpwm_overmodulated),.error_code(svpwm_error));

  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      busy<=0; needs_reset<=0; age<=0; work_error<=0; error_stage<=0; result_done<=0;
      transform_sent<=0; pi_sent<=0; inv_sent<=0; svpwm_sent<=0;
      transform_done<=0; pi_done<=0; inv_done<=0;
      cap_ia<=0; cap_ib<=0; cap_ic<=0; cap_theta<=0; cap_we<=0;
      cap_id_ref<=0; cap_iq_ref<=0; cap_vdc<=0; cap_pi_reset<=0; cap_uq_zero<=0;
      saved_alpha<=0; saved_beta<=0; saved_id<=0; saved_iq<=0; saved_sin<=0; saved_cos<=0;
      saved_ud<=0; saved_uq<=0; saved_v_alpha<=0; saved_v_beta<=0;
      pending_u<=0; pending_v<=0; pending_w<=0;
      duty_u<=0; duty_v<=0; duty_w<=0; result_valid<=0; error_code<=0;
    end else begin
      result_valid<=0;
      if(sample_valid && sample_ready) begin
        busy<=1; age<=0; result_done<=vdc<=0; work_error<=vdc<=0 ? 2'b01 : 2'b00;
        error_stage<=vdc<=0 ? 3'd1 : 3'd0;
        cap_ia<=ia; cap_ib<=ib; cap_ic<=ic; cap_theta<=theta_e; cap_we<=we;
        cap_id_ref<=id_ref; cap_iq_ref<=iq_ref; cap_vdc<=vdc;
        cap_pi_reset<=pi_reset; cap_uq_zero<=uq_zero_en;
        transform_sent<=0; pi_sent<=0; inv_sent<=0; svpwm_sent<=0;
        transform_done<=0; pi_done<=0; inv_done<=0;
        pending_u<=0; pending_v<=0; pending_w<=0;
      end else if(busy) begin
        age<=age+1'b1;
        if(transform_start) transform_sent<=1;
        if(pi_start) pi_sent<=1;
        if(inv_start) inv_sent<=1;
        if(svpwm_start) svpwm_sent<=1;
        if(work_error==0) begin
          case(age)
            9'd6: begin
              if(!transform_valid) begin work_error<=3; needs_reset<=1; error_stage<=1; end
              else begin
                saved_alpha<=transform_alpha; saved_beta<=transform_beta;
                saved_id<=transform_id; saved_iq<=transform_iq;
                saved_sin<=transform_sin; saved_cos<=transform_cos; transform_done<=1;
              end
            end
            9'd7: if(!pi_ready || !transform_done) begin work_error<=3; needs_reset<=1; error_stage<=2; end
            9'd264: begin
              if(!pi_valid) begin work_error<=3; needs_reset<=1; error_stage<=2; end
              else if(pi_error!=0) begin
                work_error<=pi_error; result_done<=1; error_stage<=2;
                if(pi_error==3) needs_reset<=1;
              end else begin saved_ud<=pi_ud; saved_uq<=pi_uq; pi_done<=1; end
            end
            9'd268: begin
              if(!inv_valid) begin work_error<=3; needs_reset<=1; error_stage<=3; end
              else begin saved_v_alpha<=inv_alpha; saved_v_beta<=inv_beta; inv_done<=1; end
            end
            9'd269: if(!svpwm_ready || !inv_done) begin work_error<=3; needs_reset<=1; error_stage<=4; end
            9'd398: begin
              if(!svpwm_valid) begin work_error<=3; needs_reset<=1; error_stage<=4; end
              else begin
                result_done<=1; work_error<=svpwm_error;
                if(svpwm_error!=0) begin
                  error_stage<=4;
                  if(svpwm_error==3) needs_reset<=1;
                end else begin pending_u<=svpwm_u; pending_v<=svpwm_v; pending_w<=svpwm_w; end
              end
            end
            default: ;
          endcase
        end
        // Late/duplicate/unsolicited valid also poisons the current transaction.
        if(stage_timing_error) begin work_error<=3; needs_reset<=1; error_stage<=5; end
        if(age==511) begin
          busy<=0; result_valid<=1;
          if(result_done && work_error==0 && !stage_timing_error) begin
            duty_u<=pending_u; duty_v<=pending_v; duty_w<=pending_w; error_code<=0;
          end else begin
            duty_u<=0; duty_v<=0; duty_w<=0;
            error_code<=(work_error==0 || stage_timing_error) ? 2'b11 : work_error;
            if(work_error==0 || stage_timing_error) needs_reset<=1;
          end
        end
      end
    end
  end
endmodule
