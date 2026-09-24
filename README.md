# Zynq7020-FPGA

Zynq-7020 FPGA/PL（硬件侧）工程仓库。
作为父仓库 `zynq` 的 submodule 使用。

本仓库采用 **「脚本化 + 源码入库」+ 多工程分目录** 的方式管理 Vivado 工程，
避免把 Vivado 生成的大量中间文件提交到 Git。

> 📌 **跨平台设计文件规范见 [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)**：
> 规定了哪些文件入库、哪些是中间产物、Block Design 与换行的跨平台约定，
> 保证同一仓库在 Windows 和 Linux/WSL2 下使用一致。

---

## 整体结构

```
zynq7020-fpga/
├── README.md                 # 本文件
├── .gitignore                # 忽略 Vivado 中间生成物（.runs/.cache/.hw 等）
├── scripts/                  # 顶层公共脚本
│   ├── fpga.py               # 跨平台统一入口（build/sim/program/clean）
│   ├── create_project.tcl    # 建工程+综合+实现+出bit+XSA（跨平台）
│   ├── program_fpga.tcl      # 命令行烧板（跨平台）
│   └── simulate.tcl          # 命令行仿真（跨平台）
├── common/                   # 跨工程共享资源
│   ├── rtl/                  # 公共 RTL 模块
│   ├── ip/                   # 公共 IP核
│   ├── constraints/          # 公共约束 xdc
│   └── sdk/                  # 预留：导出的 SDK 硬件文件
└── projects/                 # 【多工程目录】每个 Vivado 工程一个子目录
    └── proj1_template/       # 示例模板
        ├── src/              # 工程专用 RTL
        ├── ip/               # 工程专用 IP
        ├── constraints/      # 工程专用约束
        └── README.md
```

## 新增一个 Vivado 工程

1. 复制模板目录：`cp -r projects/proj1_template projects/<工程名>`
2. 把源码放入 `<工程名>/src`、`ip`、`constraints`，补写 README。
3. 用命令行构建（见下方「用法」），`--top <工程名>` 指定该工程。

> 原则：**只提交源码与脚本，不提交生成物（.xpr/.runs/.cache/.bit 等）**，
> 这样可以安全地在一个仓库里管理多个工程，多人协作也不产生冲突。

---

## 安装 Vivado（Windows 或 Linux/WSL2 二选一或并存）

Vivado 的 Windows 版和 Linux 版相互独立。需要哪台机器编译，就在哪台装对应版本：

- **Windows 本机**：去官网下载 **Windows 版**，图形化安装，装完把 `vivado` 加进 PATH。
- **Linux / WSL2**：装 **Linux 版**（无显示服务器也可无人值守安装）。

Linux/WSL2 安装步骤（Ubuntu）：

```bash
# 1. 下载 Linux 版安装包（官网 AMD/Xilinx 账号，WebPACK 版 license 免费）
#    Vivado-*.tar.gz（约 20~100GB）

# 2. 解压并安装
tar -xzf Vivado-<版本>.tar.gz
cd Vivado-<版本> && sudo ./xsetup

# 3.（可选）授权文件放到 ~/.Xilinx/Xilinx.lic

# 4. 把 vivado 加入 PATH（写进 ~/.bashrc 一劳永逸）
echo 'export PATH=/opt/Xilinx/Vivado/<版本>/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# 5. 验证
vivado -version
```

> 无图形显示的 Linux 服务器也可：`./xsetup -b Install -e <版本>.xinstall` 无人值守安装，
> 编译/仿真/烧板全程命令行，无需界面。
> 建议工程源码放在 **Linux 侧文件系统**（如 `~/workspace/...`），避免放 `/mnt/c` 下拖慢 I/O。

## 用法（跨平台：Windows 与 Linux/WSL2 通用）

> 前提：已安装对应平台的 Vivado（Windows 用 Windows 版；Linux/WSL2 用 Linux 版）。
> 统一入口脚本 `scripts/fpga.py` 会自动定位 vivado（依次查找 PATH、常见安装目录、环境变量 `VIVADO`），
> 无需手动指定路径。若你的环境命令是 `python3`，请把下面的 `python` 换成 `python3`。

