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
    logic [31:0] time_cnt;       //当前计数状态
    logic [31:0] next_time_cnt;  //下一计数状态
    logic        pwm_out_reg;
    logic        next_pwm_out;

    /**
        @brief 组合计算下一计数状态和与其对应的下一PWM状态。
               config_en有效时使用本次输入的新配置，并从计数状态0开始。
    */
    always_comb begin
        next_time_cnt = time_cnt;
        next_pwm_out  = pwm_out_reg;

        if(config_en) begin
            next_time_cnt = 32'd0;
            if(period_set == 32'd0)
                next_pwm_out = 1'b0;
            else if(next_time_cnt >= compare_value_set)
                next_pwm_out = 1'b1;
            else
                next_pwm_out = 1'b0;
        end
        else if(period_set_reg == 32'd0) begin
            next_time_cnt = 32'd0;
            next_pwm_out  = 1'b0;
        end
        else begin
            if(time_cnt < (period_set_reg - 1'b1))
                next_time_cnt = time_cnt + 1'b1;
            else
                next_time_cnt = 32'd0;

            if(next_time_cnt >= compare_value_reg)
                next_pwm_out = 1'b1;
            else
                next_pwm_out = 1'b0;
        end
    end

    //--------------------------------
    //3.寄存下一状态
    //--------------------------------
    always_ff @(posedge clk , negedge reset_n)
        if(!reset_n) begin
            time_cnt   <= 32'd0;
            pwm_out_reg <= 1'b0;
        end
        else begin
            time_cnt   <= next_time_cnt;
            pwm_out_reg <= next_pwm_out;
        end

    assign pwm_out = pwm_out_reg;

endmodule
