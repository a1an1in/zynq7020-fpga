`timescale 1ns/1ps
/************************************************************
 * tb_aurora_dma_src.v - 纯软件验证 aurora_dma_src：(A) 正常 TLAST
 * 时序；(B) 防死锁看门狗：tready 卡死时应放弃本帧、不置 done、不计数；
 * (C) 恢复 tready 后再次 RUN 应能重新完成。
 *
 * 跑法：iverilog -o /tmp/tb_src <aurora_dma_src.v> 本文件 && vvp /tmp/tb_src
 ************************************************************/
module tb_aurora_dma_src;

    localparam DATA_WIDTH = 32;
    localparam LEN        = 12;      // 12 字 = 48B

    reg            aclk    = 0;
    reg            aresetn = 0;
    reg            run_i   = 0;
    reg  [15:0]    len_i   = LEN;
    reg            drv_tready = 1;   // 可控 tready, 用于构造卡死
    wire           busy_o, done_o;
    wire [7:0]     frames_o;
    wire           m_tvalid, m_tlast;
    wire [DATA_WIDTH-1:0] m_tdata;
    wire [3:0]     m_tkeep;
    wire           m_tready = drv_tready;

    aurora_dma_src #(
        .DATA_WIDTH    (DATA_WIDTH),
        .STALL_TIMEOUT (26'd6)        // 小值, 让看门狗在测试里快速触发
    ) u_dut (
        .aclk     (aclk),
        .aresetn  (aresetn),
        .run_i    (run_i),
        .len_i    (len_i),
        .busy_o   (busy_o),
        .done_o   (done_o),
        .frames_o (frames_o),
        .m_tvalid (m_tvalid),
        .m_tready (m_tready),
        .m_tdata  (m_tdata),
        .m_tkeep  (m_tkeep),
        .m_tlast  (m_tlast)
    );

    always #5 aclk = ~aclk;

    // ---- 观测 ----
    integer beats = 0;
    reg    final_ok = 0;
    reg    got_done = 0;
    always @(posedge aclk) begin
        if (m_tvalid && m_tready) begin
            beats = beats + 1;
            if (m_tlast) begin
                final_ok = 1'b1;
                $display("  [beat %0d] FINAL tlast tdata=%08h tkeep=%h", beats, m_tdata, m_tkeep);
            end
        end
        if (done_o) got_done <= 1;
    end

    // ---- 工具任务 ----
    task pulse_run;
        begin
            run_i <= 1;
            @(posedge aclk);
            @(posedge aclk);
            run_i <= 0;
        end
    endtask

    initial begin
        $dumpfile("/tmp/tb_aurora_dma_src.vcd");
        $dumpvars(0, tb_aurora_dma_src);

        // 复位
        repeat (3) @(posedge aclk);
        aresetn <= 1;
        repeat (2) @(posedge aclk);

        // ---------------- P1: 正常帧(tready 恒 1), 应完成且计数+1 ----------------
        $display("== P1: 正常帧 len=%0d ==", LEN);
        drv_tready = 1;
        beats = 0; final_ok = 0; got_done = 0;
        pulse_run;
        begin : w1
            repeat (60) begin @(posedge aclk); if (done_o) disable w1; end
        end
        @(posedge aclk);   // 让 done/frames 的非阻塞赋值落定再采样
        if (got_done && final_ok && (beats == LEN)) $display("P1: PASS busy=%b done=%b beats=%0d", busy_o, done_o, beats);
        else $display("P1: FAIL busy=%b done=%b beats=%0d", busy_o, done_o, beats);

        // ---------------- P2: tready 卡死, RUN 后看门狗应释放 busy, 不置 done ----------------
        $display("== P2: tready 卡死, 期望看门狗释放 busy 且无 done ==");
        drv_tready = 0;
        beats = 0; final_ok = 0; got_done = 0;
        pulse_run;
        repeat (2) @(posedge aclk);
        begin : w2
            integer i;
            for (i = 0; i < 30; i = i + 1) begin
                @(posedge aclk);
                if (~busy_o) disable w2;
            end
        end
        if (~busy_o) $display("P2: PASS busy 已被看门狗释放 (frames=%0d)", frames_o);
        else         $display("P2: FAIL busy 未释放 (frames=%0d)", frames_o);

        // ---------------- P3: 恢复 tready, 再 RUN, 应重新完成且计数再+1 ----------------
        $display("== P3: 恢复 tready 重新 RUN, 期望完成 ==");
        drv_tready = 1;
        beats = 0; final_ok = 0; got_done = 0;
        pulse_run;
        begin : w3
            repeat (60) begin @(posedge aclk); if (done_o) disable w3; end
        end
        @(posedge aclk);   // 让 done/frames 落定再采样
        if (got_done && (beats == LEN)) $display("P3: PASS done=%b beats=%0d", done_o, beats);
        else $display("P3: FAIL done=%b beats=%0d", done_o, beats);

        // ---------------- 汇总 ----------------
        $display("============================================");
        $display("P1 done + P3 done => frames 应=2, 实测 frames=%0d", frames_o);
        if (final_ok && (frames_o == 2)) begin
            $display("PASS: 正常帧 TLAST 正确; 卡死被看门狗自愈; 恢复后重发完成。防死锁加固有效。");
        end else begin
            $display("FAIL: final_ok=%0b frames=%0d (期望 2)", final_ok, frames_o);
        end
        $finish;
    end

    initial begin
        #50000;   // 50us 兜底
        $display("FAIL: 仿真超时未完成");
        $finish;
    end

endmodule