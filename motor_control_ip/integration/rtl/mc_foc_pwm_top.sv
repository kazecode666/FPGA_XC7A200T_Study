`timescale 1ns/1ps
// One carrier, one sample slot, one command assigned to the next physical ZERO.
module mc_foc_pwm_top #(parameter int PI_PROFILE=0) (
  input logic clk,reset_n,run_enable,sample_valid,
  input logic signed [23:0] ia,ib,ic,
  input logic [15:0] theta_e,
  input logic signed [31:0] we,
  input logic signed [24:0] id_ref,iq_ref,vdc,
  input logic pi_reset,uq_zero_en,
  output logic sample_request,sample_ready,pwm_u,pwm_v,pwm_w,needs_reset,
  output logic [2:0] fault_code,
  output logic pwm_command_loaded
);
  logic started,operating,transaction_pending,cmp_sent,foc_seen,await_load;
  logic foc_ready,foc_result_valid,foc_command_valid;
  logic signed [25:0] foc_duty_u,foc_duty_v,foc_duty_w;
  logic [1:0] foc_error_code,last_foc_error;
  logic adapter_ready,adapter_valid,adapter_take,adapter_flush;
  logic [11:0] cmp_u_cmd,cmp_v_cmd,cmp_w_cmd;
  logic pwm_enable,pwm_cmd_valid,pwm_cmd_ready,cmp_handshake,sample_accept;
  logic [11:0] tbctr,cmp_u_shadow,cmp_v_shadow,cmp_w_shadow,cmp_u_active,cmp_v_active,cmp_w_active;
  logic count_up,carrier_zero,carrier_peak,shadow_pending,compare_load_event;
  logic impending_zero,resources_ready;
  logic [2:0] fault_now;
  logic [11:0] expected_u,expected_v,expected_w;
  logic [31:0] carrier_id,sample_cycle_id,active_cycle_id;

  assign pwm_command_loaded=compare_load_event;
  assign operating=reset_n && run_enable && !needs_reset;
  assign pwm_enable=operating;
  assign impending_zero=operating && tbctr==12'd1 && !count_up;
  assign resources_ready=foc_ready && adapter_ready && !shadow_pending && !transaction_pending;
  assign sample_request=operating && carrier_peak && !transaction_pending;
  assign sample_ready=sample_request && resources_ready;
  assign sample_accept=sample_valid && sample_ready;
  assign adapter_take=operating && transaction_pending && !foc_seen && foc_command_valid && fault_now==0;
  // Gate before the PWM port: disabled PWM otherwise accepts and preloads!
  assign pwm_cmd_valid=operating && transaction_pending && !cmp_sent && adapter_valid && !impending_zero && fault_now==0;
  assign cmp_handshake=pwm_cmd_valid && pwm_cmd_ready;
  assign adapter_flush=!operating;

  always_comb begin
    fault_now=0;
    if(operating) begin
      if(foc_result_valid && foc_error_code!=0) fault_now=1;
      else if((impending_zero && transaction_pending && !cmp_sent) ||
              (await_load && (!compare_load_event || !transaction_pending ||
               sample_cycle_id!=carrier_id-1'b1 || cmp_u_active!=expected_u ||
               cmp_v_active!=expected_v || cmp_w_active!=expected_w))) fault_now=2;
      else if((carrier_peak && (!resources_ready || !sample_valid)) ||
              (sample_valid && !carrier_peak) ||
              (foc_command_valid && (!transaction_pending || foc_seen || !adapter_ready)) ||
              (adapter_valid && (!transaction_pending || cmp_sent)) ||
              (compare_load_event && !await_load)) fault_now=3;
    end
  end

  mc_foc_current_core #(.PI_PROFILE(PI_PROFILE)) foc(
    .clk(clk),.reset_n(reset_n),.enable(operating),.sample_valid(sample_accept),.sample_ready(foc_ready),
    .ia(ia),.ib(ib),.ic(ic),.theta_e(theta_e),.we(we),.id_ref(id_ref),.iq_ref(iq_ref),.vdc(vdc),
    .pi_reset(pi_reset),.uq_zero_en(uq_zero_en),.duty_u(foc_duty_u),.duty_v(foc_duty_v),.duty_w(foc_duty_w),
    .result_valid(foc_result_valid),.command_valid(foc_command_valid),.error_code(foc_error_code));
  mc_duty_to_cmp adapter(.clk(clk),.reset_n(reset_n),.flush(adapter_flush),.input_valid(adapter_take),
    .input_ready(adapter_ready),.foc_duty_u(foc_duty_u),.foc_duty_v(foc_duty_v),.foc_duty_w(foc_duty_w),
    .cmp_u_cmd(cmp_u_cmd),.cmp_v_cmd(cmp_v_cmd),.cmp_w_cmd(cmp_w_cmd),.cmp_cmd_valid(adapter_valid),
    .cmp_cmd_ready(pwm_cmd_ready && pwm_cmd_valid));
  motor_pwm_core pwm(.clk(clk),.reset_n(reset_n),.pwm_enable(pwm_enable),
    .cmp_u_cmd(cmp_u_cmd),.cmp_v_cmd(cmp_v_cmd),.cmp_w_cmd(cmp_w_cmd),
    .cmp_cmd_valid(pwm_cmd_valid),.cmp_cmd_ready(pwm_cmd_ready),
    .pwm_u(pwm_u),.pwm_v(pwm_v),.pwm_w(pwm_w),.tbctr(tbctr),.count_up(count_up),
    .carrier_zero(carrier_zero),.carrier_peak(carrier_peak),.cmp_u_shadow(cmp_u_shadow),
    .cmp_v_shadow(cmp_v_shadow),.cmp_w_shadow(cmp_w_shadow),.cmp_u_active(cmp_u_active),
    .cmp_v_active(cmp_v_active),.cmp_w_active(cmp_w_active),.shadow_pending(shadow_pending),.compare_load_event(compare_load_event));

  always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      started<=0;needs_reset<=0;fault_code<=0;last_foc_error<=0;
      transaction_pending<=0;cmp_sent<=0;foc_seen<=0;await_load<=0;
      expected_u<=0;expected_v<=0;expected_w<=0;
      carrier_id<=0;sample_cycle_id<=0;active_cycle_id<=0;
    end else begin
      if(run_enable && !needs_reset) started<=1;
      if(started && !run_enable) needs_reset<=1;
      if(operating && fault_now!=0) begin
        needs_reset<=1;
        if(fault_code==0) fault_code<=fault_now;
        if(foc_result_valid) last_foc_error<=foc_error_code;
      end
      if(operating && fault_now==0) begin
        if(sample_accept) begin
          transaction_pending<=1;cmp_sent<=0;foc_seen<=0;sample_cycle_id<=carrier_id;
        end
        if(adapter_take) foc_seen<=1;
        if(cmp_handshake) begin
          cmp_sent<=1;expected_u<=cmp_u_cmd;expected_v<=cmp_v_cmd;expected_w<=cmp_w_cmd;
        end
        if(impending_zero) begin
          carrier_id<=carrier_id+1'b1;
          if(transaction_pending) await_load<=1;
        end
        if(await_load) begin
          transaction_pending<=0;await_load<=0;cmp_sent<=0;foc_seen<=0;
          active_cycle_id<=sample_cycle_id;
        end
      end
    end
  end
endmodule
