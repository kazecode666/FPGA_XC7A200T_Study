`timescale 1ns / 1ns
`define    cycle 20

module LED_flicker_tb;
    logic clk;
    logic reset_n;
    logic LED_out;

    //1.实例化被测模块
    LED_flicker LED_flicker(
        .clk(clk),
        .reset_n(reset_n),
        .LED_out(LED_out)
    );

    //2.时钟信号产生
    initial begin
        clk = 1'b1;
        forever #(`cycle/2) clk = ~clk;
    end

    //3.生成激励
    initial begin
        reset_n = 1'b0;
        repeat (5) @(negedge clk);
        reset_n = 1'b1;
        $stop;
    end
endmodule
