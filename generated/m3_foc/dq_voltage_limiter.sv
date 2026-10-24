
`timescale 1ns/1ps

module dq_voltage_limiter
          import FOC_DUT_pkg::* ;
          (  input logic clk,
             input logic reset,
             input logic enb,
             input logic enb_1_5000_1,
             input logic signed [63:0] ud_raw,
             input logic signed [63:0] uq_raw,
             input logic [31:0] Vdc_V,
             output logic signed [63:0] ud_lim,
             output logic signed [63:0] uq_lim,
             output logic signed [63:0] du_d_z,
             output logic signed [63:0] du_q_z);


  logic signed [63:0] ud_raw_1;
  logic signed [63:0] From10_out1;
  vector_of_signed_logic_64 reduced_reg [0:163];
  logic signed [63:0] From10_out1_1;
  logic [31:0] Vdc_V_1;
  logic signed [32:0] Bus_over_sqrt3_cast;
  logic signed [96:0] Bus_over_sqrt3_mul_temp;
  logic signed [95:0] Bus_over_sqrt3_cast_1;
  logic signed [63:0] Bus_over_sqrt3_out1;
  logic signed [127:0] Gain_mul_temp;
  logic signed [63:0] U_max;
  logic Sum_out1_timer;
  logic [55:0] delayMatch1_reg;
  logic Sum_out1_timer_1;
  logic signed [127:0] multiplier1_mul_temp;
  logic [63:0] Math_Function_out1;
  logic signed [63:0] uq_raw_1;
  logic signed [127:0] multiplier_mul_temp;
  logic [63:0] Math_Function1_out1;
  logic [64:0] Add_add_cast;
  logic [64:0] Add_add_cast_1;
  logic [64:0] Add_add_temp;
  logic [63:0] Add_out1;
  logic signed [63:0] U_raw;
  vector_of_signed_logic_64 delayMatch_reg [0:55];
  logic signed [63:0] U_max_1;
  logic signed [63:0] Sum_out1_default;
  logic signed [63:0] Constant2_out1;
  logic signed [64:0] Sum_add_cast;
  logic signed [64:0] Sum_add_cast_1;
  logic signed [64:0] Sum_add_temp;
  logic signed [63:0] Sum_out1;
  logic signed [63:0] Sum_out1_zp;
  logic [71:0] Divide_out1;
  logic signed [72:0] MinMax_op_stage1;
  logic signed [63:0] Constant3_out1;
  logic signed [72:0] MinMax_op_stage2;
  logic signed [72:0] MinMax_stage1_val;
  logic signed [63:0] obs_s;
  logic signed [63:0] obs_s_1;
  logic signed [127:0] Product_mul_temp;
  logic signed [63:0] obs_ud_lim;
  logic signed [63:0] From12_out1;
  vector_of_signed_logic_64 reduced_reg_1 [0:163];
  logic signed [63:0] From12_out1_1;
  logic signed [127:0] Product1_mul_temp;
  logic signed [63:0] obs_uq_lim;
  logic signed [64:0] Subtract_sub_cast;
  logic signed [64:0] Subtract_sub_cast_1;
  logic signed [64:0] Subtract_sub_temp;
  logic signed [63:0] Subtract_out1;
  logic signed [63:0] Subtract_out1_1;
  logic signed [63:0] Unit_Delay_bypass_reg;
  logic signed [63:0] Subtract_out1_2;
  logic signed [64:0] Subtract1_sub_cast;
  logic signed [64:0] Subtract1_sub_cast_1;
  logic signed [64:0] Subtract1_sub_temp;
  logic signed [63:0] Subtract1_out1;
  logic signed [63:0] Subtract1_out1_1;
  logic signed [63:0] Unit_Delay1_bypass_reg;
  logic signed [63:0] Subtract1_out1_2;


  assign ud_raw_1 = ud_raw;
  always_ff @(posedge clk)
    begin : reduced_process
      if (reset == 1'b1) begin
        From10_out1 <= 64'sh0000000000000000;
      end
      else begin
        if (enb) begin
          From10_out1 <= ud_raw_1;
        end
      end
    end

  always_ff @(posedge clk)
    begin : reduced_1_process
      if (reset == 1'b1) begin
        reduced_reg <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          reduced_reg[0] <= From10_out1;
          reduced_reg[32'sd1:32'sd163] <= reduced_reg[32'sd0:32'sd162];
        end
      end
    end

  assign From10_out1_1 = reduced_reg[163];

  assign Vdc_V_1 = Vdc_V;

  assign Bus_over_sqrt3_cast = {1'b0, Vdc_V_1};
  assign Bus_over_sqrt3_mul_temp = 64'sh00000093CD3A2C82 * Bus_over_sqrt3_cast;
  assign Bus_over_sqrt3_cast_1 = Bus_over_sqrt3_mul_temp[95:0];
  assign Bus_over_sqrt3_out1 = (((Bus_over_sqrt3_cast_1[95] == 1'b0) && (Bus_over_sqrt3_cast_1[94:87] != 8'b00000000)) || ((Bus_over_sqrt3_cast_1[95] == 1'b0) && (Bus_over_sqrt3_cast_1[87:24] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Bus_over_sqrt3_cast_1[95] == 1'b1) && (Bus_over_sqrt3_cast_1[94:87] != 8'b11111111) ? 64'sh8000000000000000 :
              $signed(Bus_over_sqrt3_cast_1[87:24]) + $signed({1'b0, Bus_over_sqrt3_cast_1[23] & (Bus_over_sqrt3_cast_1[24] | (|Bus_over_sqrt3_cast_1[22:0]))})));
  assign Gain_mul_temp = 64'sh000000E666666666 * Bus_over_sqrt3_out1;
  assign U_max = (((Gain_mul_temp[127] == 1'b0) && (Gain_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Gain_mul_temp[127] == 1'b0) && (Gain_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain_mul_temp[127] == 1'b1) && (Gain_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Gain_mul_temp[103:40]) + $signed({1'b0, Gain_mul_temp[39] & (Gain_mul_temp[40] | (|Gain_mul_temp[38:0]))})));
  assign Sum_out1_timer = 1'b1;

  always_ff @(posedge clk)
    begin : delayMatch1_process
      if (reset == 1'b1) begin
        delayMatch1_reg <= '{default :1'b0};
      end
      else begin
        if (enb) begin
          delayMatch1_reg[0] <= Sum_out1_timer;
          delayMatch1_reg[32'sd55:32'sd1] <= delayMatch1_reg[32'sd54:32'sd0];
        end
      end
    end

  assign Sum_out1_timer_1 = delayMatch1_reg[55];

  assign multiplier1_mul_temp = ud_raw_1 * ud_raw_1;
  assign Math_Function_out1 = (((multiplier1_mul_temp[127] == 1'b0) && (multiplier1_mul_temp[126:108] != 19'b0000000000000000000)) || ((multiplier1_mul_temp[127] == 1'b0) && (multiplier1_mul_temp[107:44] == 64'hFFFFFFFFFFFFFFFF)) ? 64'hFFFFFFFFFFFFFFFF :
              (multiplier1_mul_temp[127] == 1'b1 ? 64'h0000000000000000 :
              multiplier1_mul_temp[107:44] + (multiplier1_mul_temp[43] & (multiplier1_mul_temp[44] | (|multiplier1_mul_temp[42:0])))));
  assign uq_raw_1 = uq_raw;
  assign multiplier_mul_temp = uq_raw_1 * uq_raw_1;
  assign Math_Function1_out1 = (((multiplier_mul_temp[127] == 1'b0) && (multiplier_mul_temp[126:108] != 19'b0000000000000000000)) || ((multiplier_mul_temp[127] == 1'b0) && (multiplier_mul_temp[107:44] == 64'hFFFFFFFFFFFFFFFF)) ? 64'hFFFFFFFFFFFFFFFF :
              (multiplier_mul_temp[127] == 1'b1 ? 64'h0000000000000000 :
              multiplier_mul_temp[107:44] + (multiplier_mul_temp[43] & (multiplier_mul_temp[44] | (|multiplier_mul_temp[42:0])))));
  assign Add_add_cast = {1'b0, Math_Function_out1};
  assign Add_add_cast_1 = {1'b0, Math_Function1_out1};
  assign Add_add_temp = Add_add_cast + Add_add_cast_1;
  assign Add_out1 = (Add_add_temp[64] != 1'b0 ? 64'hFFFFFFFFFFFFFFFF :
              Add_add_temp[63:0]);
  Sqrt u_Sqrt (.clk(clk),
               .reset(reset),
               .enb(enb),
               .din(Add_out1),
               .dout(U_raw)
               );
  always_ff @(posedge clk)
    begin : delayMatch_process
      if (reset == 1'b1) begin
        delayMatch_reg <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          delayMatch_reg[0] <= U_max;
          delayMatch_reg[32'sd1:32'sd55] <= delayMatch_reg[32'sd0:32'sd54];
        end
      end
    end

  assign U_max_1 = delayMatch_reg[55];

  assign Sum_out1_default = 64'sh0000010000000000;

  assign Constant2_out1 = 64'sh000000000010C6F8;
  assign Sum_add_cast = {U_raw[63], U_raw};
  assign Sum_add_cast_1 = {Constant2_out1[63], Constant2_out1};
  assign Sum_add_temp = Sum_add_cast + Sum_add_cast_1;
  assign Sum_out1 = ((Sum_add_temp[64] == 1'b0) && (Sum_add_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Sum_add_temp[64] == 1'b1) && (Sum_add_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Sum_add_temp[63:0])));
  assign Sum_out1_zp = (Sum_out1_timer_1 == 1'b0 ? Sum_out1_default :
              Sum_out1);

  Divide u_Divide (.clk(clk),
                   .reset(reset),
                   .enb(enb),
                   .dividend_in(U_max_1),
                   .divisor_in(Sum_out1_zp),
                   .quotient(Divide_out1)
                   );
  assign MinMax_op_stage1 = {1'b0, Divide_out1};
  assign Constant3_out1 = 64'sh0000010000000000;
  assign MinMax_op_stage2 = {{9{Constant3_out1[63]}}, Constant3_out1};
  assign MinMax_stage1_val = (MinMax_op_stage1 <= MinMax_op_stage2 ? MinMax_op_stage1 :
              MinMax_op_stage2);
  assign obs_s = ((MinMax_stage1_val[72] == 1'b0) && (MinMax_stage1_val[71:63] != 9'b000000000) ? 64'sh7FFFFFFFFFFFFFFF :
              ((MinMax_stage1_val[72] == 1'b1) && (MinMax_stage1_val[71:63] != 9'b111111111) ? 64'sh8000000000000000 :
              $signed(MinMax_stage1_val[63:0])));
  assign obs_s_1 = obs_s;
  assign Product_mul_temp = From10_out1_1 * obs_s_1;
  assign obs_ud_lim = (((Product_mul_temp[127] == 1'b0) && (Product_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Product_mul_temp[127] == 1'b0) && (Product_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Product_mul_temp[127] == 1'b1) && (Product_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Product_mul_temp[103:40]) + $signed({1'b0, Product_mul_temp[39] & (Product_mul_temp[40] | (|Product_mul_temp[38:0]))})));
  assign ud_lim = obs_ud_lim;

  always_ff @(posedge clk)
    begin : reduced_2_process
      if (reset == 1'b1) begin
        From12_out1 <= 64'sh0000000000000000;
      end
      else begin
        if (enb) begin
          From12_out1 <= uq_raw_1;
        end
      end
    end

  always_ff @(posedge clk)
    begin : reduced_3_process
      if (reset == 1'b1) begin
        reduced_reg_1 <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          reduced_reg_1[0] <= From12_out1;
          reduced_reg_1[32'sd1:32'sd163] <= reduced_reg_1[32'sd0:32'sd162];
        end
      end
    end

  assign From12_out1_1 = reduced_reg_1[163];

  assign Product1_mul_temp = obs_s_1 * From12_out1_1;
  assign obs_uq_lim = (((Product1_mul_temp[127] == 1'b0) && (Product1_mul_temp[126:103] != 24'b000000000000000000000000)) || ((Product1_mul_temp[127] == 1'b0) && (Product1_mul_temp[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Product1_mul_temp[127] == 1'b1) && (Product1_mul_temp[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Product1_mul_temp[103:40]) + $signed({1'b0, Product1_mul_temp[39] & (Product1_mul_temp[40] | (|Product1_mul_temp[38:0]))})));
  assign uq_lim = obs_uq_lim;

  assign Subtract_sub_cast = {From10_out1[63], From10_out1};
  assign Subtract_sub_cast_1 = {obs_ud_lim[63], obs_ud_lim};
  assign Subtract_sub_temp = Subtract_sub_cast - Subtract_sub_cast_1;
  assign Subtract_out1 = ((Subtract_sub_temp[64] == 1'b0) && (Subtract_sub_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Subtract_sub_temp[64] == 1'b1) && (Subtract_sub_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Subtract_sub_temp[63:0])));
  always_ff @(posedge clk)
    begin : crp_out_delay1_process
      if (reset == 1'b1) begin
        Subtract_out1_1 <= 64'sh0000000000000000;
      end
      else begin
        if (enb) begin
          Subtract_out1_1 <= Subtract_out1;
        end
      end
    end

  always_ff @(posedge clk)
    begin : Unit_Delay_bypass_process
      if (reset == 1'b1) begin
        Unit_Delay_bypass_reg <= 64'sh0000000000000000;
      end
      else begin
        if (enb_1_5000_1) begin
          Unit_Delay_bypass_reg <= Subtract_out1_1;
        end
      end
    end

  assign Subtract_out1_2 = (enb_1_5000_1 == 1'b1 ? Subtract_out1_1 :
              Unit_Delay_bypass_reg);

  assign du_d_z = Subtract_out1_2;

  assign Subtract1_sub_cast = {From12_out1[63], From12_out1};
  assign Subtract1_sub_cast_1 = {obs_uq_lim[63], obs_uq_lim};
  assign Subtract1_sub_temp = Subtract1_sub_cast - Subtract1_sub_cast_1;
  assign Subtract1_out1 = ((Subtract1_sub_temp[64] == 1'b0) && (Subtract1_sub_temp[63] != 1'b0) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Subtract1_sub_temp[64] == 1'b1) && (Subtract1_sub_temp[63] != 1'b1) ? 64'sh8000000000000000 :
              $signed(Subtract1_sub_temp[63:0])));
  always_ff @(posedge clk)
    begin : crp_out_delay_process
      if (reset == 1'b1) begin
        Subtract1_out1_1 <= 64'sh0000000000000000;
      end
      else begin
        if (enb) begin
          Subtract1_out1_1 <= Subtract1_out1;
        end
      end
    end

  always_ff @(posedge clk)
    begin : Unit_Delay1_bypass_process
      if (reset == 1'b1) begin
        Unit_Delay1_bypass_reg <= 64'sh0000000000000000;
      end
      else begin
        if (enb_1_5000_1) begin
          Unit_Delay1_bypass_reg <= Subtract1_out1_1;
        end
      end
    end

  assign Subtract1_out1_2 = (enb_1_5000_1 == 1'b1 ? Subtract1_out1_1 :
              Unit_Delay1_bypass_reg);

  assign du_q_z = Subtract1_out1_2;

endmodule   
