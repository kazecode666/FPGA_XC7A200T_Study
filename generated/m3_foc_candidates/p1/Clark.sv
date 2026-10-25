
`timescale 1ns/1ps

module Clark
          (  input logic signed [31:0] ia,
             input logic signed [31:0] ib,
             input logic signed [31:0] ic,
             output logic signed [63:0] ialpha,
             output logic signed [63:0] ibeta);


  logic signed [95:0] Gain_cast;
  logic signed [63:0] Gain_out1;
  logic signed [63:0] Add_stage2_sub_cast;
  logic signed [64:0] Add_stage2_sub_cast_1;
  logic signed [64:0] Add_stage2_sub_cast_2;
  logic signed [64:0] Add_stage2_sub_temp;
  logic signed [63:0] Add_op_stage1;
  logic signed [95:0] Gain1_cast;
  logic signed [63:0] Gain1_out1;
  logic signed [64:0] Add_stage3_sub_cast;
  logic signed [64:0] Add_stage3_sub_cast_1;
  logic signed [64:0] Add_stage3_sub_temp;
  logic signed [63:0] Add_out1;
  logic signed [127:0] ialf;
  logic signed [63:0] ialf_1;
  logic signed [63:0] Add1_sub_cast;
  logic signed [63:0] Add1_sub_cast_1;
  logic signed [63:0] Add1_out1;
  logic signed [127:0] ibeta_1;

      

  assign Gain_cast = {{25{ib[31]}}, {ib, 39'b000000000000000000000000000000000000000}};
  assign Gain_out1 = (((Gain_cast[95] == 1'b0) && (Gain_cast[94:87] != 8'b00000000)) || ((Gain_cast[95] == 1'b0) && (Gain_cast[87:24] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain_cast[95] == 1'b1) && (Gain_cast[94:87] != 8'b11111111) ? 64'sh8000000000000000 :
              $signed(Gain_cast[87:24]) + $signed({1'b0, Gain_cast[23] & (Gain_cast[24] | (|Gain_cast[22:0]))})));
  assign Add_stage2_sub_cast = {{16{ia[31]}}, {ia, 16'b0000000000000000}};
  assign Add_stage2_sub_cast_1 = {Add_stage2_sub_cast[63], Add_stage2_sub_cast};
  assign Add_stage2_sub_cast_2 = {Gain_out1[63], Gain_out1};
  assign Add_stage2_sub_temp = Add_stage2_sub_cast_1 - Add_stage2_sub_cast_2;
  assign Add_op_stage1 = ((Add_stage2_sub_temp[64] == 1'b0) && (Add_stage2_sub_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Add_stage2_sub_temp[64] == 1'b1) && (Add_stage2_sub_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Add_stage2_sub_temp[63:0])));

  assign Gain1_cast = {{25{ic[31]}}, {ic, 39'b000000000000000000000000000000000000000}};
  assign Gain1_out1 = (((Gain1_cast[95] == 1'b0) && (Gain1_cast[94:87] != 8'b00000000)) || ((Gain1_cast[95] == 1'b0) && (Gain1_cast[87:24] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain1_cast[95] == 1'b1) && (Gain1_cast[94:87] != 8'b11111111) ? 64'sh8000000000000000 :
              $signed(Gain1_cast[87:24]) + $signed({1'b0, Gain1_cast[23] & (Gain1_cast[24] | (|Gain1_cast[22:0]))})));
  assign Add_stage3_sub_cast = {Add_op_stage1[63], Add_op_stage1};
  assign Add_stage3_sub_cast_1 = {Gain1_out1[63], Gain1_out1};
  assign Add_stage3_sub_temp = Add_stage3_sub_cast - Add_stage3_sub_cast_1;
  assign Add_out1 = ((Add_stage3_sub_temp[64] == 1'b0) && (Add_stage3_sub_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Add_stage3_sub_temp[64] == 1'b1) && (Add_stage3_sub_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Add_stage3_sub_temp[63:0])));
  assign ialf = 64'sh000000AAAAAAAAAB * Add_out1;
  assign ialf_1 = (((ialf[127] == 1'b0) && (ialf[126:103] != 24'b000000000000000000000000)) || ((ialf[127] == 1'b0) && (ialf[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((ialf[127] == 1'b1) && (ialf[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(ialf[103:40]) + $signed({1'b0, ialf[39] & (ialf[40] | (|ialf[38:0]))})));

  assign ialpha = ialf_1;

  assign Add1_sub_cast = {{16{ib[31]}}, {ib, 16'b0000000000000000}};
  assign Add1_sub_cast_1 = {{16{ic[31]}}, {ic, 16'b0000000000000000}};
  assign Add1_out1 = Add1_sub_cast - Add1_sub_cast_1;
  assign ibeta_1 = 64'sh00000093CD3A2C82 * Add1_out1;
  assign ibeta = (((ibeta_1[127] == 1'b0) && (ibeta_1[126:103] != 24'b000000000000000000000000)) || ((ibeta_1[127] == 1'b0) && (ibeta_1[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((ibeta_1[127] == 1'b1) && (ibeta_1[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(ibeta_1[103:40]) + $signed({1'b0, ibeta_1[39] & (ibeta_1[40] | (|ibeta_1[38:0]))})));

endmodule   
