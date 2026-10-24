
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


  logic enb;
  logic enb_1_5000_1;
  logic enb_1_5000_0;
  logic enb_1_1_1;
  logic signed [63:0] Clark_ialpha;
  logic signed [63:0] Clark_ibeta;
  logic signed [63:0] Park2_bypass_reg;
  logic signed [63:0] Clark_ialpha_1;
  logic signed [63:0] Park3_bypass_reg;
  logic signed [63:0] Clark_ibeta_1;
  logic signed [39:0] theta_e_1;
  logic signed [39:0] Park1_bypass_reg;
  logic signed [39:0] Read_theta_0_out1;
  logic signed [63:0] Park_O1;
  logic signed [63:0] Park_O2;
  logic signed [39:0] omega_e_1;
  logic PI_Reset_EN_1;
  logic [31:0] Vdc_V_1;
  logic [31:0] Vdc_V_2;
  logic signed [63:0] dq_voltage_limiter_du_q_z;
  logic signed [63:0] Iq_uq_raw;
  logic signed [63:0] dq_voltage_limiter_du_d_z;
  logic signed [63:0] Id_ud_raw;
  logic signed [63:0] ud;
  logic signed [63:0] uq;
  logic signed [39:0] InversePark1_bypass_reg;
  logic signed [39:0] Read_theta_1_out1;
  logic signed [63:0] InversePark_O1;
  logic signed [63:0] InversePark_O2;
  vector_of_signed_logic_64 rd_0_reg [0:2];
  logic signed [63:0] InversePark_O1_1;
  vector_of_signed_logic_64 rd_1_reg [0:2];
  logic signed [63:0] InversePark_O2_1;
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

  always_ff @(posedge clk)
    begin : Park2_bypass_process
      if (reset == 1'b1) begin
        Park2_bypass_reg <= 64'sh0000000000000000;
      end
      else begin
        if (enb_1_5000_1) begin
          Park2_bypass_reg <= Clark_ialpha;
        end
      end
    end

  assign Clark_ialpha_1 = (enb_1_5000_1 == 1'b1 ? Clark_ialpha :
              Park2_bypass_reg);

  always_ff @(posedge clk)
    begin : Park3_bypass_process
      if (reset == 1'b1) begin
        Park3_bypass_reg <= 64'sh0000000000000000;
      end
      else begin
        if (enb_1_5000_1) begin
          Park3_bypass_reg <= Clark_ibeta;
        end
      end
    end

  assign Clark_ibeta_1 = (enb_1_5000_1 == 1'b1 ? Clark_ibeta :
              Park3_bypass_reg);

  assign theta_e_1 = theta_e;
  always_ff @(posedge clk)
    begin : Park1_bypass_process
      if (reset == 1'b1) begin
        Park1_bypass_reg <= 40'sh0000000000;
      end
      else begin
        if (enb_1_5000_1) begin
          Park1_bypass_reg <= theta_e_1;
        end
      end
    end

  assign Read_theta_0_out1 = (enb_1_5000_1 == 1'b1 ? theta_e_1 :
              Park1_bypass_reg);

  Park u_Park (.clk(clk),
               .reset(reset),
               .enb_1_5000_0(enb_1_5000_0),
               .A(Clark_ialpha_1),
               .B(Clark_ibeta_1),
               .C(Read_theta_0_out1),
               .O1(Park_O1),
               .O2(Park_O2)
               );
  assign omega_e_1 = omega_e;
  assign PI_Reset_EN_1 = PI_Reset_EN;
  assign Vdc_V_1 = Vdc_V;
  always_ff @(posedge clk)
    begin : rd_01_process
      if (reset == 1'b1) begin
        Vdc_V_2 <= 32'b00000000000000000000000000000000;
      end
      else begin
        if (enb) begin
          Vdc_V_2 <= Vdc_V_1;
        end
      end
    end
  Iq u_Iq (.clk(clk),
           .reset(reset),
           .enb(enb),
           .enb_1_5000_1(enb_1_5000_1),
           .Iq_ref(iq_ref),
           .id(Park_O1),
           .iq_1(Park_O2),
           .we(omega_e_1),
           .du_q_z(dq_voltage_limiter_du_q_z),
           .PI_Reset_EN(PI_Reset_EN_1),
           .uq_raw(Iq_uq_raw)
           );
  Id u_Id (.clk(clk),
           .reset(reset),
           .enb(enb),
           .enb_1_5000_1(enb_1_5000_1),
           .id_ref(id_ref),
           .id_1(Park_O1),
           .iq(Park_O2),
           .we(omega_e_1),
           .du_d_z(dq_voltage_limiter_du_d_z),
           .PI_Reset_EN(PI_Reset_EN_1),
           .ud_raw(Id_ud_raw)
           );
  dq_voltage_limiter u_dq_voltage_limiter (.clk(clk),
                                           .reset(reset),
                                           .enb(enb),
                                           .enb_1_5000_1(enb_1_5000_1),
                                           .ud_raw(Id_ud_raw),
                                           .uq_raw(Iq_uq_raw),
                                           .Vdc_V(Vdc_V_2),
                                           .ud_lim(ud),
                                           .uq_lim(uq),
                                           .du_d_z(dq_voltage_limiter_du_d_z),
                                           .du_q_z(dq_voltage_limiter_du_q_z)
                                           );
  always_ff @(posedge clk)
    begin : InversePark1_bypass_process
      if (reset == 1'b1) begin
        InversePark1_bypass_reg <= 40'sh0000000000;
      end
      else begin
        if (enb_1_5000_1) begin
          InversePark1_bypass_reg <= theta_e_1;
        end
      end
    end

  assign Read_theta_1_out1 = (enb_1_5000_1 == 1'b1 ? theta_e_1 :
              InversePark1_bypass_reg);

  InversePark u_InversePark (.clk(clk),
                             .reset(reset),
                             .enb(enb),
                             .enb_1_5000_1(enb_1_5000_1),
                             .enb_1_5000_0(enb_1_5000_0),
                             .A(ud),
                             .B(uq),
                             .C(Read_theta_1_out1),
                             .O1(InversePark_O1),
                             .O2(InversePark_O2)
                             );
  always_ff @(posedge clk)
    begin : rd_0_process
      if (reset == 1'b1) begin
        rd_0_reg <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          rd_0_reg[0] <= InversePark_O1;
          rd_0_reg[32'sd1:32'sd2] <= rd_0_reg[32'sd0:32'sd1];
        end
      end
    end

  assign InversePark_O1_1 = rd_0_reg[2];

  always_ff @(posedge clk)
    begin : rd_1_process
      if (reset == 1'b1) begin
        rd_1_reg <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          rd_1_reg[0] <= InversePark_O2;
          rd_1_reg[32'sd1:32'sd2] <= rd_1_reg[32'sd0:32'sd1];
        end
      end
    end

  assign InversePark_O2_1 = rd_1_reg[2];

  SVPWMG u_SVPWMG (.clk(clk),
                   .reset(reset),
                   .enb(enb),
                   .Valpha(InversePark_O1_1),
                   .Vbeta(InversePark_O2_1),
                   .Vdc_V(Vdc_V_1),
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
