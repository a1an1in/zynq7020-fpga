/************************************************************
 * run_led_top.v
 * 整系统顶层：例化 PS 系统（system_wrapper，含 DDR/FIXED_IO/以太）
 *            + 流水灯（run_led，PL 侧独立管脚）。
 *
 * 目的：让“PL 重配后 PS 网络不掉” —— 被加载的 bit 本身含 PS 系统，
 * 不再是一份纯 PL 位流。
 *
 * 端口与 build 生成的 system_wrapper.v 严格一致（DDR_dqs_p、
 * FIXED_IO_ddr_vrn/vrp、FIXED_IO_ps_porb/ps_srstb 等）。
 *
 * 另：板上 LED1/2/3（PL 脚 H15/R15/C15）此前无任何位流驱动（Hi-Z），
 * 被板上拉拉成常亮。这里新增 led_off[2:0] 恒 0，显式拉低这三脚，
 * 使 run_led bit 加载后流水灯照常跑、同时三颗常亮灯熄灭。
 ************************************************************/
module run_led_top (
    // ---- PS 内存接口（DDR + 固定IO，透传保证 DDR 工作）----
    inout  [14:0] DDR_addr,
    inout  [2:0]  DDR_ba,
    inout         DDR_cas_n,
    inout         DDR_ck_n,
    inout         DDR_ck_p,
    inout         DDR_cke,
    inout         DDR_cs_n,
    inout  [3:0]  DDR_dm,
    inout  [31:0] DDR_dq,
    inout  [3:0]  DDR_dqs_n,
    inout  [3:0]  DDR_dqs_p,
    inout         DDR_odt,
    inout         DDR_ras_n,
    inout         DDR_reset_n,
    inout         DDR_we_n,
    inout         FIXED_IO_ddr_vrn,
    inout         FIXED_IO_ddr_vrp,
    inout  [53:0] FIXED_IO_mio,
    inout         FIXED_IO_ps_clk,
    inout         FIXED_IO_ps_porb,
    inout         FIXED_IO_ps_srstb,

    // ---- PL 侧独立 IO：流水灯 ----
    input         sysclk_p,      // 板载 100MHz（管脚约束在 run_led_pin.xdc）
    input         rstn_i,        // 复位按键，低有效
    output [3:0]  led_o,

    // ---- 常亮三颗 LED（H15/R15/C15），显式拉 0 熄灭 ----
    output [2:0]  led_off
);

    // 例化 PS 系统（Block Design "system" 的 wrapper）
    system_wrapper ps_system (
        .DDR_addr        (DDR_addr),
        .DDR_ba          (DDR_ba),
        .DDR_cas_n       (DDR_cas_n),
        .DDR_ck_n        (DDR_ck_n),
        .DDR_ck_p        (DDR_ck_p),
        .DDR_cke         (DDR_cke),
        .DDR_cs_n        (DDR_cs_n),
        .DDR_dm          (DDR_dm),
        .DDR_dq          (DDR_dq),
        .DDR_dqs_n       (DDR_dqs_n),
        .DDR_dqs_p       (DDR_dqs_p),
        .DDR_odt         (DDR_odt),
        .DDR_ras_n       (DDR_ras_n),
        .DDR_reset_n     (DDR_reset_n),
        .DDR_we_n        (DDR_we_n),
        .FIXED_IO_ddr_vrn (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio    (FIXED_IO_mio),
        .FIXED_IO_ps_clk (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb)
    );

    // 例化流水灯（PL 侧独立管脚）
    run_led led_demo (
        .sysclk_p (sysclk_p),
        .rstn_i   (rstn_i),
        .led_o    (led_o)
    );

    // H15 / R15 / C15 三脚显式输出 0（熄灭常亮 LED1/2/3）
    assign led_off = 3'b000;

endmodule