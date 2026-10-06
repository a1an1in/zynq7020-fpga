`timescale 1ns / 1ps
/************************************************************
 * aurora_led_subsys.v — LED 子系统（仿 aurora_dma_subsys 收敛成一块）
 *
 * 把原散落在 aurora_top 里的：
 *     aurora_led_regs + 状态回填 + aurora_led(管脚逻辑)
 * 集中到一个外壳。顶层只需：
 *   1) 例化一个 P-BUS 从器（与 sys/adc/dma 同风格）；
 *   2) 把物理 led_o 连到本壳。
 * 之后调 LED 寄存器/管脚逻辑只改本文件，不用再动 aurora_top。
 ************************************************************/
module aurora_led_subsys (
    input  wire         aclk,
    input  wire         aresetn,

    // ---- P-BUS 从器接口（top 的 regbank 广播）----
    input  wire         p_wvalid,
    input  wire [15:0]  p_waddr,
    input  wire [31:0]  p_wdata,
    input  wire [3:0]   p_wstrb,
    input  wire         p_rvalid,
    input  wire [15:0]  p_raddr,
    output wire         o_rvalid,
    output wire [31:0]  o_rdata,

    // ---- LED 物理输出 ----
    output wire [3:0]   led_o,    // 寄存器控制灯脚 (LVCMOS33, E16/F16/H18/H17)
    output wire [2:0]   led_off   // 常亮三颗的熄灭输出 (H15/R15/C15, 固定拉 0)
);
    // led 寄存器块输出
    wire [31:0] led_o_value, led_o_ctrl, led_i_status;
    wire [3:0]  led_out, led_status_net;
    wire        led_o_rvalid;
    wire [31:0] led_o_rdata;

    // led 寄存器块（P-BUS 从器）
    aurora_led_regs u_ledregs (
        .aclk    (aclk),
        .aresetn (aresetn),
        .p_wvalid(p_wvalid), .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid(p_rvalid), .p_raddr(p_raddr),
        .o_rvalid(led_o_rvalid), .o_rdata(led_o_rdata),
        .o_value (led_o_value),
        .o_ctrl  (led_o_ctrl),
        .i_status(led_i_status)
    );

    // status 回填: [1]en 标志 + 当前灯位态
    assign led_i_status = {27'd0, led_o_ctrl[0], led_status_net[3:0]};

    // 管脚逻辑（value+en -> led_o，回填 status）
    aurora_led u_ledio (
        .led_value_i   (led_o_value[3:0]),
        .led_en_i      (led_o_ctrl[0]),
        .led_o         (led_out),
        .led_status_o  (led_status_net)
    );
    assign led_o   = led_out;
    assign led_off = 3'b000;      // 常亮三颗恒灭（固定约束输出）

    // P-BUS 从口输出（供 top N 选 1 归并）
    assign o_rvalid = led_o_rvalid;
    assign o_rdata  = led_o_rdata;
endmodule