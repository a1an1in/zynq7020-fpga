/************************************************************
 * aurora_top.v — aurora 整系统顶层 (P-BUS 架构)。
 *
 * 结构：
 *   system_wrapper (PS: DDR/FIXED_IO/以太, M_AXI_GP0)
 *        │  M00_AXI_*  (BD 引出的外部 AXI4-Lite 主接口, 0x40000000 唯一窗口)
 *        ▼
 *   aurora_regbank    (手写固定 = 纯 AXI4-Lite 从 + P-BUS 广播/读回, 32bit,
 *                       零外设业务、不认识块；寄存器从器在 src/regs/ 由工具生成)
 *        │  P-BUS(读写分开, 按 AXI 先后): p_wvalid/p_waddr/p_wdata/p_wstrb,
 *        │                                p_rvalid/p_raddr, 单根 p_rdata 读回
 *        ├─── aurora_system_regs (生成: scratch/version/ctrl.ctrl[0] 软复位自动清)
 *        ├─── aurora_led_subsys  (LED 子系统壳：寄存器+管脚逻辑 收敛为一块)
 *        │         │ value/ctrl   status      │ led_o / led_off
 *        │         ▼                          │
 *        │   内部: aurora_led_regs + aurora_led(管脚逻辑)
 *        └─ aurora_dma_subsys  (DMA 子系统壳：寄存器+假数据源+MM2S 接收收敛为一块)
 *                 │  ctrl/len   status     │ S_AXIS_S2MM -> BD AXI DMA -> S_AXI_HP0 写 DDR
 *                 ▼                        │ 读回 M_AXIS_MM2S（丢弃/回环预留）
 *           内部: aurora_dma_regs + aurora_dma_src(假源) + aurora_dma_sink(接收)
 *
 * 时钟/复位：AXI 与 PS 同为 FCLK_CLK0(100MHz)，复位 FCLK_RESET0_N(低有效)。
 * sysclk_p / rstn_i 保留端口供约束文件引用，本版不用。
 ************************************************************/
