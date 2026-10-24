
`timescale 1ns/1ps

module T1T2_Calculate
          import FOC_DUT_pkg::* ;
          (  input logic clk,
             input logic reset,
             input logic enb,
             input logic [7:0] N,
             input logic signed [63:0] X,
             input logic signed [63:0] Y,
             input logic signed [63:0] Z,
             output logic signed [63:0] T1,
             output logic signed [63:0] T2);


  logic signed [64:0] Gain2_cast;
  logic signed [64:0] Gain2_cast_1;
  logic signed [127:0] Gain2_cast_2;
  logic signed [63:0] Gain2_out1;
  logic signed [64:0] Gain_cast;
  logic signed [64:0] Gain_cast_1;
  logic signed [127:0] Gain_cast_2;
  logic signed [63:0] Gain_out1;
  logic signed [64:0] Gain1_cast;
  logic signed [64:0] Gain1_cast_1;
  logic signed [127:0] Gain1_cast_2;
  logic signed [63:0] Gain1_out1;
  logic signed [63:0] Multiport_Switch_out1;
  logic signed [63:0] Multiport_Switch1_out1;
  logic signed [63:0] Constant_out1;
  vector_of_signed_logic_64 Mux_out1 [0:2];
  logic signed [63:0] Fcn_Value;
  vector_of_signed_logic_64 reduced_reg [0:108];
  logic signed [63:0] Fcn_Value_1;
  logic switch_compare_1;
  logic signed [63:0] Fcn1_Value;
  vector_of_signed_logic_64 delayMatch_reg [0:108];
  logic signed [63:0] Multiport_Switch_out1_1;
  logic switch_compare_1_1;
  logic signed [63:0] Fcn2_Value;
  vector_of_signed_logic_64 delayMatch2_reg [0:108];
  logic signed [63:0] Multiport_Switch1_out1_1;


  assign Gain2_cast = {Z[63], Z};
  assign Gain2_cast_1 =  - (Gain2_cast);
  assign Gain2_cast_2 = {{23{Gain2_cast_1[64]}}, {Gain2_cast_1, 40'b0000000000000000000000000000000000000000}};
  assign Gain2_out1 = (((Gain2_cast_2[127] == 1'b0) && (Gain2_cast_2[126:103] != 24'b000000000000000000000000)) || ((Gain2_cast_2[127] == 1'b0) && (Gain2_cast_2[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain2_cast_2[127] == 1'b1) && (Gain2_cast_2[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Gain2_cast_2[103:40]) + $signed({1'b0, Gain2_cast_2[39] & (Gain2_cast_2[40] | (|Gain2_cast_2[38:0]))})));
  assign Gain_cast = {X[63], X};
  assign Gain_cast_1 =  - (Gain_cast);
  assign Gain_cast_2 = {{23{Gain_cast_1[64]}}, {Gain_cast_1, 40'b0000000000000000000000000000000000000000}};
  assign Gain_out1 = (((Gain_cast_2[127] == 1'b0) && (Gain_cast_2[126:103] != 24'b000000000000000000000000)) || ((Gain_cast_2[127] == 1'b0) && (Gain_cast_2[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain_cast_2[127] == 1'b1) && (Gain_cast_2[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Gain_cast_2[103:40]) + $signed({1'b0, Gain_cast_2[39] & (Gain_cast_2[40] | (|Gain_cast_2[38:0]))})));
  assign Gain1_cast = {Y[63], Y};
  assign Gain1_cast_1 =  - (Gain1_cast);
  assign Gain1_cast_2 = {{23{Gain1_cast_1[64]}}, {Gain1_cast_1, 40'b0000000000000000000000000000000000000000}};
  assign Gain1_out1 = (((Gain1_cast_2[127] == 1'b0) && (Gain1_cast_2[126:103] != 24'b000000000000000000000000)) || ((Gain1_cast_2[127] == 1'b0) && (Gain1_cast_2[103:40] == 64'sh7FFFFFFFFFFFFFFF)) ? 64'sh7FFFFFFFFFFFFFFF :
              ((Gain1_cast_2[127] == 1'b1) && (Gain1_cast_2[126:103] != 24'b111111111111111111111111) ? 64'sh8000000000000000 :
              $signed(Gain1_cast_2[103:40]) + $signed({1'b0, Gain1_cast_2[39] & (Gain1_cast_2[40] | (|Gain1_cast_2[38:0]))})));
  assign Multiport_Switch_out1 = (N == 8'b00000001 ? Z :
              (N == 8'b00000010 ? Y :
              (N == 8'b00000011 ? Gain2_out1 :
              (N == 8'b00000100 ? Gain_out1 :
              (N == 8'b00000101 ? X :
              Gain1_out1)))));
  assign Multiport_Switch1_out1 = (N == 8'b00000001 ? Y :
              (N == 8'b00000010 ? Gain_out1 :
              (N == 8'b00000011 ? X :
              (N == 8'b00000100 ? Z :
              (N == 8'b00000101 ? Gain1_out1 :
              Gain2_out1)))));
  assign Constant_out1 = 64'sh00000000068DB8BB;
  assign Mux_out1[0] = Multiport_Switch_out1;
  assign Mux_out1[1] = Multiport_Switch1_out1;
  assign Mux_out1[2] = Constant_out1;
  Fcn_block u_Fcn (.Vector(Mux_out1),
                   .Value(Fcn_Value)
                   );
  always_ff @(posedge clk)
    begin : reduced_process
      if (reset == 1'b1) begin
        reduced_reg <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          reduced_reg[0] <= Fcn_Value;
          reduced_reg[32'sd1:32'sd108] <= reduced_reg[32'sd0:32'sd107];
        end
      end
    end

  assign Fcn_Value_1 = reduced_reg[108];

  assign switch_compare_1 = Fcn_Value_1 >= 64'sh0000000000000000;

  Fcn1_block u_Fcn1 (.clk(clk),
                     .reset(reset),
                     .enb(enb),
                     .Vector(Mux_out1),
                     .Value(Fcn1_Value)
                     );
  always_ff @(posedge clk)
    begin : delayMatch_process
      if (reset == 1'b1) begin
        delayMatch_reg <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          delayMatch_reg[0] <= Multiport_Switch_out1;
          delayMatch_reg[32'sd1:32'sd108] <= delayMatch_reg[32'sd0:32'sd107];
        end
      end
    end

  assign Multiport_Switch_out1_1 = delayMatch_reg[108];

  assign T1 = (switch_compare_1 == 1'b0 ? Fcn1_Value :
              Multiport_Switch_out1_1);
  assign switch_compare_1_1 = Fcn_Value_1 > 64'sh0000000000000000;

  Fcn2_block u_Fcn2 (.clk(clk),
                     .reset(reset),
                     .enb(enb),
                     .Vector(Mux_out1),
                     .Value(Fcn2_Value)
                     );
  always_ff @(posedge clk)
    begin : delayMatch2_process
      if (reset == 1'b1) begin
        delayMatch2_reg <= '{default :64'sh0000000000000000};
      end
      else begin
        if (enb) begin
          delayMatch2_reg[0] <= Multiport_Switch1_out1;
          delayMatch2_reg[32'sd1:32'sd108] <= delayMatch2_reg[32'sd0:32'sd107];
        end
      end
    end

  assign Multiport_Switch1_out1_1 = delayMatch2_reg[108];

  assign T2 = (switch_compare_1_1 == 1'b0 ? Fcn2_Value :
              Multiport_Switch1_out1_1);
endmodule   
