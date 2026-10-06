# aurora — Zynq-7020 单窗口寄存器组工程

## 一句话
PS 通过**单一 AXI4-Lite 从机**（一个窗口 · 地址分块 · 一次 mmap）访问 FPGA 外设寄存器。
本版先落地 **LED**；全表一次 mmap 为将来 UIO/驱动做铺垫。

## 架构（定稿：生成从器 + 手写 bank/top/tb）
- **单 AXI4-Lite 从窗口**固定占 PS `0x4000_0000`（64KB）。窗内按块分址：
  `SYSTEM`(0x00) / `LED`(0x10) / `ADC`(0x20·预留) / `DMA`(0x30·假数据源)。
- PS `M_AXI_GP0` → BD 内 `axi_interconnect` → 外部主接口 `M00_AXI` → 顶层 `aurora_top.v`
  接到自研寄存器组 `aurora_regbank`。
- **寄存器映射单一真源** `tools/aurora_regs.json` → 生成器 `tools/gen_regs.py` 一次产出
  **三份**（永不漂移）：
  - `src/aurora_addr_def.vh`（`localparam`/`define` 偏址）
  - `include/aurora_regs.h`（ARM 宏，含 `AURORA_BASE`）
  - `src/regs/aurora_<块>_regs.v`（每块一个**自命中 P-BUS 从器**；`reserved` 块生成占位从器）
- **分工**：
  - `aurora_regbank.v`（手写固定）＝纯 AXI4-Lite 从 + P-BUS 读写广播，不认识任何寄存器/地址窗口。
  - `src/regs/*_regs.v`（生成）＝按地址窗口自命中、持有本块寄存器、经 `o_*/i_*` 对接外设。
  - `aurora_top.v`（手写）＝例化 bank + 各从器，把读出 OR 归并成单根 `p_rdata` 回给 bank。
- **加外设/寄存器**＝改 JSON → 重跑生成器 → 加外设 RTL 接 `o_*/i_*`。bank/top/驱动几乎不用改。
  `python3 tools/gen_regs.py --check` 可校验生成结果与真源幂等一致。

## 读回归并与时序（设计要点）
- 各从器 `o_rdata = addr_hit ? rd_val : 0`：**按地址恒组合译码**，非命中恒回 0。
  `o_rvalid = p_rvalid & addr_hit` 仅用于隔离互检。
- top 用 `pb_rdata = sys_o_rdata | led_o_rdata | adc_o_rdata` 归并：因窗口**两两互斥**
  （`[0x00,0x10)/[0x10,0x20)/[0x20,0x30)`），OR 严格等价“3 选 1”，无并发叠加。
- bank 读为**确定性三段式**：握手拍“接受”并登记地址 → 下一拍把登记的 `p_raddr` 广播、
  从器组合译码稳定 → 再采样进 `ar_data` 驱动 `RVALID`。规避“握手拍采样活组合”的 delta 竞争。
- tb 新增 **隔离监控断言**：读握手拍上命中集必须单热或全 0，绝不“多人命中”——
  对“窗口互斥”这一 OR 前提做实时守护，任何人改坏地址会立刻让仿真 FAIL。

## 目录结构
```
projects/aurora/
├─ tools/aurora_regs.json      # 寄存器映射单一真源（改这里！）
├─ tools/gen_regs.py           # 生成 .vh / .h / src/regs/*.v（含 --check）
├─ src/aurora_addr_def.vh      # 生成：地址 define/localparam
├─ src/aurora_top.v            # 顶层：bank + 从器 + OR 归并 + LED 外设
├─ src/aurora_regbank.v        # 手写：纯 AXI4-Lite 从 + P-BUS 读写广播
├─ src/aurora_led.v            # LED 外设模块
├─ src/aurora_dma_src.v        # 假数据源（S2MM AXI-Stream 帧发生器，PL->PS）
├─ src/aurora_dma_sink.v       # MM2S 接收器（回环/丢弃，回环预留）
├─ src/regs/                   # 生成：每块一个自命中从器
│   ├─ aurora_system_regs.v    #   SYSTEM（SCRATCH/VERSION/CTRL）
│   ├─ aurora_led_regs.v       #   LED（VALUE/CTRL/STATUS）
│   ├─ aurora_adc_regs.v       #   ADC（预留占位，读恒 0）
│   └─ aurora_dma_regs.v       #   DMA（CTRL/LEN/STATUS 假数据源控制）
├─ bd/system.tcl               # BD 脚本（PS+互联+AXI DMA+HP0 → 外部 M00_AXI + 流口）
├─ constraints/                # aurora_pin.xdc + config.xdc
├─ tb/tb_aurora_regbank.v      # 功能自检 + 隔离监控（iverilog，13 项全过）
├─ include/aurora_regs.h       # 生成：ARM 侧宏
└─ top.txt                     # 顶层模块名 aurora_top（create_project.tcl 读取）
```

## 构建（Windows，批处理，无需 GUI）
在 `zynq7020-fpga` 根目录：
```
python scripts/fpga.py build --top aurora
```
（等价 `vivado -mode batch -source scripts/create_project.tcl -tclargs --top aurora`）
产出 `build/aurora_prj/`，位流 `build/aurora_prj/aurora_prj.runs/impl_1/aurora.bit`，
XSA `build/aurora.xsa`（含 bit，供 ARM/Vitis）。`top.txt` 内容 `aurora_top` 会被
`create_project.tcl` 读取并设为顶层。

