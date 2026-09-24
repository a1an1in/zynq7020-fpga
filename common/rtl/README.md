# common/rtl
存放跨多个工程共享的通用 RTL 模块（AXI 接口、时钟复位、FIFO、通用计数器等）。

约定：
- 文件命名 `模块名_功能.v`，例如 `axis_fifo.v`、`clk_gen.v`
- 工程专属代码不要放这里，放对应 `projects/<工程名>/src/`

（此目录为空，放置文件后再提交。）