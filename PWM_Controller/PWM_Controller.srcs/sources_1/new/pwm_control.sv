module pwm_controller(
    input clk,  //时钟：50MHz
    input reset_n,  //复位信号，低电平有效
    input [31:0] period_set,    //32bit配置输入
    input [31:0] compare_value_set, //32bit比较值配置输入
    input config_en,  //配置使能信号，高电平有效
    output pwm_out  //PWM输出
    );
    //--------------------------------
    //1.锁存配置参数
    //--------------------------------
    logic [31:0] period_set_reg;
    logic [31:0] compare_value_reg;
    
    /**
        @brief 利用使能信号锁存配置参数
    */
    always_ff @(posedge clk , negedge reset_n) 
        if(!reset_n) 
            begin
                period_set_reg <= 32'd0;
                compare_value_reg <= 32'd0;
            end
        else if(config_en)
            begin
                period_set_reg <= period_set;
                compare_value_reg <= compare_value_set;
            end
        else
            begin
                period_set_reg <= period_set_reg;
                compare_value_reg <= compare_value_reg;
            end
    //--------------------------------
    //2.定时计数器自动计数
    //--------------------------------
    logic [31:0] time_cnt;  //定时器
    /**
        @brief （1）定时自动递增计数，配置数据使能到来时计数器清零，消除脉冲的顿挫；
               （2）计数器达到配置周期值时清零，重新计数；
    */
    always_ff @(posedge clk , negedge reset_n) 
        if(!reset_n) 
            time_cnt <= 32'd0;
        else if(config_en)
            time_cnt <= 32'd0;
        else if(period_set_reg == 32'd0)
            time_cnt <= 32'd0;
        else if(time_cnt < (period_set_reg - 1'b1))
            time_cnt <= time_cnt + 1'b1;
        else
            time_cnt <= 32'd0;

    //--------------------------------
    //3.比较器
    //--------------------------------
    logic pwm_out_reg;
    /**
        @brief period非零且定时值大于等于比较值时，pwm_out输出1，否则输出0
    */
    always_ff @(posedge clk , negedge reset_n)
        if(!reset_n)
            pwm_out_reg <= 1'b0;
        else if(period_set_reg == 32'd0)
            pwm_out_reg <= 1'b0;
        else if(time_cnt >= compare_value_reg)
            pwm_out_reg <= 1'b1;
        else
            pwm_out_reg <= 1'b0;
        assign pwm_out = pwm_out_reg;

endmodule
