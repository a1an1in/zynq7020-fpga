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

    // ---------- stimulus ----------
    // assert reset for 100 time units, release it, and let the DUT run.
    // The actual run length / $finish is governed by the self check below.
    initial begin
        sysclk_p = 1'b0;
        rstn_i   = 1'b0;
        #100;
        rstn_i   = 1'b1;   // release reset
    end

    // ---------- self check: produces an explicit PASS/FAIL in the log ----------
    reg [31:0] changes      = 32'd0;   // how many times the lit LED has moved
    reg [31:0] total_cycles = 32'd0;   // active-high clock cycles since reset
    reg [3:0]  prev_led     = 4'b1000;
    reg [3:0]  seen_states  = 4'b0000; // bitmask of the 4 legal patterns observed
    reg [31:0] err_cnt      = 32'd0;
    reg        pass;
    integer    fd;                     // handle to the machine-readable verdict file

    always @(posedge sysclk_p) begin
        if (~rstn_i) begin
            changes      <= 32'd0;
            total_cycles <= 32'd0;
            prev_led     <= 4'b1000;
            seen_states  <= 4'b0000;
            err_cnt      <= 32'd0;
        end else begin
            // 1) led_o must always be a single-hot value (1000/0100/0010/0001)
            case (led_o)
                4'b1000, 4'b0100, 4'b0010, 4'b0001:
                    seen_states <= seen_states | led_o;   // record which LED is on
                default: begin
                    err_cnt <= err_cnt + 32'd1;
                    $display("[FAIL] %0t ns: led_o=%b is not a valid single-hot pattern",
                             $time, led_o);
                end
            endcase
            // 2) count how many times the lit LED rotates
            if (led_o !== prev_led)
                changes <= changes + 32'd1;
            prev_led     <= led_o;
            total_cycles <= total_cycles + 32'd1;
        end
    end

    // verdict: let it rotate many times, then print a clear PASS/FAIL
    // T_INR_CNT_SET = 1000 -> rotation every 1001 cycles (40 ns each).
    // 200_000 cycles is ~200 rotations: plenty to catch fast/broken logic.
    initial begin
        wait (rstn_i == 1'b1);                 // wait for reset release
        repeat (200_000) @(posedge sysclk_p);
        pass = (err_cnt == 32'd0 &&            // no bad LED patterns
                seen_states == 4'b1111 &&      // all 4 patterns appeared
                changes >= 100 &&              // slow-rotation sanity (expected ~200)
                changes <= 400);
        if (pass) begin
            $display("\n===============================================================");
            $display("  SIMULATION: PASS  (rotations=%0d, no errors)", changes);
            $display("===============================================================");
        end else begin
            $display("\n===============================================================");
            $display("  SIMULATION: FAIL (rotations=%0d, errors=%0d, seen=%b)",
                     changes, err_cnt, seen_states);
            $display("===============================================================");
        end
        // write a machine-readable verdict for the calling script to pick up.
        // (xsim runs with the xsim/ dir as its working directory.)
        fd = $fopen("sim_verdict.txt", "w");
        if (fd != 0) begin
            if (pass) $fdisplay(fd, "PASS");
            else      $fdisplay(fd, "FAIL");
            $fclose(fd);
        end
        $finish(pass ? 0 : 1);
    end

    // clock generator: toggle every 20 time units (40 ns period)
    always #20 sysclk_p = ~sysclk_p;

endmodule