`include "aurora_addr_def.vh"

module aurora_top (
    // ---- PS 内存接口（DDR + 固定IO），透传保证 DDR 工作 ----
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

    // ---- 保留：板载时钟/复位（约束文件引用；本版用 PS 时钟/复位）----
    input         sysclk_p,
    input         rstn_i,

    // ---- PL 侧独立 IO：寄存器控制的 LED（LVCMOS33, E16/F16/H18/H17）----
    output [3:0]  led_o,

    // ---- 常亮三颗 LED（H15/R15/C15），显式拉 0 熄灭（同 run_led）----
    output [2:0]  led_off
);

    // ------------------------------------------------------------------
    // 互联线网
    // ------------------------------------------------------------------
    wire        fclk_clk0;
    wire        fclk_reset0_n;
    wire [31:0] m00_awaddr;
    wire        m00_awvalid, m00_awready;
    wire [31:0] m00_wdata;
    wire [3:0]  m00_wstrb;
    wire        m00_wvalid, m00_wready;
    wire [1:0]  m00_bresp;
    wire        m00_bvalid, m00_bready;
    wire [31:0] m00_araddr;
    wire        m00_arvalid, m00_arready;
    wire [31:0] m00_rdata;
    wire [1:0]  m00_rresp;
    wire        m00_rvalid, m00_rready;
    wire [2:0]  m00_awprot, m00_arprot;   // master 输出, 本设计不使用

    // ---- P-BUS 干线（regbank 广播到各从器, 读写分开、按 AXI 先后）----
    wire        p_wvalid, p_rvalid;
    wire [15:0] p_waddr, p_raddr;
    wire [31:0] p_wdata;
    wire [3:0]  p_wstrb;
    wire [31:0] pb_rdata;                    // N 选 1 归并后的单根读回总线

    // ---- 各从器握手拍命中标志与读回（供 top N 选 1 归并）----
    wire        sys_o_rvalid, led_o_rvalid, adc_o_rvalid;
    wire [31:0] sys_o_rdata,  led_o_rdata,  adc_o_rdata;

    // ---- DMA 通路：壳子对外只留 P-BUS 从口 + 流网；内部 regs/src/sink 收敛在 aurora_dma_subsys ----
    wire        dma_o_rvalid;
    wire [31:0] dma_o_rdata;
    // AXI-Stream 数据网 (aurora_dma_subsys <-> wrapper BD)
    wire [63:0] s2mm_tdata;
    wire [31:0] mm2s_tdata;
    wire        s2mm_tvalid, s2mm_tready, s2mm_tlast;
    wire [7:0]  s2mm_tkeep;
    wire        mm2s_tvalid, mm2s_tready, mm2s_tlast;

    // ------------------------------------------------------------------
    // 例化 PS 系统（Block Design「system」的 wrapper）
    // ------------------------------------------------------------------
    system_wrapper ps_system (
        .DDR_addr         (DDR_addr),
        .DDR_ba           (DDR_ba),
        .DDR_cas_n        (DDR_cas_n),
        .DDR_ck_n         (DDR_ck_n),
        .DDR_ck_p         (DDR_ck_p),
        .DDR_cke          (DDR_cke),
        .DDR_cs_n         (DDR_cs_n),
        .DDR_dm           (DDR_dm),
        .DDR_dq           (DDR_dq),
        .DDR_dqs_n        (DDR_dqs_n),
        .DDR_dqs_p        (DDR_dqs_p),
        .DDR_odt          (DDR_odt),
        .DDR_ras_n        (DDR_ras_n),
        .DDR_reset_n      (DDR_reset_n),
        .DDR_we_n         (DDR_we_n),
        .FIXED_IO_ddr_vrn (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio     (FIXED_IO_mio),
        .FIXED_IO_ps_clk  (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .FCLK_CLK0        (fclk_clk0),
        .FCLK_RESET0_N    (fclk_reset0_n),
        .M00_AXI_awaddr   (m00_awaddr),
        .M00_AXI_awprot   (m00_awprot),
        .M00_AXI_awvalid  (m00_awvalid),
        .M00_AXI_awready  (m00_awready),
        .M00_AXI_wdata    (m00_wdata),
        .M00_AXI_wstrb    (m00_wstrb),
        .M00_AXI_wvalid   (m00_wvalid),
        .M00_AXI_wready   (m00_wready),
        .M00_AXI_bresp    (m00_bresp),
        .M00_AXI_bvalid   (m00_bvalid),
        .M00_AXI_bready   (m00_bready),
        .M00_AXI_araddr   (m00_araddr),
        .M00_AXI_arprot   (m00_arprot),
        .M00_AXI_arvalid  (m00_arvalid),
        .M00_AXI_arready  (m00_arready),
        .M00_AXI_rdata    (m00_rdata),
        .M00_AXI_rresp    (m00_rresp),
        .M00_AXI_rvalid   (m00_rvalid),
        .M00_AXI_rready   (m00_rready),
        .S_AXIS_S2MM_tdata  (s2mm_tdata),
        .S_AXIS_S2MM_tvalid (s2mm_tvalid),
        .S_AXIS_S2MM_tready (s2mm_tready),
        .S_AXIS_S2MM_tkeep  (s2mm_tkeep),
        .S_AXIS_S2MM_tlast  (s2mm_tlast),
        .M_AXIS_MM2S_tdata  (mm2s_tdata),
        .M_AXIS_MM2S_tvalid (mm2s_tvalid),
        .M_AXIS_MM2S_tready (mm2s_tready),
        .M_AXIS_MM2S_tlast  (mm2s_tlast)
    );

    // ------------------------------------------------------------------
    // P-BUS 主机：生成器产出的纯路由 regbank（无任何外设业务）
    // ------------------------------------------------------------------
    aurora_regbank #(
        .C_S_AXI_DATA_WIDTH (32),
        .C_S_AXI_ADDR_WIDTH (16)
    ) u_regbank (
        .S_AXI_ACLK    (fclk_clk0),
        .S_AXI_ARESETN (fclk_reset0_n),
        .S_AXI_AWADDR  (m00_awaddr[15:0]),
        .S_AXI_AWVALID (m00_awvalid),
        .S_AXI_AWREADY (m00_awready),
        .S_AXI_WDATA   (m00_wdata),
        .S_AXI_WSTRB   (m00_wstrb),
        .S_AXI_WVALID  (m00_wvalid),
        .S_AXI_WREADY  (m00_wready),
        .S_AXI_BRESP   (m00_bresp),
        .S_AXI_BVALID  (m00_bvalid),
        .S_AXI_BREADY  (m00_bready),
        .S_AXI_ARADDR  (m00_araddr[15:0]),
        .S_AXI_ARVALID (m00_arvalid),
        .S_AXI_ARREADY (m00_arready),
        .S_AXI_RDATA   (m00_rdata),
        .S_AXI_RRESP   (m00_rresp),
        .S_AXI_RVALID  (m00_rvalid),
        .S_AXI_RREADY  (m00_rready),
        .p_wvalid      (p_wvalid),
        .p_waddr       (p_waddr),
        .p_wdata       (p_wdata),
        .p_wstrb       (p_wstrb),
        .p_rvalid      (p_rvalid),
        .p_raddr       (p_raddr),
        .p_rdata       (pb_rdata)
    );

    // ------------------------------------------------------------------
    // P-BUS 从器们（各自承载自己的寄存器/业务，regbank 不关心）
    // ------------------------------------------------------------------
    // N 选 1 归并：各从器 o_rdata 为按地址自译码(addr_hit)，窗口两两不相交，
    // 故 OR 即等价 3 选 1，且与 p_rvalid 时序无关——bank 读握手拍锁存稳定值。
    assign pb_rdata = sys_o_rdata | led_o_rdata | adc_o_rdata | dma_o_rdata;

    aurora_system_regs u_sysregs (
        .aclk    (fclk_clk0),
        .aresetn (fclk_reset0_n),
        .p_wvalid(p_wvalid), .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid(p_rvalid), .p_raddr(p_raddr),
        .o_rvalid(sys_o_rvalid), .o_rdata(sys_o_rdata),
        .o_scratch(),
        .o_ctrl   ()
    );

    aurora_adc_regs u_adcregs (
        .aclk    (fclk_clk0),
        .aresetn (fclk_reset0_n),
        .p_wvalid(p_wvalid), .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid(p_rvalid), .p_raddr(p_raddr),
        .o_rvalid(adc_o_rvalid), .o_rdata(adc_o_rdata)
    );

    // ------------------------------------------------------------------
    // LED 子系统: 寄存器 + 管脚逻辑 收敛成一个壳（同 dma 风格）
    // ------------------------------------------------------------------
    aurora_led_subsys u_led (
        .aclk        (fclk_clk0),
        .aresetn     (fclk_reset0_n),
        .p_wvalid    (p_wvalid),
        .p_waddr     (p_waddr),
        .p_wdata     (p_wdata),
        .p_wstrb     (p_wstrb),
        .p_rvalid    (p_rvalid),
        .p_raddr     (p_raddr),
        .o_rvalid    (led_o_rvalid),
        .o_rdata     (led_o_rdata),
        .led_o       (led_o),
        .led_off     (led_off)
    );

    // ------------------------------------------------------------------
    // DMA 子系统: 寄存器 + 假数据源(S2MM->写 DDR) + MM2S 接收，收敛成一个壳
    // 后续调 DMA 时序/状态/RTL 只改 aurora_dma_subsys.v，不必再动本顶层
    // ------------------------------------------------------------------
    aurora_dma_subsys u_dma (
        .aclk        (fclk_clk0),
        .aresetn     (fclk_reset0_n),
        .p_wvalid    (p_wvalid),
        .p_waddr     (p_waddr),
        .p_wdata     (p_wdata),
        .p_wstrb     (p_wstrb),
        .p_rvalid    (p_rvalid),
        .p_raddr     (p_raddr),
        .o_rvalid    (dma_o_rvalid),
        .o_rdata     (dma_o_rdata),
        .s2mm_tdata  (s2mm_tdata),
        .s2mm_tvalid (s2mm_tvalid),
        .s2mm_tready (s2mm_tready),
        .s2mm_tkeep  (s2mm_tkeep),
        .s2mm_tlast  (s2mm_tlast),
        .mm2s_tdata  (mm2s_tdata),
        .mm2s_tvalid (mm2s_tvalid),
        .mm2s_tready (mm2s_tready),
        .mm2s_tlast  (mm2s_tlast)
    );

endmodule