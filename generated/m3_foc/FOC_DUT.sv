
`timescale 1ns/1ps

module FOC_DUT
          import FOC_DUT_pkg::* ;
          (  input logic clk,
             input logic reset,
             input logic reset_FOC_DUT_tc,
             input logic clk_enable,
             input logic signed [31:0] ia,
             input logic signed [31:0] ib,
             input logic signed [31:0] ic,
             input logic signed [39:0] theta_e,
             input logic signed [39:0] omega_e,
             input logic signed [31:0] iq_ref,
             input logic signed [31:0] id_ref,
             input logic PI_Reset_EN,
             input logic [31:0] Vdc_V,
             output logic ce_out,
             output logic [31:0] duty_u_cmd,
             output logic [31:0] duty_v_cmd,
             output logic [31:0] duty_w_cmd);


  logic enb_1_5000_0;
  logic enb;
  logic enb_1_5000_1;
  logic enb_1_1_1;
  logic signed [63:0] Clark_ialpha;
  logic signed [63:0] Clark_ibeta;
  logic signed [63:0] Park_O1;
  logic signed [63:0] Park_O2;
  logic signed [63:0] dq_voltage_limiter_du_q_z;
  logic signed [63:0] Iq_uq_raw;
  logic signed [63:0] dq_voltage_limiter_du_d_z;
  logic signed [63:0] Id_ud_raw;
  logic signed [63:0] ud;
  logic signed [63:0] uq;
  logic signed [63:0] InversePark_O1;
  logic signed [63:0] InversePark_O2;
  logic signed [63:0] SVPWMG_duty_u_cmd;
  logic signed [63:0] SVPWMG_duty_v_cmd;
  logic signed [63:0] SVPWMG_duty_w_cmd;
  logic [31:0] Encode_Duty_1_out1;
  logic [31:0] Encode_Duty_2_out1;
  logic [31:0] Encode_Duty_3_out1;


  Clark u_Clark (.ia(ia),
                 .ib(ib),
                 .ic(ic),
                 .ialpha(Clark_ialpha),
                 .ibeta(Clark_ibeta)
                 );
  FOC_DUT_tc u_FOC_DUT_tc (.clk(clk),
                           .reset(reset),
                           .reset_FOC_DUT_tc(reset_FOC_DUT_tc),
                           .clk_enable(clk_enable),
                           .enb(enb),
                           .enb_1_1_1(enb_1_1_1),
                           .enb_1_5000_0(enb_1_5000_0),
                           .enb_1_5000_1(enb_1_5000_1)
                           );

  Park u_Park (.clk(clk),
               .reset(reset),
               .enb_1_5000_0(enb_1_5000_0),
               .A(Clark_ialpha),
               .B(Clark_ibeta),
               .C(theta_e),
               .O1(Park_O1),
               .O2(Park_O2)
               );
  Iq u_Iq (.clk(clk),
           .reset(reset),
           .enb_1_5000_0(enb_1_5000_0),
           .Iq_ref(iq_ref),
           .id(Park_O1),
           .iq_1(Park_O2),
           .we(omega_e),
           .du_q_z(dq_voltage_limiter_du_q_z),
           .PI_Reset_EN(PI_Reset_EN),
           .uq_raw(Iq_uq_raw)
           );
  Id u_Id (.clk(clk),
           .reset(reset),
           .enb_1_5000_0(enb_1_5000_0),
           .id_ref(id_ref),
           .id_1(Park_O1),
           .iq(Park_O2),
           .we(omega_e),
           .du_d_z(dq_voltage_limiter_du_d_z),
           .PI_Reset_EN(PI_Reset_EN),
           .ud_raw(Id_ud_raw)
           );
  dq_voltage_limiter u_dq_voltage_limiter (.clk(clk),
                                           .reset(reset),
                                           .enb(enb),
                                           .enb_1_5000_1(enb_1_5000_1),
                                           .ud_raw(Id_ud_raw),
                                           .uq_raw(Iq_uq_raw),
                                           .Vdc_V(Vdc_V),
                                           .ud_lim(ud),
                                           .uq_lim(uq),
                                           .du_d_z(dq_voltage_limiter_du_d_z),
                                           .du_q_z(dq_voltage_limiter_du_q_z)
                                           );
  InversePark u_InversePark (.clk(clk),
                             .reset(reset),
                             .enb_1_5000_0(enb_1_5000_0),
                             .enb(enb),
                             .A(ud),
                             .B(uq),
                             .C(theta_e),
                             .O1(InversePark_O1),
                             .O2(InversePark_O2)
                             );
  SVPWMG u_SVPWMG (.clk(clk),
                   .reset(reset),
                   .enb(enb),
                   .Valpha(InversePark_O1),
                   .Vbeta(InversePark_O2),
                   .Vdc_V(Vdc_V),
                   .duty_u_cmd(SVPWMG_duty_u_cmd),
                   .duty_v_cmd(SVPWMG_duty_v_cmd),
                   .duty_w_cmd(SVPWMG_duty_w_cmd)
                   );
  assign Encode_Duty_1_out1 = (((SVPWMG_duty_u_cmd[63] == 1'b0) && (SVPWMG_duty_u_cmd[62:42] != 21'b000000000000000000000)) || ((SVPWMG_duty_u_cmd[63] == 1'b0) && (SVPWMG_duty_u_cmd[41:10] == 32'b11111111111111111111111111111111)) ? 32'b11111111111111111111111111111111 :
              (SVPWMG_duty_u_cmd[63] == 1'b1 ? 32'b00000000000000000000000000000000 :
              SVPWMG_duty_u_cmd[41:10] + (SVPWMG_duty_u_cmd[9] & (SVPWMG_duty_u_cmd[10] | (|SVPWMG_duty_u_cmd[8:0])))));
  assign duty_u_cmd = Encode_Duty_1_out1;

  assign Encode_Duty_2_out1 = (((SVPWMG_duty_v_cmd[63] == 1'b0) && (SVPWMG_duty_v_cmd[62:42] != 21'b000000000000000000000)) || ((SVPWMG_duty_v_cmd[63] == 1'b0) && (SVPWMG_duty_v_cmd[41:10] == 32'b11111111111111111111111111111111)) ? 32'b11111111111111111111111111111111 :
              (SVPWMG_duty_v_cmd[63] == 1'b1 ? 32'b00000000000000000000000000000000 :
              SVPWMG_duty_v_cmd[41:10] + (SVPWMG_duty_v_cmd[9] & (SVPWMG_duty_v_cmd[10] | (|SVPWMG_duty_v_cmd[8:0])))));
  assign duty_v_cmd = Encode_Duty_2_out1;

  assign Encode_Duty_3_out1 = (((SVPWMG_duty_w_cmd[63] == 1'b0) && (SVPWMG_duty_w_cmd[62:42] != 21'b000000000000000000000)) || ((SVPWMG_duty_w_cmd[63] == 1'b0) && (SVPWMG_duty_w_cmd[41:10] == 32'b11111111111111111111111111111111)) ? 32'b11111111111111111111111111111111 :
              (SVPWMG_duty_w_cmd[63] == 1'b1 ? 32'b00000000000000000000000000000000 :
              SVPWMG_duty_w_cmd[41:10] + (SVPWMG_duty_w_cmd[9] & (SVPWMG_duty_w_cmd[10] | (|SVPWMG_duty_w_cmd[8:0])))));
  assign duty_w_cmd = Encode_Duty_3_out1;

  assign ce_out = enb_1_1_1;

endmodule   
