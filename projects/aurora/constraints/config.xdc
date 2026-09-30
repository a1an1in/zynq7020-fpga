# ============================================================
# config.xdc —— 通用 FPGA 配置属性（与管脚无关，方便跨工程移植）
# 来源：米联客 F6-7020 soc 工程 uisrc/04_pin/fpga_pin.xdc
# 作用：
#   CFGBVS VCCO           配置参考电压取自 VCCO
#   CONFIG_VOLTAGE 3.3   配置电压 3.3 V（与 PS bank0 配置要求对齐）
# 这两个属性使 SD 启动/运行时全片重配（fpga_manager）的配置链路更稳。
# COMPRESS 位流压缩已放在 run_led_pin.xdc；如需统一可移到这里。
# ============================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]