# run_led（流水灯 · 移植自米联客 MLK-F6-CZ06-7020 例程 CH05）

> 纯 PL 入门工程：4 个 LED 按固定间隔循环移位（`led_o` 低位向高位轮转）。

## 一览

| 项目 | 值 |
|------|-----|
| 开发板 | MLK-F6-CZ06-7020（米联客 F6 系列 7020 板） |
| 器件 / 封装 | `xc7z020clg484-2`（Zynq-7020，CLG484，-2 速度等级） |
| 顶层模块 | `run_led`（与工程目录同名 —— 框架约定：产物为 `build/run_led_prj/…/run_led.bit`） |
| IP | 无（不使用任何 `.xci`） |
| Block Design | 无（纯 PL，因此不导出 XSA） |
| 系统时钟 | `sysclk_p` = 100 MHz（XDC：`create_clock -period 10.000`） |
| 移植日期 | 2026-09-24 |

## 目录内容与来源

| 路径 | 内容 | 原始例程内的位置 |
|------|------|------------------|
| `src/run_led.v` | 顶层：分频计数 + 4bit 循环移位 | `CH05_run_led/fpga_prj/uisrc/01_rtl/run_led.v` |
| `constraints/run_led_pin.xdc` | 时钟 / 复位 / LED 管脚与电平约束 | `CH05_run_led/fpga_prj/uisrc/04_pin/fpga_pin.xdc` |
| `tb/tb_run_led.v` | testbench（`T_INR_CNT_SET=1000` 缩短仿真时间） | `CH05_run_led/fpga_prj/uisrc/02_sim/tb_run_led.v` |
| `ip/` | 空（本工程不需要 IP） | — |

例程包：米联客 F6-7020 官方资料 `3-1_ex_soc_fpga/3-1-01_ex_fpga_base__F6-020`
→ `3-1-01_ex_fpga_base_CZ06_F6_7020/CH05_run_led`（Vivado v2021.1 工程，本机 Vivado 版本一致）。

移植时按 `docs/CONTRIBUTING.md` 做了两项规范化：

1. 源码注释原为 **GBK** 编码 → 转为 **UTF-8**（Linux / VS Code 下不再乱码）；
2. 行尾统一 **LF**（XDC 原为 CRLF）。

**未移植**（生成物或与本站无关，按规范不入库）：`fpga_prj/*.xpr`、`.runs/`、`.cache/`、`.hw/`、
`.ip_user_files/`、`.sim/`、`*.bit`、`*.jou`、`*.log`；`uisrc/03_ip`、`05_boot`、`06_doc`（均为空目录）；
以及 `fpga_prj.srcs/sources_1/run_led.v` —— 那是**原工程未引用的 MZ7035FA 板残留版本**
（差分时钟 + `IBUFGDS` + 2 位 LED），与本站管脚和 TB 都不匹配，已弃用。

## 管脚分配

| 端口 | 管脚 | 电平 | 说明 |
|------|------|------|------|
| `sysclk_p` | L18 | LVCMOS33 | 系统时钟 100 MHz |
| `rstn_i` | U7 | LVCMOS18 | 复位按键（按下为低电平） |
| `led_o[0]` | H17 | LVCMOS33 | LED |
| `led_o[1]` | H18 | LVCMOS33 | LED |
| `led_o[2]` | F16 | LVCMOS33 | LED |
| `led_o[3]` | E16 | LVCMOS33 | LED |

> ⚠️ 换板必须同时改两处：`scripts/create_project.tcl` 的 `fpga_part` 与本目录 XDC 的管脚号，
> 否则综合/实现会报管脚不存在（封装不同，球位号完全不同）。

## 使用

```bash
python scripts/fpga.py build   --top run_led    # 建工程 + 综合 + 实现 + 出 bit
python scripts/fpga.py sim     --top run_led    # 命令行仿真（需先 build）
python scripts/fpga.py program --top run_led    # 烧板（先连好 JTAG）
```

产物：`build/run_led_prj/run_led.xpr`、`build/run_led_prj/run_led.runs/impl_1/run_led.bit`。
本工程无 PS/BD，脚本会提示"未检测到硬件平台，跳过 XSA 导出"，属正常。

## 备注

- **顶层参数实际不生效（与厂家原始行为保持一致，未修改）**：
  `T_INR_CNT_SET = 32'd999_999_999` 大于计数器位宽 `reg [24:0]`（上限 33,554,431），
  因此 `t_cnt == T_INR_CNT_SET` 永远不成立，计数器自然溢出回 0；
  LED 实际约每 `2^25 / 100 MHz ≈ 0.34 s` 移位一次。
  若要让参数真正生效：把 `t_cnt` 改为 `reg [31:0]`（或改小参数值）。
- 仿真时序：TB 每 `#20` 翻转时钟（周期 40 ns），100 ns 后释放复位；`T_INR_CNT_SET` 用 1000。
- 复位/按键电平：`rstn_i` 为低有效，且约束在 1V8 的 IO BANK（LVCMOS18）。

## 构建环境注意（本机实测）

| 事实 | 说明 |
|------|------|
| 器件已对齐 | `scripts/create_project.tcl` 的 `fpga_part` 已改为 **`xc7z020clg484-2`**（与本例程工程一致） |
| Vivado 只有 Windows 版 | 本机装在 `C:\Xilinx\Vivado\2021.1\bin\vivado.bat`（**未加入 PATH**）；`scripts/fpga.py` 的版本候选列表已含 `2021.1` 会自动定位，也可用环境变量 `VIVADO` 显式指定 |
| Windows 侧已装 Python 3.11 | 仓库若位于 WSL 的 `\\wsl.localhost\…`（UNC 路径），`fpga.py` 会自动 `pushd` 映射盘符再调用 Vivado——cmd.exe 不允许把 UNC 当作当前目录、且 Vivado 的 run 流程也需要盘符工作目录，故统一由脚本处理，**用户无需手动映射/无需 `net use`** |

因此直接使用统一入口即可（脚本内部自动处理 Windows 的盘符映射）：

```powershell
python scripts\fpga.py build --top run_led      # Windows：自动 pushd 映射盘符
python scripts\fpga.py sim     --top run_led
python scripts\fpga.py program --top run_led
```

在 **WSL/Linux** 侧则需先安装 Linux 版 Vivado，再 `python3 scripts/fpga.py build --top run_led`（本机 WSL 已有 Python 3.12）。

