`timescale 1ns/1ps
module step7b_counter(input logic clk, reset_n,
    input logic [7:0] in_data, output logic [7:0] out_data);
  always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) out_data <= 8'd0;
    else out_data <= in_data + 8'd1;
endmodule
