`timescale 1ns/1ps
/************************************************************
 * tb_aurora_led_subsys.v - 集成验证 aurora_led_subsys 壳（重构后）：
 *   P-BUS 写 value/ctrl -> led_o 按 en 点亮；status 读回 en+灯位；
 *   ctrl 关闭后灯全灭。附 led_off 恒 0（常亮三颗熄灭输出）。
 * 跑法：iverilog -g2012 -I<src> -o /tmp/tb_led aurora_led_subsys.v
 *        aurora_led_regs.v aurora_led.v 本文件 && vvp /tmp/tb_led
 ************************************************************/
module tb_aurora_led_subsys;
    localparam LED_VALUE = 16'h0010;
    localparam LED_CTRL  = 16'h0014;
    localparam LED_STATUS= 16'h0018;

    reg aclk = 0, aresetn = 0;
    reg p_wvalid = 0; reg [15:0] p_waddr; reg [31:0] p_wdata; reg [3:0] p_wstrb = 0;
    reg p_rvalid = 0; reg [15:0] p_raddr;
    wire o_rvalid; wire [31:0] o_rdata;
    wire [3:0] led_o; wire [2:0] led_off;

    aurora_led_subsys u_dut (
        .aclk(aclk), .aresetn(aresetn),
        .p_wvalid(p_wvalid), .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid(p_rvalid), .p_raddr(p_raddr),
        .o_rvalid(o_rvalid), .o_rdata(o_rdata),
        .led_o(led_o), .led_off(led_off)
    );

    always #5 aclk = ~aclk;

    reg [31:0] rd;
    task pb_write(input [15:0] a, input [31:0] d);
        @(posedge aclk); p_wvalid=1; p_waddr=a; p_wdata=d; p_wstrb=4'hf;
        @(posedge aclk); p_wvalid=0; p_wstrb=0;
    endtask
    task pb_read(input [15:0] a, output [31:0] v);
        begin
            p_rvalid = 0;
            @(posedge aclk);
            p_rvalid = 1; p_raddr = a;
            @(posedge aclk);
            v = o_rdata;
            p_rvalid = 0; p_raddr = 16'h0;
            @(posedge aclk);
        end
    endtask

    integer npass = 0, nfail = 0;
    task chk(input [255:0] msg, input cond);
        begin
            if (cond) begin npass=npass+1; $display("  PASS: %0s", msg); end
            else      begin nfail=nfail+1; $display("  FAIL: %0s", msg); end
        end
    endtask

    initial begin
        $dumpfile("/tmp/tb_led.vcd");
        $dumpvars(0, tb_aurora_led_subsys);
        repeat (3) @(posedge aclk); aresetn <= 1; repeat (2) @(posedge aclk);

        $display("== T1: 复位后 ==");
        rd = 0; pb_read(LED_STATUS, rd);
        chk("status 初始=0", rd == 0);
        chk("led_off 恒 0", led_off == 0);

        $display("== T2: 写 value=0xA, ctrl=1 -> 点亮 ==");
        pb_write(LED_VALUE, 32'hA);
        pb_write(LED_CTRL,  32'd1);
        @(posedge aclk);
        chk("led_o == 0xA", led_o == 4'hA);
        pb_read(LED_STATUS, rd);
        chk("status[3:0]=0xA", rd[3:0] == 4'hA);
        chk("status[4]=1 en", rd[4] == 1);

        $display("== T3: ctrl=0 -> 全灭, en 清 ==");
        pb_write(LED_CTRL, 32'd0);
        @(posedge aclk);
        chk("led_o == 0", led_o == 4'h0);
        pb_read(LED_STATUS, rd);
        chk("status[4]=0 en", rd[4] == 0);

        $display("== T4: value 读回保留 0xA ==");
        pb_read(LED_VALUE, rd);
        chk("value 读回 0xA", rd[3:0] == 4'hA);

        $display("============================================");
        $display("TCPASS=%0d TCFAIL=%0d", npass, nfail);
        if (nfail == 0) $display("LED_SUBSYS_SIM: PASS");
        else            $display("LED_SUBSYS_SIM: FAIL");
        $finish;
    end

    initial begin
        #50000; $display("FAIL: 仿真超时"); $finish;
    end
endmodule