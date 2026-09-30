# aurora — Zynq-7020 单窗口寄存器组工程

## 一句话
PS 通过**单一 AXI4-Lite 从机**（单从机 · 地址分块 · 单次 mmap）访问 FPGA 外设寄存器。
本版先落地 **LED**；全表一次 mmap 为将来 UIO/驱动做铺垫。

## 方案要点（已确认的"单窗口"）
- 一个 AXI-Lite 从机窗口固定占 PS `0x43C1_0000`（64KB，可扩到 1GiB）。
- 窗口内按功能块分址：`SYSTEM`(0x00) / `LED`(0x10) / `ADC`(0x20, 预留)。
- PS `M_AXI_GP0` → BD 内 `axi_interconnect` → 引出外部 AXI4-Lite 主接口 `M00_AXI`，
  顶层 `aurora_top.v` 把它接到自研寄存器组 `aurora_regbank`。
- **寄存器偏移单一真源** `tools/aurora_regs.json` → 生成两份文件（永不漂移）：
  - `src/aurora_addr_def.vh`（FPGA `localparam`）
  - `include/aurora_regs.h`（ARM 宏，含 `AURORA_BASE` 与各块偏移）
- **加外设** = 加一个外设 RTL 模块 + 在 JSON 里加几个寄存器 + 重跑生成器 + 在
  `aurora_regbank` 的读写 `case` 补几行。—— PS/驱动几乎不用改。

## 目录结构
```
projects/aurora/
├─ tools/aurora_regs.json      # 寄存器映射单一真源（改这里！）
├─ tools/gen_regs.py           # 生成 .vh / .h（含 --check）
├─ src/aurora_addr_def.vh      # 生成：FPGA 偏移 localparam
├─ src/aurora_top.v            # 顶层：PS wrapper + 寄存器组 + LED 外设
├─ src/aurora_regbank.v        # 通用 AXI4-Lite 寄存器组从机
├─ src/aurora_led.v            # LED 外设模块
├─ bd/system.tcl               # BD 脚本(PS + 互联 -> 外部 M00_AXI)，重建 system_wrapper
├─ constraints/                # aurora_pin.xdc + config.xdc（LED 脚/时钟/复位/位流）
├─ tb/tb_aurora_regbank.v      # 寄存器组功能自检（iverilog）
├─ include/aurora_regs.h       # 生成：ARM 侧宏
└─ top.txt                     # aurora_top
```

## 构建（Windows，批处理，无需 GUI）
在 `zynq7020-fpga` 根目录：
```
vivado -mode batch -source scripts/create_project.tcl -tclargs --top aurora
```
产出 `build/aurora_prj/`，位流 `build/aurora_prj/aurora_prj.runs/impl_1/aurora.bit`，
XSA `build/aurora.xsa`（含 bit，供 ARM/Vitis）。

## RTL 功能自检（可选，本机即可）
```
python3 tools/gen_regs.py                            # 从 JSON 重新生成 .vh/.h
iverilog -g2012 -o /tmp/aurora_tb.vvp -I src \
    src/aurora_regbank.v src/aurora_led.v tb/tb_aurora_regbank.v
vvp /tmp/aurora_tb.vvp
```

## 寄存器表（窗内字节偏址，绝对地址 = 0x43C10000 + 偏址）
| 块   | 寄存器        | 偏址 | 属性 | 说明                                   |
|------|--------------|------|------|----------------------------------------|
|system| SCRATCH      | 0x00 | RW   | 通用读写测试寄存器                     |
|system| VERSION      | 0x04 | RO   | = 1                                   |
|system| CTRL         | 0x08 | RW   | bit0 软件复位脉冲(写1自动清)          |
|led   | VALUE        | 0x10 | RW   | LED 控制值 [3:0]（默认全灭 0x0，见 rst）|
|led   | CTRL         | 0x14 | RW   | bit0 使能 (0 全灭 / 1 按 VALUE 点亮)  |
|led   | STATUS       | 0x18 | RO   | [4]使能 [3:0]实际 LED 输出            |
|adc   | CTRL/STATUS/DATA| 0x20/… | RW/RO | 预留, 读回 0（本版不实现）             |

### 快速点亮四个 LED（ARM 侧）
```c
#define AURORA_BASE 0x43C10000u
*(volatile uint32_t*)(AURORA_BASE + AURORA_LED_VALUE) = 0x0A; // LED1+LED3
*(volatile uint32_t*)(AURORA_BASE + AURORA_LED_CTRL ) = 0x1;  // 使能
```
正式驱动见 ARM 工程（先字符设备驱动，后 UIO 单次 mmap 全表）。

## 与 run_led 的差异
- 去掉 `xadc_wiz` 与 `ila` 探针（ADC 预留，不实现）。
- 寄存器由 PS 经 AXI 控制，不再直连流水灯 RTL；LED 引脚/E16/F16/H18/H17 不变。

## 备注 / 可能踩的坑
- BD 外部 AXI 接口若 IPI 要求给 `M00_AXI_aclk/M00_AXI_aresetn` 连网，请在
  `bd/system.tcl` 里把这两个 pin 连到 `FCLK_CLK0` / `rst_ps7_0_100M/peripheral_aresetn`
  网表（对应 `connect_bd_net`）。
- 地址编辑器里若没自动出现 `0x43C10000`，用 UI 的 Address Editor 对 `M00_AXI` 指定
  基址 `0x43C10000`、范围 `0x10000`（脚本里已写 `assign_bd_address`）。
- 软件复位(`SYS_CTRL[0]`)为**自动清除**脉冲，读回通常为 0，属设计如此。