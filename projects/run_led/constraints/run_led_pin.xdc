#系统时钟周期约束
create_clock -period 10.000 -name sysclk [get_ports sysclk_p]
#时钟管脚物理，物理约束为具体的芯片管脚号约束
set_property PACKAGE_PIN L18 [get_ports sysclk_p]
#电平属性为LVCMOS33,代表了3V3的IO BANK,电平约束不会改版实际的IO BANK电平，如果电平约束和实际的BANK电平不匹配，可能会导致工作异常
set_property IOSTANDARD LVCMOS33 [get_ports sysclk_p]

#复位管脚约束，这里绑定到按键输入
set_property PACKAGE_PIN U7 [get_ports rstn_i]
#复位输入的电平约束为1V8的IO BANK电平
set_property IOSTANDARD LVCMOS18 [get_ports rstn_i]

#绑定led输出管脚到FPGA IO上
set_property PACKAGE_PIN E16 [get_ports {led_o[3]}]
set_property PACKAGE_PIN F16 [get_ports {led_o[2]}]
set_property PACKAGE_PIN H18 [get_ports {led_o[1]}]
set_property PACKAGE_PIN H17 [get_ports {led_o[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_o[*]}]

#对bit大小进行压缩，可以节省程序存储空间
set_property BITSTREAM.GENERAL.COMPRESS true [current_design]