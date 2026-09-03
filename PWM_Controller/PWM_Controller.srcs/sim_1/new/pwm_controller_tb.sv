`timescale 1ns / 1ns
`define cycle 20

module pwm_controller_tb;
    logic clk;  //时钟信号：50MHz
    logic reset_n;  // 复位，低电平有效
    logic [31:0] period_set;    //32bit配置输入
    logic [31:0] pulse_width_set;   //32bit配置输入
    logic config_en;    //配置使能，高电平有效
    wire pwm_out;   //pwm输出信号


    pwm_controller pwm_controller(
        .clk(clk),
        .reset_n(reset_n),
        .period_set(period_set),
        .pulse_width_set(pulse_width_set),
        .config_en(config_en),
        .pwm_out(pwm_out)
    );
    initial begin
        clk = 1'b1;
        forever #(`cycle/2) clk = ~clk;
    end
    initial begin
        reset_n = 1'b0;
        period_set = 32'd0;
        pulse_width_set = 32'd0;
        config_en = 1'b0;
        #(`cycle*2);
        reset_n = 1'b1;
        #(`cycle*2);

        //case1:设置周期为10个clk，比较值为4
        period_set = 32'd10;
        pulse_width_set = 32'd4;
        config_en = 1'b1;
        #(`cycle*1);
        config_en = 1'b0;
        #(`cycle*25);

        //case2:设置周期为15个clk，比较值为10
        period_set = 32'd15;
        pulse_width_set = 32'd10;
        config_en = 1'b1;
        #(`cycle*1);
        config_en = 1'b0;
        #(`cycle*35);
        $stop;
    end
endmodule
