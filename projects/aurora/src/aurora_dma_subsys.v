`timescale 1ns / 1ps
/************************************************************
 * aurora_dma_subsys.v — DMA 子系统（把 dma 从器/数据源/接收器收敛成一块）
 *
 * 把原来散落在 aurora_top 里的：
 *     aurora_dma_regs + 状态回填 + aurora_dma_src(S2MM) + aurora_dma_sink(MM2S)
 * 集中到一个外壳。顶层只需：
 *   1) 例化一个 P-BUS 从器（与 led/adc 同风格，一行）；
 *   2) 把 S_AXIS_S2MM / M_AXIS_MM2S 流网连到本壳的流端口。
 * 之后调 DMA 时序/状态/FIFO 只改本文件，不用再动 aurora_top。
 ************************************************************/
module aurora_dma_subsys (
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

    // ---- 到 BD：S2MM (假数据源 -> AXI DMA -> 写 DDR) ----
    output wire [63:0]  s2mm_tdata,
    output wire         s2mm_tvalid,
    input  wire         s2mm_tready,
    output wire [7:0]   s2mm_tkeep,
    output wire         s2mm_tlast,

    // ---- 来自 BD：MM2S (读回，接收丢弃/回环预留) ----
    input  wire [31:0]  mm2s_tdata,
    input  wire         mm2s_tvalid,
    output wire         mm2s_tready,
    input  wire         mm2s_tlast
);
    // dma 寄存器块输出
    wire [31:0] dma_o_ctrl, dma_o_len;
    wire [31:0] dma_i_status, dma_src_status;
    wire        dma_o_rvalid;
    wire [31:0] dma_o_rdata;
    wire        dma_busy, dma_done;
    wire [7:0]  dma_frames;

    // dma 寄存器块（P-BUS 从器）
    aurora_dma_regs u_dmaregs (
        .aclk    (aclk),
        .aresetn (aresetn),
        .p_wvalid(p_wvalid), .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid(p_rvalid), .p_raddr(p_raddr),
        .o_rvalid(dma_o_rvalid), .o_rdata(dma_o_rdata),
        .o_ctrl  (dma_o_ctrl),
        .o_len   (dma_o_len),
        .i_status(dma_i_status)
    );

    // 假数据源 -> 状态回填: [15:8]帧数 [1]本帧完成(一拍) [0]busy
    assign dma_src_status = {16'd0, dma_frames, 6'd0, dma_done, dma_busy};
    assign dma_i_status   = dma_src_status;

    // 假数据源（S2MM，写 DDR）
    aurora_dma_src u_dmasrc (
        .aclk     (aclk),
        .aresetn  (aresetn),
        .run_i    (dma_o_ctrl[0]),
        .len_i    (dma_o_len[15:0]),
        .busy_o   (dma_busy),
        .done_o   (dma_done),
        .frames_o (dma_frames),
        .m_tvalid (s2mm_tvalid),
        .m_tready (s2mm_tready),
        .m_tdata  (s2mm_tdata),
        .m_tkeep  (s2mm_tkeep),
        .m_tlast  (s2mm_tlast)
    );

    // MM2S 接收（读回丢弃/回环预留）
    aurora_dma_sink u_dmasink (
        .aclk       (aclk),
        .aresetn    (aresetn),
        .s_tdata    (mm2s_tdata),
        .s_tvalid   (mm2s_tvalid),
        .s_tready   (mm2s_tready),
        .s_tlast    (mm2s_tlast),
        .word_cnt_o (),
        .frame_cnt_o()
    );

    // P-BUS 从口输出（供 top N 选 1 归并）
    assign o_rvalid = dma_o_rvalid;
    assign o_rdata  = dma_o_rdata;
endmodule