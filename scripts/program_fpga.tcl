# ============================================================
# program_fpga.tcl  （跨平台：Windows / Linux 通用）
# 命令行烧板：通过 Hardware Manager 把 bit 写入 FPGA (JTAG)。
# 前提：开发板已连接并上电，且驱动/USB 能被 Vivado 识别。
#
# 用法：
#   python scripts/fpga.py program --top <工程名>
#   # 或
#   vivado -mode batch -nolog -nojournal \
#          -source scripts/program_fpga.tcl --top <工程名>
# ============================================================

# ---------- 参数解析：--top <工程名> ----------
set project_name "proj1_template"
if {$argc > 0} {
    for {set i 0} {$i < $argc} {incr i} {
        if {[string equal [lindex $argv $i] "--top"]} {
            set project_name [lindex $argv [expr {$i + 1}]]
        }
    }
}

set bit_file [file join "build" "bin" "${project_name}.bit"]
if {![file exists $bit_file]} {
    # 兜底：去 impl_1 运行目录里找
    set cand [glob -nocomplain \
        [file join "build" "${project_name}_prj" "*.runs" "impl_1" "${project_name}.bit"]]
    if {[llength $cand] > 0} {
        set bit_file [lindex $cand 0]
    } else {
        error "找不到 bit 文件：${bit_file}"
    }
}

puts "准备烧写的 bit：${bit_file}"
puts "打开 Hardware Manager 并连接设备..."

open_hw_manager
connect_hw_server
set hw_target [get_hw_targets -regexp .*]
if {[llength $hw_target] == 0} {
    error "未发现硬件目标/jtag 设备，请检查开发板连接与驱动。"
}
open_hw_target $hw_target

# 选择第一个 fpga（Zynq 通常 device 0）
set hw_dev [lindex [get_hw_devices] 0]
current_hw_device $hw_dev
refresh_hw_device -update_hw_probes false $hw_dev

set_property PROGRAM.FILE $bit_file $hw_dev
program_hw_devices $hw_dev

puts "=================================================================="
puts "烧写完成：${bit_file}"
puts "=================================================================="
close_hw_target $hw_target
close_hw_manager