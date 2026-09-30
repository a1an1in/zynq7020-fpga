`timescale 1ns / 1ps
`include "aurora_addr_def.vh"
/**************************************************************************
 * tb_aurora_regbank.v — P-BUS 架构端到端回验：
 *   AXI(master) -> aurora_regbank(路由) -> system/led/adc_regs -> aurora_led
 *
 * 覆盖：复位默认全灭 / SCRATCH 写读 / VERSION 只读 / LED value+ctrl 点亮、
 *       关断、status 回读 / SYS_CTRL 软复位自动清 / ADC 保留读 0 / 越界读 0。
 **************************************************************************/
module tb_aurora_regbank;

    // ---- 仿真时钟/复位 ----
    reg aclk = 1'b0;
    reg aresetn = 1'b0;
    always #5 aclk = ~aclk;

    // ---- AXI4-Lite 主端信号（tb 作为 master 驱动）----
    reg  [15:0] S_AXI_AWADDR;  reg S_AXI_AWVALID;
    wire        S_AXI_AWREADY;
    reg  [31:0] S_AXI_WDATA;   reg [3:0] S_AXI_WSTRB; reg S_AXI_WVALID;
    wire        S_AXI_WREADY;
    wire [1:0]  S_AXI_BRESP;   wire S_AXI_BVALID;    reg S_AXI_BREADY;
    reg  [15:0] S_AXI_ARADDR;  reg S_AXI_ARVALID;
    wire        S_AXI_ARREADY;
    wire [31:0] S_AXI_RDATA;   wire [1:0] S_AXI_RRESP; wire S_AXI_RVALID;
    reg         S_AXI_RREADY;

    // ---- P-BUS 干线（bank 广播, 读写分开按 AXI 先后, 单根读回）----
    wire        p_wvalid, p_rvalid;
    wire [15:0] p_waddr, p_raddr;
    wire [31:0] p_wdata;
    wire [3:0]  p_wstrb;
    wire [31:0] pb_rdata;                     // N 选 1 归并后单根读回

    // ---- 各从器握手拍命中标志与读回 ----
    wire        sys_o_rvalid, led_o_rvalid, adc_o_rvalid;
    wire [31:0] sys_o_rdata,  led_o_rdata,  adc_o_rdata;

    // ---- LED 通路 ----
    wire [31:0] led_o_value, led_o_ctrl, led_i_status;
    wire [3:0]  led_out, led_status_net;

    // ---- 复位后释放 ----
    initial begin
        S_AXI_AWADDR = 16'd0; S_AXI_AWVALID = 1'b0;
        S_AXI_WDATA  = 32'd0; S_AXI_WSTRB   = 4'b0000; S_AXI_WVALID = 1'b0;
        S_AXI_BREADY = 1'b0;
        S_AXI_ARADDR = 16'd0; S_AXI_ARVALID = 1'b0; S_AXI_RREADY = 1'b0;
        repeat (4) @(posedge aclk);
        aresetn = 1'b1;
    end

    assign led_i_status = {27'd0, led_o_ctrl[0], led_status_net[3:0]};

    // ---- N 选 1 归并：与 aurora_top.v 同一语义(OR 等价 3 选 1, 窗口两两不相交)----
    assign pb_rdata = sys_o_rdata | led_o_rdata | adc_o_rdata;

    // ===== DUT =====
    aurora_regbank u_regbank (
        .S_AXI_ACLK    (aclk),
        .S_AXI_ARESETN (aresetn),
        .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWVALID (S_AXI_AWVALID),
        .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA   (S_AXI_WDATA),
        .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),
        .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID),
        .S_AXI_BREADY  (S_AXI_BREADY),
        .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARVALID (S_AXI_ARVALID),
        .S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP   (S_AXI_RRESP),
        .S_AXI_RVALID  (S_AXI_RVALID),
        .S_AXI_RREADY  (S_AXI_RREADY),
        .p_wvalid      (p_wvalid),
        .p_waddr       (p_waddr),
        .p_wdata       (p_wdata),
        .p_wstrb       (p_wstrb),
        .p_rvalid      (p_rvalid),
        .p_raddr       (p_raddr),
        .p_rdata       (pb_rdata)
    );

    aurora_system_regs u_sysregs (
        .aclk(aclk), .aresetn(aresetn),
        .p_wvalid(p_wvalid), .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid(p_rvalid), .p_raddr(p_raddr),
        .o_rvalid(sys_o_rvalid), .o_rdata(sys_o_rdata),
        .o_scratch(), .o_ctrl()
    );
    aurora_led_regs u_ledregs (
        .aclk(aclk), .aresetn(aresetn),
        .p_wvalid(p_wvalid), .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid(p_rvalid), .p_raddr(p_raddr),
        .o_rvalid(led_o_rvalid), .o_rdata(led_o_rdata),
        .o_value(led_o_value), .o_ctrl(led_o_ctrl),
        .i_status(led_i_status)
    );
    aurora_adc_regs u_adcregs (
        .aclk(aclk), .aresetn(aresetn),
        .p_wvalid(p_wvalid), .p_waddr(p_waddr), .p_wdata(p_wdata), .p_wstrb(p_wstrb),
        .p_rvalid(p_rvalid), .p_raddr(p_raddr),
        .o_rvalid(adc_o_rvalid), .o_rdata(adc_o_rdata)
    );
    aurora_led u_ledio (
        .led_value_i (led_o_value[3:0]),
        .led_en_i    (led_o_ctrl[0]),
        .led_o       (led_out),
        .led_status_o(led_status_net)
    );

    // ---- (10) P-BUS 隔离监控：读握手拍(p_rvalid=1)时命中集必须为单热或全 0(越界)，
    //       绝不允许多个从器同时命中（N 选 1 归并正确性核心）。----
    reg iso_fail = 1'b0;
    always @(posedge aclk) begin
        if (p_rvalid && (sys_o_rvalid + led_o_rvalid + adc_o_rvalid) > 1)
            iso_fail <= 1'b1;
    end

    // ===== 任务：AXI 写 / 读 =====
    task axi_write;
        input [15:0] aaddr;
        input [31:0] adata;
        begin
            @(posedge aclk);
            S_AXI_AWADDR = aaddr; S_AXI_AWVALID = 1'b1;
            S_AXI_WDATA  = adata; S_AXI_WSTRB = 4'b1111; S_AXI_WVALID = 1'b1;
            while (!(S_AXI_AWVALID && S_AXI_AWREADY && S_AXI_WVALID && S_AXI_WREADY)) @(posedge aclk);
            @(posedge aclk);
            S_AXI_AWVALID = 1'b0; S_AXI_WVALID = 1'b0;
            while (!S_AXI_BVALID) @(posedge aclk);
            S_AXI_BREADY = 1'b1;
            @(posedge aclk); S_AXI_BREADY = 1'b0;
        end
    endtask

    task axi_read;
        input [15:0] aaddr;
        output [31:0] rdata;
        integer i;
        begin
            S_AXI_ARADDR = aaddr; S_AXI_ARVALID = 1'b1;
            // bank 读为"接受→登记地址→从器译码→返回"三段式, ARREADY=ARVALID&~ar_busy
            // 组合反冲, 数据 2 拍后经 RVALID 返回. 每拍 posedge 用 #1 让 NBA 更新可采样.
            while (!S_AXI_RVALID) begin @(posedge aclk); #1; end
            rdata = S_AXI_RDATA;
            S_AXI_RREADY = 1'b1;
            @(posedge aclk); #1;
            S_AXI_RREADY = 1'b0; S_AXI_ARVALID = 1'b0;
            while (S_AXI_RVALID) begin @(posedge aclk); #1; end   // 等 rvalid 回落收尾
        end
    endtask

    // ===== 测试主体 =====
    integer pass = 0, fail = 0;
    reg [31:0] rd;

    initial begin
        @(posedge aresetn);
        @(posedge aclk);

        // (1) 复位默认 LED 全灭
        if (led_out == 4'b0000) pass = pass + 1;
        else begin fail = fail + 1; $display("FAIL 1 默认LED全灭: led=%b", led_out); end

        // (2) SCRATCH 写读
        axi_write (`AURORA_SYSTEM_SCRATCH, 32'hDEADBEEF);
        axi_read  (`AURORA_SYSTEM_SCRATCH, rd);
        if (rd == 32'hDEADBEEF) pass = pass + 1;
        else begin fail = fail + 1; $display("FAIL 2 SCRATCH 回读 %h", rd); end

        // (3) VERSION 只读
        axi_read (`AURORA_SYSTEM_VERSION, rd);
        if (rd == `AURORA_VERSION) pass = pass + 1;
        else begin fail = fail + 1; $display("FAIL 3 VERSION=%h", rd); end

        // (4) LED: 写 value=0xA, ctrl=1 -> 点亮
        axi_write (`AURORA_LED_VALUE, 32'h0000000A);
        axi_write (`AURORA_LED_CTRL,  32'h00000001);
        if (led_out == 4'b1010) pass = pass + 1;
        else begin fail = fail + 1; $display("FAIL 4 LED 点亮 led=%b", led_out); end

        // (5) LED: 关使能 -> 全灭
        axi_write (`AURORA_LED_CTRL, 32'h00000000);
        if (led_out == 4'b0000) pass = pass + 1;
        else begin fail = fail + 1; $display("FAIL 5 LED 熄灭 led=%b", led_out); end

        // (6) LED: 重新点亮, 回读 status = {en, led_out}
        axi_write (`AURORA_LED_VALUE, 32'h00000005);
        axi_write (`AURORA_LED_CTRL,  32'h00000001);
        axi_read  (`AURORA_LED_STATUS, rd);
        if (rd[4] == 1'b1 && rd[3:0] == 4'b0101) pass = pass + 1;
        else begin fail = fail + 1; $display("FAIL 6 status=%h", rd); end

        // (7) SYS_CTRL autoclear: 写 bit0=1 后读回 0
        axi_write (`AURORA_SYSTEM_CTRL, 32'h00000001);
        axi_read  (`AURORA_SYSTEM_CTRL, rd);
        if (rd[0] == 1'b0) pass = pass + 1;
        else begin fail = fail + 1; $display("FAIL 7 软复位未自动清 ctrl=%h", rd); end

        // (8) ADC 预留读 0
        axi_read (`AURORA_ADC_CTRL,  rd); if (rd != 0) begin fail = fail + 1; $display("FAIL 8a adc.ctrl=%h", rd); end else pass = pass + 1;
        axi_read (`AURORA_ADC_STATUS,rd); if (rd != 0) begin fail = fail + 1; $display("FAIL 8b adc.status=%h", rd); end else pass = pass + 1;
        axi_read (`AURORA_ADC_DATA,  rd); if (rd != 0) begin fail = fail + 1; $display("FAIL 8c adc.data=%h", rd); end else pass = pass + 1;

        // (9) 越界 / 空洞读 0
        axi_read (32'h00C0, rd); if (rd != 0) begin fail = fail + 1; $display("FAIL 9a OOR=%h", rd); end else pass = pass + 1;
        axi_read (32'h000C, rd); if (rd != 0) begin fail = fail + 1; $display("FAIL 9b gap=%h", rd); end else pass = pass + 1;

        // (10) 隔离：全程读握手拍从未出现"多人命中"
        if (iso_fail == 1'b0) pass = pass + 1;
        else begin fail = fail + 1; $display("FAIL 10 隔离: 出现多人命中"); end

        $display("--------------------------------------------------");
        $display("RESULT: %0d passed, %0d failed", pass, fail);
        if (fail == 0) $display(">>> ALL TESTS PASSED");
        else           $display(">>> TESTS FAILED");
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $fatal;
    end
endmodule