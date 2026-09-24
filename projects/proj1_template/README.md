# proj1_template（示例工程模板）

> 这是一个**占位模板工程**，用于示范多工程的组织方式。
> 实际使用时：在 `projects/` 下新建 `projects/<工程名>/`，复制本目录结构，
> 并把 `scripts/create_project.tcl` / `export_bit.tcl` 中 `top_name` 改为对应工程名。

## 目录说明

| 目录 | 用途 |
|------|------|
| `src/` | 本工程专用 RTL 源文件（.v / .vhd / .sv） |
| `ip/` | 本工程专用 Vivado IP（.xci） |
| `constraints/` | 本工程专用 XDC 约束（引脚、时序） |
| `tb/` | 本工程的 testbench（`scripts/simulate.tcl` 约定的目录，可选） |
| `bd/` | BD 重建脚本（GUI 导出或 `write_bd_tcl`，构建时自动 `source`；见 `docs/CONTRIBUTING.md` §3） |
| `top.txt` | 可选：显式指定顶层模块名（BD 工程一般是 `<bd>_wrapper`） |

> ⚠️ 生成的 Vivado 工程与中间产物**不在本目录**，而在**仓库根**的 `build/<工程名>_prj/`
> （由 `scripts/create_project.tcl` 重建，不入库；两平台各建各的）：
> - 工程文件：`build/<工程名>_prj/<工程名>.xpr`
> - bit 流：`build/<工程名>_prj/<工程名>.runs/impl_1/<工程名>.bit`

## README 建议写的内容
- 工程用途、功能框图
- 开发板型号、器件型号、管脚分配说明
- 用到的 IP 和关键外设
- 生成的 bit 流如何使用（下载方式、配合的 ARM 侧说明）