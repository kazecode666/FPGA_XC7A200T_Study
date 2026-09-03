module LED_flicker(
    input clk,
    input reset_n,
    output logic LED_out
    );
    //1.LED 1Hz闪烁定时计数器
    //localparam FLICKER_CNT_PAR = 32'd25_000_000; //1s周期
    localparam FLICKER_CNT_PAR = 32'd25; //1s周期仿真值
    logic [31:0]flicker_counter;
    always_ff@(posedge clk, negedge reset_n)
        if(!reset_n)
            flicker_counter <= 32'd0;
        else if(flicker_counter == (FLICKER_CNT_PAR- 1'b1))
            flicker_counter <= 32'd0;
        else
            flicker_counter <= flicker_counter + 1'b1;
    
    //2.LED输出逻辑
    always_ff@(posedge clk, negedge reset_n)
        if(!reset_n)
            LED_out <= 1'b0;
        else if(flicker_counter == (FLICKER_CNT_PAR-1'b1))
            LED_out <= ~LED_out;
        else
            LED_out <= LED_out;
endmodule
