/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2019/12/17
*Module Name:run_led
*File Name:run_led.v
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) _i input
*2) _o output
*3) _n activ low
*4) _dg debug signal 
*5) _r delay or register
*6) _s state mechine
*********************************************************************/
`timescale 1ns / 1ns

module run_led #(
    parameter T_INR_CNT_SET = 32'd999_999_999   // counter target; larger = slower rotation
)(
    input        sysclk_p,                       // system clock
    input        rstn_i,                         // global async reset, active low
    output [3:0] led_o                           // LED output
);

    // LED state register (1 = on)
    reg [3:0] led_r;

    // divider counter; [29:0] is wide enough for the 999_999_999 default
    reg [29:0] t_cnt;

    assign led_o = led_r;

    // free-running counter; clears at T_INR_CNT_SET to set the rotation period
    always @(posedge sysclk_p or negedge rstn_i) begin
        if (~rstn_i)                       // reset
            t_cnt <= 30'd0;
        else if (t_cnt == T_INR_CNT_SET)   // wrap: reached the count target
            t_cnt <= 30'd0;
        else                               // count up
            t_cnt <= t_cnt + 30'd1;
    end

    // rotate the lit LED once per counter period
    always @(posedge sysclk_p or negedge rstn_i) begin
        if (~rstn_i)
            led_r <= 4'b1000;               // initial: LED[3] on
        else if (t_cnt == 30'd0)
            // rotate right: 1000 -> 0100 -> 0010 -> 0001 -> ...
            led_r <= {led_r[0], led_r[3:1]};
    end

endmodule   

