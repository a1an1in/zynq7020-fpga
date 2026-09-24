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
| `build/` | 生成的工程与中间产物（不入库，见 .gitignore） |

## README 建议写的内容
- 工程用途、功能框图
- 开发板型号、器件型号、管脚分配说明
- 用到的 IP 和关键外设
- 生成的 bit 流如何使用（下载方式、配合的 ARM 侧说明）