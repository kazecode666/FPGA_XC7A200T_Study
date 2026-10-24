
`timescale 1ns/1ps

module XYZ_Calculate
          import FOC_DUT_pkg::* ;
          (  input logic clk,
             input logic reset,
             input logic enb,
             input logic signed [63:0] Ualpha,
             input logic signed [63:0] Ubeta,
             input logic [31:0] Udc,
             output logic signed [63:0] X,
             output logic signed [63:0] Y,
             output logic signed [63:0] Z);


  logic signed [127:0] Gain1_mul_temp;
  logic signed [63:0] Gain1_out1;
  logic signed [63:0] Constant1_out1;
  logic signed [63:0] Math_Function_out1;
  logic signed [127:0] Product_mul_temp;
  logic signed [63:0] Product_out1;
  vector_of_signed_logic_64 reduced_reg [0:93];
  logic signed [63:0] Product_out1_1;
  logic signed [127:0] Product1_mul_temp;
  logic signed [127:0] Gain2_mul_temp;
  logic signed [63:0] Gain2_out1;
  logic signed [127:0] Gain_mul_temp;
  logic signed [63:0] Gain_out1;
  logic signed [64:0] Add_add_cast;
  logic signed [64:0] Add_add_cast_1;
  logic signed [64:0] Add_add_temp;
  logic signed [63:0] Add_out1;
  logic signed [127:0] Product3_mul_temp;
  logic signed [64:0] Add1_sub_cast;
  logic signed [64:0] Add1_sub_cast_1;
  logic signed [64:0] Add1_sub_temp;
  logic signed [63:0] Add1_out1;
  logic signed [127:0] Product2_mul_temp;


  assign Gain1_mul_temp = 64'sh000001BB6AE7D567 * Ubeta;
  assign Gain1_out1 = (((Gain1_mul_temp[127] == 1'b0) && (Gain1_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Gain1_mul_temp[127] == 1'b0) && (Gain1_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain1_mul_temp[127] == 1'b1) && (Gain1_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Gain1_mul_temp[103:40]) + $signed({1'b0, Gain1_mul_temp[39] & (Gain1_mul_temp[40] | (|Gain1_mul_temp[38:0]))})));
  assign Constant1_out1 = 64'sh00000000068DB8BB;
  reciprocal u_reciprocal (.clk(clk),
                           .reset(reset),
                           .enb(enb),
                           .recip_in(Udc),
                           .recip_out(Math_Function_out1)
                           );
  assign Product_mul_temp = Constant1_out1 * Math_Function_out1;
  assign Product_out1 = (((Product_mul_temp[127] == 1'b0) && (Product_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Product_mul_temp[127] == 1'b0) && (Product_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Product_mul_temp[127] == 1'b1) && (Product_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Product_mul_temp[103:40]) + $signed({1'b0, Product_mul_temp[39] & (Product_mul_temp[40] | (|Product_mul_temp[38:0]))})));
  always_ff @(posedge clk)
    begin : reduced_process
      if (reset == 1'b1) begin
        reduced_reg <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          reduced_reg[0] <= Product_out1;
          reduced_reg[32'sd1:32'sd93] <= reduced_reg[32'sd0:32'sd92];
        end
      end
    end

  assign Product_out1_1 = reduced_reg[93];

  assign Product1_mul_temp = Gain1_out1 * Product_out1_1;
  assign X = (((Product1_mul_temp[127] == 1'b0) && (Product1_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Product1_mul_temp[127] == 1'b0) && (Product1_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Product1_mul_temp[127] == 1'b1) && (Product1_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Product1_mul_temp[103:40]) + $signed({1'b0, Product1_mul_temp[39] & (Product1_mul_temp[40] | (|Product1_mul_temp[38:0]))})));
  assign Gain2_mul_temp = 64'sh000000DDB22D0E56 * Ubeta;
  assign Gain2_out1 = (((Gain2_mul_temp[127] == 1'b0) && (Gain2_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Gain2_mul_temp[127] == 1'b0) && (Gain2_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain2_mul_temp[127] == 1'b1) && (Gain2_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Gain2_mul_temp[103:40]) + $signed({1'b0, Gain2_mul_temp[39] & (Gain2_mul_temp[40] | (|Gain2_mul_temp[38:0]))})));
  assign Gain_mul_temp = 64'sh0000018000000000 * Ualpha;
  assign Gain_out1 = (((Gain_mul_temp[127] == 1'b0) && (Gain_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Gain_mul_temp[127] == 1'b0) && (Gain_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain_mul_temp[127] == 1'b1) && (Gain_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Gain_mul_temp[103:40]) + $signed({1'b0, Gain_mul_temp[39] & (Gain_mul_temp[40] | (|Gain_mul_temp[38:0]))})));
  assign Add_add_cast = {Gain2_out1[63], Gain2_out1};
  assign Add_add_cast_1 = {Gain_out1[63], Gain_out1};
  assign Add_add_temp = Add_add_cast + Add_add_cast_1;
  assign Add_out1 = ((Add_add_temp[64] == 1'b0) && (Add_add_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Add_add_temp[64] == 1'b1) && (Add_add_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Add_add_temp[63:0])));
  assign Product3_mul_temp = Add_out1 * Product_out1_1;
  assign Y = (((Product3_mul_temp[127] == 1'b0) && (Product3_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Product3_mul_temp[127] == 1'b0) && (Product3_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Product3_mul_temp[127] == 1'b1) && (Product3_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Product3_mul_temp[103:40]) + $signed({1'b0, Product3_mul_temp[39] & (Product3_mul_temp[40] | (|Product3_mul_temp[38:0]))})));
  assign Add1_sub_cast = {Gain2_out1[63], Gain2_out1};
  assign Add1_sub_cast_1 = {Gain_out1[63], Gain_out1};
  assign Add1_sub_temp = Add1_sub_cast - Add1_sub_cast_1;
  assign Add1_out1 = ((Add1_sub_temp[64] == 1'b0) && (Add1_sub_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Add1_sub_temp[64] == 1'b1) && (Add1_sub_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Add1_sub_temp[63:0])));
  assign Product2_mul_temp = Add1_out1 * Product_out1_1;
  assign Z = (((Product2_mul_temp[127] == 1'b0) && (Product2_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Product2_mul_temp[127] == 1'b0) && (Product2_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Product2_mul_temp[127] == 1'b1) && (Product2_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Product2_mul_temp[103:40]) + $signed({1'b0, Product2_mul_temp[39] & (Product2_mul_temp[40] | (|Product2_mul_temp[38:0]))})));
endmodule   
