# 跨平台开发规范（Windows & Linux 通用）

本文件是 `zynq7020-fpga` 的**设计文件记录规范**。所有新提交的设计文件都必须
遵循这里的规定，以确保在 Windows 和 Linux/WSL2 下使用一致、切换零摩擦。

---

## 一句话目标

> **仓库里只存"跨平台、可重建"的设计文件；所有路径、脚本、换行、命名都在两个平台通用。**

---

## 1. 哪些文件入库（跨平台白名单）

| 类型 | 扩展名 | 存放位置 | 说明 |
|------|--------|----------|------|
| RTL 源码 | `.v` `.vhd` `.vh` `.sv` | `projects/<工程>/src/` 或 `common/rtl/` | 纯文本，两平台通用 |
| 管脚/时序约束 | `.xdc` | `projects/<工程>/constraints/` 或 `common/constraints/` | 纯文本 |
| IP 定义 | `.xci` | `projects/<工程>/ip/` 或 `common/ip/` | XML 文本 |
| 工程重建脚本 | `.tcl` | `scripts/` 或各工程目录 | 跨平台 Tcl |
| 跨平台入口 | `.py` | `scripts/` | 统一命令行 |
| Block Design 导出 | `.tcl` + `.bd` | 工程目录 | 见第 3 节 |
| 说明文档 | `.md` | `README.md`、`docs/` | 纯文本 |

## 2. 哪些文件**不**入库（中间产物）

`.xpr`、`.runs/`、`.cache/`、`.hw/`、`.ip_user_files/`、`.gen/`、`*.bit`、
`*.bin`、`*.xsa`、`*.hdf` 等全部由 `.gitignore` 与 `.gitattributes` 排除。
这些是**各平台各自生成的产物**，不共享、不入库。

> 两个平台各自 `build/`、各自的 bit/XSA——从同一份源码重建，结果行为一致，
> 但不互相复制二进制产物。

## 3. Block Design 的跨平台约定

Zynq 工程若含 **PS（Block Design）**，BD 没法用文本方式手工维护（含 IP 版本、地址映射、
图形布局），所以**以 Tcl 脚本作为唯一可信源**：

1. 在**任意一台有 GUI 的机器**（Windows，或带显示环境的 Linux）上搭好 BD。
2. 导出重建脚本（二选一）：
   - GUI：`File -> Export -> Export Block Design to Tcl`
   - Tcl：`write_bd_tcl -force -no_ip_version projects/<工程>/bd/<bd>.tcl`
     - `-no_ip_version`：把 IP 版本写成 `7.*` 这类宽松形式，换 Vivado 版本重建时不会因为
       "找不到 7.1 版 IP" 而失败（**推荐**）。
     - **不要**加 `-no_project_wrapper`：否则导出的脚本不会生成顶层 wrapper。
3. 入库清单：

   | 文件 / 目录 | 入库 | 说明 |
   |------|------|------|
   | `projects/<工程>/bd/<bd>.tcl` | **必须** | `scripts/create_project.tcl` 会按文件名顺序自动 `source`，负责重建 BD + wrapper |
   | `projects/<工程>/bd/<bd>.bd` | 建议 | 文本文件，便于 diff/回溯；**构建不依赖它**（由上面的 Tcl 重新生成） |
   | `projects/<工程>/ip/`（自定义 IP 的 `.xci` / `.coe` / IP 仓库） | **必须** | BD 脚本按 VLNV 引用它；`create_project.tcl` 会先把该目录加进 IP catalog |
   | `projects/<工程>/bd/<bd>.srcs/`（含 `hdl/<bd>_wrapper.v`） | 不入库 | 生成物，由 BD 脚本重新生成 |
   | `projects/<工程>/top.txt` | 可选 | 需要固定顶层时写一行模块名（BD 工程一般为 `<bd>_wrapper`） |

4. 之后在 Windows **或** Linux，重建/编译/出 bit/XSA 全走命令行，无需再开 GUI：

   ```bash
   python scripts/fpga.py build --top <工程名>   # 内部会自动 source projects/<工程名>/bd/*.tcl
   ```

> - 含 PS 的工程才会导出 XSA；纯 PL 工程脚本会提示"跳过 XSA 导出"，属正常。
> - 换 Vivado 大版本重建时，Vivado 可能提示 IP 需要升级（`upgrade_ip [get_ips]`），
>   按提示执行一次即可——这也正是"只存重建脚本、不存 .bd 产物"的另一个理由。

## 4. 换行与编码（重点）

- 由仓库根 `.gitattributes` 强制所有文本文件统一 **LF**。
- 无论你在 Windows（编辑端默认 CRLF 或编辑器随意）还是 Linux 修改、提交，
  git 都会以 LF 入库、按平台正确检出——**不会产生换行差异**。
- 若在用 IDE（VS Code/TCL 编辑器），建议打开"保存用 LF"以避免预览差异。

## 5. 路径与命令写法（代码内约定）

- 脚本内一律用 `/` 相对路径，经 `[file join]` 拼接（跨平台自动转 `\`）。
- **不要**在脚本/文档里写死 `C:\...` 或 `/home`、`/opt` 绝对路径。
- 调用 vivado 统一走 `python scripts/fpga.py ...`，由入口脚本按平台自动定位。

## 6. 日常操作（两平台命令一致）

```bash
# 编译（综合/实现/出bit/XSA）
python scripts/fpga.py build --top <工程名>
# 仿真
python scripts/fpga.py sim   --top <工程名>
# 烧板
python scripts/fpga.py program --top <工程名>
# 清理
python scripts/fpga.py clean
```

## 7. 切换平台清单（从 Windows → Linux 等）

首次在另一平台使用：
1. `git clone --recursive <父仓库URL>` 或用 `git pull` 同步。
2. 确保该平台已安装对应版本 Vivado（Linux 用 Linux 版）并加入 PATH 或设 `VIVADO` 环境变量。
3. 无需修改任何命令、配置、文件——框架会自动适配平台。