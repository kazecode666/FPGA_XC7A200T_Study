
`timescale 1ns/1ps

module N
          import FOC_DUT_pkg::* ;
          (  input vector_of_unsigned_logic_8 Vector[0:2],
             output logic [7:0] Value);


  logic [7:0] Vector_2;
  logic [15:0] Four_cast;
  logic [7:0] Four_out1;
  logic [7:0] Vector_1;
  logic [15:0] Two_cast;
  logic [7:0] Two_out1;
  logic [8:0] SectorNumber_stage2_add_temp;
  logic [8:0] SectorNumber_stage2_1;
  logic [8:0] SectorNumber_stage2_2;
  logic [7:0] SectorNumber_op_stage1;
  logic [7:0] Vector_0;
  logic [8:0] SectorNumber_stage3_add_temp;
  logic [8:0] SectorNumber_stage3_1;
  logic [8:0] SectorNumber_stage3_2;
  logic [7:0] SectorNumber_out1;


  assign Vector_2 = Vector[2];

  assign Four_cast = {6'b0, {Vector_2, 2'b00}};
  assign Four_out1 = (Four_cast[15:8] != 8'b00000000 ? 8'b11111111 :
              Four_cast[7:0]);
  assign Vector_1 = Vector[1];

  assign Two_cast = {7'b0, {Vector_1, 1'b0}};
  assign Two_out1 = (Two_cast[15:8] != 8'b00000000 ? 8'b11111111 :
              Two_cast[7:0]);
  assign SectorNumber_stage2_1 = {1'b0, Four_out1};
  assign SectorNumber_stage2_2 = {1'b0, Two_out1};
  assign SectorNumber_stage2_add_temp = SectorNumber_stage2_1 + SectorNumber_stage2_2;
  assign SectorNumber_op_stage1 = (SectorNumber_stage2_add_temp[8] != 1'b0 ? 8'b11111111 :
              SectorNumber_stage2_add_temp[7:0]);

  assign Vector_0 = Vector[0];
  assign SectorNumber_stage3_1 = {1'b0, SectorNumber_op_stage1};
  assign SectorNumber_stage3_2 = {1'b0, Vector_0};
  assign SectorNumber_stage3_add_temp = SectorNumber_stage3_1 + SectorNumber_stage3_2;
  assign SectorNumber_out1 = (SectorNumber_stage3_add_temp[8] != 1'b0 ? 8'b11111111 :
              SectorNumber_stage3_add_temp[7:0]);
  assign Value = SectorNumber_out1;

endmodule   
