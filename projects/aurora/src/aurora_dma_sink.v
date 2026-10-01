`timescale 1ns / 1ps
/************************************************************
 * aurora_dma_sink.v — MM2S 数据接收器 (AXI-Stream slave)
 *
 * 作用：接收 BD 里 AXI DMA 从 DDR 读出的 M_AXIS_MM2S 流，
 *       目前"全接收丢弃"(回环/将来可改回灌 S2MM)。
 * 计数输出留作调试/回环铺垫(本版未接)。
 ************************************************************/
module aurora_dma_sink #(
    parameter DATA_WIDTH = 32
)(
    input  wire                aclk,
    input  wire                aresetn,

    // AXI-Stream slave (接 BD M_AXIS_MM2S)
    input  wire [DATA_WIDTH-1:0]   s_tdata,
    input  wire                    s_tvalid,
    output wire                    s_tready,
    input  wire                    s_tlast,

    // 调试计数 (预留)
    output reg  [31:0]          word_cnt_o,
    output reg  [31:0]          frame_cnt_o
);
    assign s_tready = 1'b1;   // 始终可接收(丢弃模式)

    always @(posedge aclk or negedge aresetn) begin
        if (~aresetn) begin
            word_cnt_o  <= 32'd0;
            frame_cnt_o <= 32'd0;
        end else if (s_tvalid & s_tready) begin
            word_cnt_o <= word_cnt_o + 32'd1;
            if (s_tlast) frame_cnt_o <= frame_cnt_o + 32'd1;
        end
    end

endmodule