## RTL 功能自检（可选，本机即可）
```
python3 tools/gen_regs.py            # 先从 JSON 重新生成 .vh/.h/src/regs
iverilog -g2012 -o tb.vvp -I src \
    src/aurora_regbank.v src/aurora_led.v \
    src/regs/aurora_system_regs.v src/regs/aurora_led_regs.v \
    src/regs/aurora_adc_regs.v tb/tb_aurora_regbank.v
vvp tb.vvp                            # 期望：RESULT: 13 passed, 0 failed
```
`tb.vvp` 为仿真生成物，已被 `.gitignore`（`*.vvp`）忽略，不入库。

## 寄存器表（窗内字节偏址，绝对地址 = 0x40000000 + 偏址）
| 块   | 寄存器 | 偏址 | 属性 | 说明 |
|------|--------|------|------|------|
|system| SCRATCH | 0x00 | RW | 通用读写测试寄存器 |
|system| VERSION | 0x04 | RO | 点分版本 M.m.p (当前 1.0.1, 编码 0x01000100; 每次 build 修订自动+1, 满255进位次) |
|system| CTRL    | 0x08 | RW | bit0 软件复位脉冲（写 1 自动清） |
|led   | VALUE   | 0x10 | RW | LED 控制值 [3:0]（默认全灭 0x0） |
|led   | CTRL    | 0x14 | RW | bit0 使能（0 全灭 / 1 按 VALUE 点亮） |
|led   | STATUS  | 0x18 | RO | [4]使能 [3:0]实际 LED 输出 |
|adc   | CTRL/STATUS/DATA | 0x20/… | RW/RO | 预留，读回 0（本版不实现） |
|dma   | CTRL   | 0x30 | RW | bit0=RUN 启动假数据源发一帧（写 1 自动清） |
|dma   | LEN    | 0x34 | RW | 每帧字数（默认 1024），与 PS 侧 DMA BTT=len*4 一致 |
|dma   | STATUS | 0x38 | RO | [0]busy [1]帧完成 [15:8]已发帧数 |

## DMA 通路（PL→PS 假数据 S2MM，MM2S 回环预留）
- **控制**：dma 寄存器块在单窗 `0x40000000+0x30`（经既有 M00/regbank 通路，一次 mmap 即可写
  `DMA_CTRL[0]=1` 启动、读 `DMA_STATUS`）。
- **数据**：`aurora_dma_src` 发确定性帧 `{16'h5AA5, word_index}` → BD `S_AXIS_S2MM` →
  `axi_dma_0`(SG 模式, 64bit) → `hp0_axi_periph` → PS `S_AXI_HP0`(0x0–0x40000000 DDR)。
- **AXI DMA 引擎**（`0x50000000`，SG/MM2S/S2MM）由 PS 经 GP0 的 BD 内部 M01 控制
  （dmaengine 驱动写描述符环）；假数据源仅负责"喂流"，两者异步配合。
- **验证点位**：PS 读回 DDR 相应区，应得到连续 `0x5AA5xxxx` 序列；`DMA_STATUS` 的 busy/帧计数
  反映源侧进度。**MM2S** 现已连出（`M_AXIS_MM2S`），顶层用 `aurora_dma_sink` 丢弃接收，为回环铺路。

## 快速点亮四个 LED（ARM 侧）
```c
#define AURORA_BASE 0x40000000u
*(volatile uint32_t*)(AURORA_BASE + AURORA_LED_VALUE) = 0x0A; // LED1+LED3
*(volatile uint32_t*)(AURORA_BASE + AURORA_LED_CTRL)  = 0x1;  // 使能
```
正式驱动见 ARM 工程（先字符设备驱动，后 UIO 单次 mmap 全表）。

## 与 run_led 的差异
- 去掉 `xadc_wiz` 与 `ila` 探针（ADC 预留，不实现）。
- 寄存器由 PS 经 AXI 控制，不再直连流水灯 RTL；LED 引脚 E16/F16/H18/H17 不变。

## 备注 / 可能踩的坑
- BD 外部 AXI 接口若 IPI 要求 `M00_AXI_aclk/M00_AXI_aresetn` 连网，请在 `bd/system.tcl`
  里把两个 pin 连到 `FCLK_CLK0` / `rst_ps7_0_100M/peripheral_aresetn`。
- 地址编辑器未自动出现 `0x40000000` 时，用 Address Editor 对 `M00_AXI` 从段指定基址
  `0x40000000`、范围 `0x10000`。脚本内 `assign_bd_address` 的**从段目标对象必须写成
  `[get_bd_addr_segs M00_AXI/Reg]`**——写成裸 `M00_AXI` 会因外部主端口无从段而直接
  在 `source bd/system.tcl` 时抛 `[BD 5-432 / Common 17-39] assign_bd_address` 失败。
- 顶层例化 `system_wrapper` 时端口名区分大小写：PS 的 `FCLK_CLK0` / `FCLK_RESET0_N`
  （大写）以小写 `fclk_clk0/fclk_reset0_n` 连接会报 `[Synth 8-448]`。
- 软件复位（`SYS_CTRL[0]`）为自动清除脉冲，读回通常为 0，属设计如此。
- 换行统一 LF：仓库 `.gitattributes` 强制 `eol=lf`，新增源码请用 LF 保存（VS Code
  右下角选 LF）。
