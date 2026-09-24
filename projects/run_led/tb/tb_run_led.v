/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2021/10/15
*Module Name:tb_run_led
*File Name:tb_run_led.v
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

module tb_run_led;

    reg        sysclk_p;   // clock stimulus
    reg        rstn_i;     // reset stimulus
    wire [3:0] led_o;      // LED output to observe

    // DUT with a small T_INR_CNT_SET so the rotation is fast enough to see in sim
    run_led #(
        .T_INR_CNT_SET(1_000)
    ) u_run_led (
        .sysclk_p (sysclk_p),
        .rstn_i   (rstn_i),
        .led_o    (led_o)
    );

    // assert reset for 100 time units, release it, then let the DUT run a while
    // before finishing the simulation.
    initial begin
        sysclk_p = 1'b0;
        rstn_i   = 1'b0;
        #100;
        rstn_i   = 1'b1;
        #1_000_000;   // enough time for the LED to rotate many times
        $finish;
    end

    // clock generator: toggle every 20 time units (40 ns period)
    always #20 sysclk_p = ~sysclk_p;

endmodule
