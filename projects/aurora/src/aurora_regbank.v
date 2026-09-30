`timescale 1ns / 1ps
// ----------------------------------------------------------------------------
// aurora_regbank.v — 手写固定(非生成). 纯 AXI4-Lite 从 + P-BUS 广播/读回.
// 特征:
//   * 零外设业务(寄存器从器在 src/regs/, bank 完全不认识块、不认识地址窗口).
//   * 32bit 单根 p_rdata 读回, N 选 1 归并在 aurora_top.v 完成.
//   * 读写分开(p_wvalid/p_waddr/p_wdata/p_wstrb 与 p_rvalid/p_raddr),
//     AXI 通道握手保证"先后", 无写优先抢占.
//   * 读握手拍广播 p_rvalid 并在同拍锁 p_rdata(组合归并值) 进 ar_data.
// ----------------------------------------------------------------------------
module aurora_regbank #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 16
)(
    input  wire S_AXI_ACLK,
    input  wire S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire S_AXI_WVALID,
    output wire S_AXI_WREADY,
    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input  wire S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input  wire S_AXI_RREADY,
    // ---------- P-BUS (读写分开, 按 AXI 先后) ----------
    output wire p_wvalid,
    output wire [C_S_AXI_ADDR_WIDTH-1:0] p_waddr,
    output wire [C_S_AXI_DATA_WIDTH-1:0] p_wdata,
    output wire [C_S_AXI_DATA_WIDTH/8-1:0] p_wstrb,
    output wire p_rvalid,
    output wire [C_S_AXI_ADDR_WIDTH-1:0] p_raddr,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] p_rdata
);
    localparam C_DATA = C_S_AXI_DATA_WIDTH;
    localparam C_ADDR = C_S_AXI_ADDR_WIDTH;

    // ---------------- 写通道: 标准 AXI (AW+W 同时到齐一握手) ----------------
    wire wr_hs = S_AXI_AWVALID & S_AXI_WVALID & ~S_AXI_BVALID;
    assign p_wvalid     = wr_hs;
    assign p_waddr      = S_AXI_AWADDR[C_ADDR-1:0];
    assign p_wdata      = S_AXI_WDATA;
    assign p_wstrb      = S_AXI_WSTRB;
    assign S_AXI_AWREADY = wr_hs;
    assign S_AXI_WREADY  = wr_hs;
    assign S_AXI_BRESP   = 2'b00;

    reg axi_bvalid;
    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (~S_AXI_ARESETN)          axi_bvalid <= 1'b0;
        else if (wr_hs)              axi_bvalid <= 1'b1;
        else if (S_AXI_BVALID && S_AXI_BREADY) axi_bvalid <= 1'b0;
    end
    assign S_AXI_BVALID = axi_bvalid;

    // ---------------- 读通道(确定性: 接受 → 呈现 → 返回) ----------------
    // 握手拍接受并登记地址; 下一拍用登记地址驱动从器(p_rvalid/p_raddr)组合译码,
    // 稳定后再采样进 ar_data --- 不采样“握手拍”上的活组合, 规避 delta 竞争.
    wire rd_hs = S_AXI_ARVALID & ~ar_busy;
    assign S_AXI_ARREADY = rd_hs;

    reg        ar_busy;                       // 已接受读请求, 正在向从器呈现址
    reg [C_ADDR-1:0] ar_addr;                 // 握手拍登记地址
    reg        ar_done;                       // 数据就绪 = S_AXI_RVALID
    reg [C_DATA-1:0] ar_data;

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (~S_AXI_ARESETN)                     ar_busy <= 1'b0;
        else if (rd_hs)                         ar_busy <= 1'b1;
        else if (ar_busy && ar_done && S_AXI_RREADY) ar_busy <= 1'b0;
    end

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (~S_AXI_ARESETN)                     ar_addr <= {C_ADDR{1'b0}};
        else if (rd_hs)                         ar_addr <= S_AXI_ARADDR[C_ADDR-1:0];
    end

    // 用登记地址驱动从器: p_raddr 为寄存器, 从器组合译码 p_rdata 全程稳定.
    assign p_rvalid = ar_busy;
    assign p_raddr  = ar_addr;

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (~S_AXI_ARESETN)       begin ar_done <= 1'b0; ar_data <= {C_DATA{1'b0}}; end
        else if (ar_done && S_AXI_RREADY) ar_done <= 1'b0;   // 完成即清(优先于 busy 重置)
        else if (ar_busy)         begin ar_done <= 1'b1; ar_data <= p_rdata; end
    end

    assign S_AXI_RVALID = ar_done;
    assign S_AXI_RDATA  = ar_data;
    assign S_AXI_RRESP  = 2'b00;

endmodule