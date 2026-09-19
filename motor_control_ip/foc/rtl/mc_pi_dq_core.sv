`timescale 1ns/1ps
// One accepted control transaction owns one update. Fabric clocks never integrate.
module mc_pi_dq_core #(parameter int PI_PROFILE=0) (
  input logic clk,reset_n,input_valid,
  input logic signed [24:0] id_meas,iq_meas,id_ref,iq_ref,
  input logic signed [31:0] we,
  input logic signed [24:0] vdc,
  input logic pi_reset,uq_zero_en,
  output logic input_ready,output_valid,
  output logic signed [24:0] ud_lim,uq_lim,
  output logic [1:0] error_code,
  output logic limited,sat_flag
);
  localparam logic [1:0] OK=2'b00,INVALID_VDC=2'b01,INTERNAL_ERROR=2'b11;
  generate
    if(PI_PROFILE!=0 && PI_PROFILE!=1) begin : g_invalid_profile
      initial $fatal(1,"mc_pi_dq_core PI_PROFILE must be 0 or 1");
    end
  endgenerate
  // Sole persistent state owner. These five registers only change at reset or
  // the successful +256 response, including a successful command reset.
  logic signed [39:0] xd_state,xq_state,du_d_state,du_q_state;
  logic sat_state;
  logic busy,eval_done,result_done;
  logic [7:0] count;
  logic [1:0] work_error;
  logic signed [24:0] cap_id,cap_iq,cap_id_ref,cap_iq_ref,cap_vdc;
  logic signed [31:0] cap_we;
  logic cap_pi_reset,cap_q_zero,cap_sat;
  logic signed [39:0] cap_xd,cap_xq,cap_du_d,cap_du_q;
  logic signed [39:0] candidate_xd,candidate_xq,candidate_ud,candidate_uq;
  logic signed [39:0] candidate_hd,candidate_hq,candidate_dd,candidate_dq;
  logic signed [24:0] candidate_dl,candidate_ql;
  logic [32:0] candidate_scale;
  logic candidate_limited,candidate_sat;

  // Response-aligned simulation observability; no extra top pins or KEEP.
  logic signed [39:0] dbg_xd_old,dbg_xq_old,dbg_du_d_old,dbg_du_q_old;
  logic dbg_sat_old;
  logic signed [39:0] dbg_ud_raw,dbg_uq_raw,dbg_xd_next,dbg_xq_next;
  logic signed [39:0] dbg_ud_hi,dbg_uq_hi,dbg_du_d_next,dbg_du_q_next;
  logic [32:0] dbg_scale;

  logic eval_input_valid,eval_ready,eval_output_valid;
  logic signed [39:0] eval_ud,eval_uq,eval_xd,eval_xq;
  logic [1:0] eval_error;
  logic limit_input_valid,limit_ready,limit_output_valid;
  logic signed [39:0] limit_hd,limit_hq,limit_dd,limit_dq;
  logic signed [24:0] limit_dl,limit_ql;
  logic [32:0] limit_scale;
  logic limit_limited,limit_sat,engine_timing_error;
  logic [1:0] limit_error;
  assign input_ready=reset_n && !busy;
  assign engine_timing_error=(eval_output_valid && count!=8'd17) ||
                             (limit_output_valid && count!=8'd180);
  // N+1 evaluate -> N+17 response -> N+18 capture.
  assign eval_input_valid=busy && count==8'd0 && work_error==OK;
  mc_pi_dq_eval #(.PI_PROFILE(PI_PROFILE)) eval_engine (
    .clk(clk),.reset_n(reset_n),.input_valid(eval_input_valid),
    .input_ready(eval_ready),.output_valid(eval_output_valid),
    .id_meas(cap_id),.iq_meas(cap_iq),.id_ref(cap_id_ref),.iq_ref(cap_iq_ref),
    .we(cap_we),.vdc(cap_vdc),.pi_reset(cap_pi_reset),.uq_zero_en(cap_q_zero),
    .xd_old(cap_xd),.xq_old(cap_xq),.du_d_old(cap_du_d),.du_q_old(cap_du_q),
    .ud_raw(eval_ud),.uq_raw(eval_uq),.xd_next(eval_xd),.xq_next(eval_xq),.error_code(eval_error)
  );
  // N+20 limit -> N+180 response -> N+181 capture; 75-clock final margin.
  assign limit_input_valid=busy && count==8'd19 && eval_done && work_error==OK;
  mc_dq_limiter limiter_engine (
    .clk(clk),.reset_n(reset_n),.input_valid(limit_input_valid),
    .input_ready(limit_ready),.output_valid(limit_output_valid),
    .ud_raw(candidate_ud),.uq_raw(candidate_uq),.vdc(cap_vdc),
    .ud_hi(limit_hd),.uq_hi(limit_hq),.du_d_next(limit_dd),.du_q_next(limit_dq),
    .ud_lim(limit_dl),.uq_lim(limit_ql),.scale(limit_scale),
    .limited(limit_limited),.sat_flag(limit_sat),.error_code(limit_error)
  );

  // Private captured/candidate registers need no asynchronous reset. Valid/error
  // control masks stale contents and every successful path overwrites them.
  always_ff @(posedge clk) begin
    if(reset_n) begin
      if(input_valid && input_ready) begin
        cap_id<=id_meas; cap_iq<=iq_meas; cap_id_ref<=id_ref; cap_iq_ref<=iq_ref;
        cap_we<=we; cap_vdc<=vdc; cap_pi_reset<=pi_reset; cap_q_zero<=uq_zero_en;
        cap_xd<=xd_state; cap_xq<=xq_state; cap_du_d<=du_d_state; cap_du_q<=du_q_state; cap_sat<=sat_state;
      end else if(busy) begin
        if(count==8'd17 && eval_output_valid && work_error==OK) begin
          candidate_ud<=eval_ud; candidate_uq<=eval_uq;
          candidate_xd<=eval_xd; candidate_xq<=eval_xq;
        end
        if(count==8'd180 && limit_output_valid && work_error==OK) begin
          candidate_hd<=limit_hd; candidate_hq<=limit_hq;
          candidate_dd<=limit_dd; candidate_dq<=limit_dq;
          candidate_dl<=limit_dl; candidate_ql<=limit_ql;
          candidate_scale<=limit_scale; candidate_limited<=limit_limited; candidate_sat<=limit_sat;
        end
      end
    end
  end
  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      busy<=0; count<=0; eval_done<=0; result_done<=0; work_error<=OK;
      xd_state<=0; xq_state<=0; du_d_state<=0; du_q_state<=0; sat_state<=0;
      output_valid<=0; ud_lim<=0; uq_lim<=0; error_code<=OK; limited<=0; sat_flag<=0;
      dbg_xd_old<=0; dbg_xq_old<=0; dbg_du_d_old<=0; dbg_du_q_old<=0; dbg_sat_old<=0;
      dbg_ud_raw<=0; dbg_uq_raw<=0; dbg_xd_next<=0; dbg_xq_next<=0;
      dbg_ud_hi<=0; dbg_uq_hi<=0; dbg_du_d_next<=0; dbg_du_q_next<=0; dbg_scale<=0;
    end else begin
      output_valid<=0;
      if(!busy) begin
        if(input_valid) begin
          busy<=1; count<=0; eval_done<=0;
          // Signed validation has priority even over command reset.
          work_error<=(vdc<=0)?INVALID_VDC:OK;
          result_done<=(vdc<=0);
        end
      end else begin
        count<=count+1'b1;
        if(work_error==OK) begin
          if(count==8'd0 && !eval_ready) work_error<=INTERNAL_ERROR;
          if(count==8'd17) begin
            if(!eval_output_valid) work_error<=INTERNAL_ERROR;
            else begin
              eval_done<=1; work_error<=eval_error;
              if(eval_error!=OK) result_done<=1;
            end
          end
          if(count==8'd19 && (!eval_done || !limit_ready)) work_error<=INTERNAL_ERROR;
          if(count==8'd180) begin
            if(!limit_output_valid) work_error<=INTERNAL_ERROR;
            else begin result_done<=1; work_error<=limit_error; end
          end
          // Unexpected early/late/duplicate engine pulses are invariant errors.
          if(engine_timing_error)
            work_error<=INTERNAL_ERROR;
        end
        if(count==8'd255) begin
          busy<=0; output_valid<=1;
          dbg_xd_old<=cap_xd; dbg_xq_old<=cap_xq;
          dbg_du_d_old<=cap_du_d; dbg_du_q_old<=cap_du_q; dbg_sat_old<=cap_sat;
          if(result_done && work_error==OK && !engine_timing_error) begin
            error_code<=OK;
            ud_lim<=candidate_dl; uq_lim<=candidate_ql;
            limited<=candidate_limited; sat_flag<=candidate_sat;
            // The only normal write site of ALL FIVE persistent registers.
            xd_state<=candidate_xd; xq_state<=candidate_xq;
            du_d_state<=candidate_dd; du_q_state<=candidate_dq; sat_state<=candidate_sat;
            dbg_ud_raw<=candidate_ud; dbg_uq_raw<=candidate_uq;
            dbg_xd_next<=candidate_xd; dbg_xq_next<=candidate_xq;
            dbg_ud_hi<=candidate_hd; dbg_uq_hi<=candidate_hq;
            dbg_du_d_next<=candidate_dd; dbg_du_q_next<=candidate_dq; dbg_scale<=candidate_scale;
          end else begin
            error_code<=(work_error==OK)?INTERNAL_ERROR:work_error;
            ud_lim<=0; uq_lim<=0; limited<=0; sat_flag<=0;
            dbg_ud_raw<=0; dbg_uq_raw<=0; dbg_ud_hi<=0; dbg_uq_hi<=0; dbg_scale<=0;
            dbg_xd_next<=cap_xd; dbg_xq_next<=cap_xq;
            dbg_du_d_next<=cap_du_d; dbg_du_q_next<=cap_du_q;
          end
        end
      end
    end
  end
endmodule
