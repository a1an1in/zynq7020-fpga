`timescale 1ns / 1ps
/************************************************************
 * aurora_dma_src.v — 假数据源 (fake AXI-Stream master)
 *
 * 作用：产生确定性的 32bit 帧数据流，喂给 BD 里的 AXI DMA S2MM，
 *       从而建立 PL->PS 的假数据通路（写 DDR）。
 * 数据模式：m_tdata = { 16'h5AA5, word_index[15:0] }，便于 PS 侧核对。
 * 控制：由 dma 寄存器块 o_ctrl[0](RUN) 上升沿启动发一帧；帧长 o_len 字。
 * 状态：busy/done/frames(已发帧数) 回填 dma_regs.i_status。
 ************************************************************/
module aurora_dma_src #(
    parameter DATA_WIDTH = 32
)(
    input  wire                aclk,
    input  wire                aresetn,

    // 控制 (来自 aurora_dma_regs)
    input  wire                run_i,        // 上升沿启动一帧 (regs 已 autoclear)
    input  wire [15:0]         len_i,        // 每帧字数 (>=1)

    // 状态 (回填 aurora_dma_regs.i_status)
    output wire                busy_o,       // bit0: 正在发送
    output wire                done_o,       // bit1: 本帧发送完成(一拍脉冲)
    output reg  [7:0]          frames_o,     // [15:8]: 已发帧数(回绕)

    // AXI-Stream master (接到 BD S_AXIS_S2MM)
    output wire                m_tvalid,
    input  wire                m_tready,
    output wire [DATA_WIDTH-1:0]   m_tdata,
    output wire [DATA_WIDTH/8-1:0] m_tkeep,
    output wire                m_tlast
);
    localparam [3:0] STRB_W = DATA_WIDTH/8;

    // ---- 帧生成状态机 ----
    reg              run_q;
    wire             run_rise = run_i & ~run_q;
    reg  [15:0]      idx;          // 当前字下标 (0..len-1)
    reg  [15:0]      len_r;        // 锁存的帧长
    reg              busy_reg;
    reg              done_sticky;  // 本帧完成标志, 新 RUN 清

    wire last_word = (idx == (len_r - 16'd1));

    always @(posedge aclk or negedge aresetn) begin
        if (~aresetn) begin
            run_q       <= 1'b0;
            idx         <= 16'd0;
            len_r       <= 16'd1;
            busy_reg    <= 1'b0;
            done_sticky <= 1'b0;
            frames_o    <= 8'd0;
        end else begin
            run_q <= run_i;

            // 新 RUN 清帧完成标志
            if (run_rise) done_sticky <= 1'b0;

            if (run_rise && ~busy_reg) begin
                // 启动一帧
                busy_reg <= 1'b1;
                idx      <= 16'd0;
                len_r    <= (len_i == 16'd0) ? 16'd1 : len_i;
            end else if (busy_reg && m_tvalid && m_tready) begin
                // 握手步进
                if (last_word) begin
                    busy_reg    <= 1'b0;          // 发完最后一字
                    idx         <= 16'd0;
                    done_sticky <= 1'b1;
                    frames_o    <= frames_o + 8'd1;
                end else begin
                    idx <= idx + 16'd1;
                end
            end
        end
    end

    // ---- AXI-Stream 输出 ----
    assign m_tvalid = busy_reg;
    assign m_tdata  = {16'h5AA5, idx[15:0]};
    assign m_tkeep  = {STRB_W{1'b1}};
    assign m_tlast  = busy_reg & last_word;

    // ---- 状态回填 ----
    assign busy_o = busy_reg;
    assign done_o = (busy_reg & m_tvalid & m_tready & last_word); // 最后一字握手拍

endmodule