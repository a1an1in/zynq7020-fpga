`timescale 1ns/1ps
/************************************************************
 * tb_aurora_dma_subsys.v - 集成验证 aurora_dma_subsys 壳（重构后）：
 *   P-BUS 写 ctrl(RUN)/len -> 假数据源应通过 S2MM 流发出一帧；
 *   ctrl 自动清；status 经 P-BUS 读回 busy/done/frames；归并口 o_rdata 正确。
 * 跑法：iverilog -g2012 -I<src> -o /tmp/tb_sub aurora_dma_subsys.v
 *        aurora_dma_regs.v aurora_dma_src.v aurora_dma_sink.v 本文件 && vvp
 ************************************************************/
module tb_aurora_dma_subsys;
    // 寄存器地址（与 aurora_addr_def.vh 一致，硬编码便于无 include）
    localparam DMA_CTRL   = 16'h0030;  // bit0=RUN(自动清)
    localparam DMA_LEN    = 16'h0034;
    localparam DMA_STATUS = 16'h0038;  // [0]busy [1]done [15:8]frames

    reg         aclk = 0, aresetn = 0;
    reg         p_wvalid = 0; reg [15:0] p_waddr; reg [31:0] p_wdata; reg [3:0] p_wstrb = 0;
    reg         p_rvalid = 0; reg [15:0] p_raddr;
    wire        o_rvalid; wire [31:0] o_rdata;

    // S2MM master (DTW=64)
    wire [63:0] s2mm_tdata; wire s2mm_tvalid, s2mm_tlast; reg s2mm_tready = 1; wire [7:0] s2mm_tkeep;
    // MM2S slave (丢弃)
    reg  [31:0] mm2s_tdata = 0; reg mm2s_tvalid = 0, mm2s_tlast = 0;
    wire mm2s_tready;

    aurora_dma_subsys u_dut (
        .aclk      (aclk),
        .aresetn   (aresetn),
        .p_wvalid  (p_wvalid),   .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid  (p_rvalid),   .p_raddr(p_raddr),
        .o_rvalid  (o_rvalid),   .o_rdata(o_rdata),
        .s2mm_tdata(s2mm_tdata), .s2mm_tvalid(s2mm_tvalid),
        .s2mm_tready(s2mm_tready), .s2mm_tkeep(s2mm_tkeep), .s2mm_tlast(s2mm_tlast),
        .mm2s_tdata(mm2s_tdata), .mm2s_tvalid(mm2s_tvalid),
        .mm2s_tready(mm2s_tready), .mm2s_tlast(mm2s_tlast)
    );

    always #5 aclk = ~aclk;

    // ---- P-BUS 读写任务 ----
    reg [31:0] rd;
    task pb_write(input [15:0] a, input [31:0] d);
        @(posedge aclk); p_wvalid=1; p_waddr=a; p_wdata=d; p_wstrb=4'hf;
        @(posedge aclk); p_wvalid=0; p_wstrb=0;
    endtask
    // 读：保持 p_rvalid 直到 o_rvalid 到来，采稳定值
    task pb_read(input [15:0] a, output [31:0] v);
        begin
            p_rvalid = 0;
            @(posedge aclk);
            p_rvalid = 1; p_raddr = a;   // 阻塞赋值后组合 o_rdata 即刻稳定
            @(posedge aclk);
            v = o_rdata;
            p_rvalid = 0;
            p_raddr  = 16'h0;
            @(posedge aclk);
        end
    endtask

    // ---- 观测 S2MM 流 ----
    integer beats = 0;
    reg    final_ok = 0;
    reg    saw_busy  = 0;
    always @(posedge aclk)
        if (s2mm_tvalid && s2mm_tready) begin
            beats = beats + 1;
            if (s2mm_tlast) final_ok = 1;
        end

    // ---- 统计 ----
    integer npass = 0, nfail = 0;
    task chk(input [255:0] msg, input cond);
        begin
            if (cond) begin npass = npass+1; $display("  PASS: %0s", msg); end
            else      begin nfail = nfail+1; $display("  FAIL: %0s", msg); end
        end
    endtask

    reg [31:0] sv;
    initial begin
        $dumpfile("/tmp/tb_subsys.vcd");
        $dumpvars(0, tb_aurora_dma_subsys);
        repeat (3) @(posedge aclk); aresetn <= 1; repeat (2) @(posedge aclk);

        $display("== T1: 复位后状态 ==");
        pb_read(DMA_STATUS, sv);
        chk("status 初始 busy=0 frames=0", (sv[0]==0) && (sv[15:8]==0));
        pb_read(DMA_CTRL, sv);
        chk("ctrl 初始=0", sv[31:0]==0);

        $display("== T2: 写 len=8 + RUN，观察一帧 ==");
        beats = 0; final_ok = 0;
        pb_write(DMA_LEN, 32'd8);
        pb_write(DMA_CTRL, 32'd1);          // RUN
        // 等待完成（busy 回落且 frames 变非 0）
        begin : w
            repeat (300) begin
                @(posedge aclk);
                pb_read(DMA_STATUS, sv);
                if (sv[0]) saw_busy = 1;
                if ((sv[0]==0) && (sv[15:8]==1)) disable w;
            end
        end
        @(posedge aclk);
        pb_read(DMA_STATUS, sv);
        chk("S2MM 发出 8 拍", beats == 8);
        chk("最后一拍有 tlast", final_ok == 1);
        chk("发送期间 busy 出现过", saw_busy == 1);
        chk("frames=1", sv[15:8] == 1);
        pb_read(DMA_CTRL, sv);
        chk("ctrl RUN 自动清为 0", sv[0] == 0);

        $display("============================================");
        $display("TCPASS=%0d TCFAIL=%0d", npass, nfail);
        if (nfail == 0) $display("SUBSYS_SIM: PASS");
        else            $display("SUBSYS_SIM: FAIL");
        $finish;
    end

    initial begin
        #50000; $display("FAIL: 仿真超时"); $finish;
    end
endmodule