### 子命令一览

| 子命令 | 作用 | 必备参数 | 示例 | 产物 / 说明 |
|--------|------|----------|------|-------------|
| `build` | **编译**：建工程 → 综合 → 实现 → 生成 bit → 导出 XSA | `--top <工程名>` | `python scripts/fpga.py build --top run_led` | `build/<工程名>_prj/<工程名>.xpr`、`build/<工程名>_prj/<工程名>.runs/impl_1/<工程名>.bit`；**含 PS/BD 才导出** `build/<工程名>.xsa`，纯 PL 会提示跳过 |
| `sim` | **命令行仿真**（需先 build，并在 `projects/<工程>/tb/` 放好 testbench） | `--top <工程名>` | `python scripts/fpga.py sim --top run_led` | 终端打印仿真结果，批处理结束自动退出 |
| `program` | **烧板**：把 bit 写入 FPGA（需先 build，且 JTAG/开发板已连接） | `--top <工程名>` | `python scripts/fpga.py program --top run_led` | 烧写 `build/<工程名>_prj/.../impl_1/<工程名>.bit` |
| `clean` | **清理** `build/` 全部编译产物 | 无 | `python scripts/fpga.py clean` | 删除 `build/`；无此目录则提示无需清理 |

> - **不设 `--top`** 时，默认使用 `projects/proj1_template`（示例工程）。
> - `build` 前置条件：`projects/<工程名>/` 存在，源码在 `src/`、约束在 `constraints/`、
>   IP 在 `ip/`（可选：`bd/`、`top.txt`）。新建工程见上文「新增一个 Vivado 工程」。
> - 内部实际调用：`vivado -mode batch -nolog -nojournal -source scripts/create_project.tcl -tclargs [--top <工程名>]`
>   （`sim`/`program` 对应对应的 `.tcl`）。

### 常用组合示例

```bash
# 首次需要：建工程+编译+出 bit
python scripts/fpga.py build --top run_led

# 改完源码只重编译
python scripts/fpga.py build --top run_led

# 仿真验证（先 build）
python scripts/fpga.py sim   --top run_led

# 接板烧写（先 build）
python scripts/fpga.py program --top run_led

# 全部洗掉重来
python scripts/fpga.py clean && python scripts/fpga.py build --top run_led
```

### 平台注意

- **Windows + WSL 目录**（仓库位于 `\\wsl.localhost\...`，UNC 路径）：入口脚本会自动
  `pushd` 映射盘符后再调 Vivado（cmd 不允许把 UNC 当工作目录、Vivado 的 run 流程也需要
  盘符），因此**无需手动 `net use` / 手动盘符**。
- **Linux / WSL2**：装 Linux 版 Vivado 并加入 PATH 后，直接 `python3 scripts/fpga.py ...`。

产物位置：
- 工程文件：`build/<工程名>_prj/`（`<工程名>.xpr`）
- bit 流：`build/<工程名>_prj/<工程名>.runs/impl_1/<工程名>.bit`
- XSA（给 ARM/软件侧）：`build/<工程名>.xsa`（含 Zynq PS 的工程才有）

> 「完全脱离界面」的边界：
> - **纯 RTL + XDC 约束 + `.xci` IP**：100% 命令行，不需任何窗口。
> - **Block Design**（图形化搭 IP 连线）这类图形化设计产物，需先在 GUI 里搭好并
>   `File -> Export -> Export Block Design to Tcl` 导出为 tcl（连同 `.bd` 入库）；
>   此后**重建、编译、出 bit/XSA 仍可命令行**。此步在装有 GUI 的机器做一次即可。
> - 仅收波形/可视化调试需要开窗口，日常编译、仿真、烧板全命令行。

## 大文件(big file)建议
- bit / bin / hdf 等较大二进制产品，建议使用 **Git LFS** 或在发布分支单独分发，
  默认已通过 `.gitignore` 忽略。
