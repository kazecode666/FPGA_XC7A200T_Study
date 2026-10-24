
`timescale 1ns/1ps

module Iq
          import FOC_DUT_pkg::* ;
          (  input logic clk,
             input logic reset,
             input logic enb_1_5000_0,
             input logic signed [31:0] Iq_ref,
             input logic signed [63:0] id,
             input logic signed [63:0] iq_1,
             input logic signed [39:0] we,
             input logic signed [63:0] du_q_z,
             input logic PI_Reset_EN,
             output logic signed [63:0] uq_raw);


  logic signed [63:0] Sum_sub_cast;
  logic signed [64:0] Sum_sub_cast_1;
  logic signed [64:0] Sum_sub_cast_2;
  logic signed [64:0] Sum_sub_temp;
  logic signed [63:0] e_q;
  logic signed [127:0] alpha_mul_temp;
  logic signed [63:0] uq_p;
  logic signed [127:0] alpha_mul_temp_1;
  logic signed [63:0] KiTs_q_e_q;
  logic signed [127:0] Gain_mul_temp;
  logic signed [63:0] u_q_aw;
  logic signed [63:0] Reset_Zero_out1;
  logic signed [63:0] x_q_z_out1;
  logic signed [64:0] Add2_stage2_add_cast;
  logic signed [64:0] Add2_stage2_add_cast_1;
  logic signed [64:0] Add2_stage2_add_temp;
  logic signed [63:0] Add2_op_stage1;
  logic signed [64:0] Add2_stage3_sub_cast;
  logic signed [64:0] Add2_stage3_sub_cast_1;
  logic signed [64:0] Add2_stage3_sub_temp;
  logic signed [63:0] x_q_next;
  logic signed [63:0] Reset_Integral_out1;
  logic signed [64:0] Add1_add_cast;
  logic signed [64:0] Add1_add_cast_1;
  logic signed [64:0] Add1_add_temp;
  logic signed [63:0] Add1_out1;
  logic signed [63:0] Ld_out1;
  logic signed [127:0] Product_mul_temp;
  logic signed [63:0] Product_out1;
  logic signed [63:0] Constant_out1;
  logic signed [64:0] Add_add_cast;
  logic signed [64:0] Add_add_cast_1;
  logic signed [64:0] Add_add_temp;
  logic signed [63:0] Add_out1;
  logic signed [103:0] Product1_mul_temp;
  logic signed [63:0] Ed;
  logic signed [64:0] Sum1_add_cast;
  logic signed [64:0] Sum1_add_cast_1;
  logic signed [64:0] Sum1_add_temp;
  logic signed [63:0] Sum1_out1;
  logic signed [63:0] Reset_Output_out1;

      

  assign Sum_sub_cast = {{16{Iq_ref[31]}}, {Iq_ref, 16'b0000000000000000}};
  assign Sum_sub_cast_1 = {Sum_sub_cast[63], Sum_sub_cast};
  assign Sum_sub_cast_2 = {iq_1[63], iq_1};
  assign Sum_sub_temp = Sum_sub_cast_1 - Sum_sub_cast_2;
  assign e_q = ((Sum_sub_temp[64] == 1'b0) && (Sum_sub_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Sum_sub_temp[64] == 1'b1) && (Sum_sub_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Sum_sub_temp[63:0])));
  assign alpha_mul_temp = 64'sh000008B99999999A * e_q;
  assign uq_p = (((alpha_mul_temp[127] == 1'b0) && (alpha_mul_temp[126:103] != 24'b000000000000000000000000)) || ((alpha_mul_temp[127] == 1'b0) && (alpha_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((alpha_mul_temp[127] == 1'b1) && (alpha_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(alpha_mul_temp[103:40]) + $signed({1'b0, alpha_mul_temp[39] & (alpha_mul_temp[40] | (|alpha_mul_temp[38:0]))})));
  assign alpha_mul_temp_1 = 64'sh0000012F5C28F5C3 * e_q;
  assign KiTs_q_e_q = (((alpha_mul_temp_1[127] == 1'b0) && (alpha_mul_temp_1[126:103] != 24'b000000000000000000000000)) || ((alpha_mul_temp_1[127] == 1'b0) && (alpha_mul_temp_1[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((alpha_mul_temp_1[127] == 1'b1) && (alpha_mul_temp_1[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(alpha_mul_temp_1[103:40]) + $signed({1'b0, alpha_mul_temp_1[39] & (alpha_mul_temp_1[40] | (|alpha_mul_temp_1[38:0]))})));
  assign Gain_mul_temp = 64'sh00000022C4E0C07A * du_q_z;
  assign u_q_aw = (((Gain_mul_temp[127] == 1'b0) && (Gain_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Gain_mul_temp[127] == 1'b0) && (Gain_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain_mul_temp[127] == 1'b1) && (Gain_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Gain_mul_temp[103:40]) + $signed({1'b0, Gain_mul_temp[39] & (Gain_mul_temp[40] | (|Gain_mul_temp[38:0]))})));
  assign Reset_Zero_out1 = 64'sh0000000000000000;
  assign Add2_stage2_add_cast = {x_q_z_out1[63], x_q_z_out1};
  assign Add2_stage2_add_cast_1 = {KiTs_q_e_q[63], KiTs_q_e_q};
  assign Add2_stage2_add_temp = Add2_stage2_add_cast + Add2_stage2_add_cast_1;
  assign Add2_op_stage1 = ((Add2_stage2_add_temp[64] == 1'b0) && (Add2_stage2_add_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Add2_stage2_add_temp[64] == 1'b1) && (Add2_stage2_add_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Add2_stage2_add_temp[63:0])));

  assign Add2_stage3_sub_cast = {Add2_op_stage1[63], Add2_op_stage1};
  assign Add2_stage3_sub_cast_1 = {u_q_aw[63], u_q_aw};
  assign Add2_stage3_sub_temp = Add2_stage3_sub_cast - Add2_stage3_sub_cast_1;
  assign x_q_next = ((Add2_stage3_sub_temp[64] == 1'b0) && (Add2_stage3_sub_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Add2_stage3_sub_temp[64] == 1'b1) && (Add2_stage3_sub_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Add2_stage3_sub_temp[63:0])));
  assign Reset_Integral_out1 = (PI_Reset_EN == 1'b0 ? x_q_next :
              Reset_Zero_out1);
  always_ff @(posedge clk)
    begin : x_q_z_process
      if (reset == 1'b1) begin
        x_q_z_out1 <= 64'sh0000000000000000;
      end
      else begin
        if (enb_1_5000_0) begin
          x_q_z_out1 <= Reset_Integral_out1;
        end
      end
    end
  assign Add1_add_cast = {uq_p[63], uq_p};
  assign Add1_add_cast_1 = {x_q_z_out1[63], x_q_z_out1};
  assign Add1_add_temp = Add1_add_cast + Add1_add_cast_1;
  assign Add1_out1 = ((Add1_add_temp[64] == 1'b0) && (Add1_add_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Add1_add_temp[64] == 1'b1) && (Add1_add_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Add1_add_temp[63:0])));
  assign Ld_out1 = 64'sh00000000725C3DEE;
  assign Product_mul_temp = id * Ld_out1;
  assign Product_out1 = (((Product_mul_temp[127] == 1'b0) && (Product_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Product_mul_temp[127] == 1'b0) && (Product_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Product_mul_temp[127] == 1'b1) && (Product_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Product_mul_temp[103:40]) + $signed({1'b0, Product_mul_temp[39] & (Product_mul_temp[40] | (|Product_mul_temp[38:0]))})));
  assign Constant_out1 = 64'sh00000024189374BC;
  assign Add_add_cast = {Product_out1[63], Product_out1};
  assign Add_add_cast_1 = {Constant_out1[63], Constant_out1};
  assign Add_add_temp = Add_add_cast + Add_add_cast_1;
  assign Add_out1 = ((Add_add_temp[64] == 1'b0) && (Add_add_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Add_add_temp[64] == 1'b1) && (Add_add_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Add_add_temp[63:0])));
  assign Product1_mul_temp = Add_out1 * we;
  assign Ed = (((Product1_mul_temp[103] == 1'b0) && (Product1_mul_temp[102:87] != 16'b0000000000000000)) || ((Product1_mul_temp[103] == 1'b0) && (Product1_mul_temp[87:24] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Product1_mul_temp[103] == 1'b1) && (Product1_mul_temp[102:87] != 16'b1111111111111111) ? 64'sh8000000000000000 :
              $signed(Product1_mul_temp[87:24]) + $signed({1'b0, Product1_mul_temp[23] & (Product1_mul_temp[24] | (|Product1_mul_temp[22:0]))})));
  assign Sum1_add_cast = {Add1_out1[63], Add1_out1};
  assign Sum1_add_cast_1 = {Ed[63], Ed};
  assign Sum1_add_temp = Sum1_add_cast + Sum1_add_cast_1;
  assign Sum1_out1 = ((Sum1_add_temp[64] == 1'b0) && (Sum1_add_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Sum1_add_temp[64] == 1'b1) && (Sum1_add_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Sum1_add_temp[63:0])));
  assign Reset_Output_out1 = (PI_Reset_EN == 1'b0 ? Sum1_out1 :
              Reset_Zero_out1);
  assign uq_raw = Reset_Output_out1;

endmodule   
