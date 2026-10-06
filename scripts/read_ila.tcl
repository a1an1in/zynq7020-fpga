# ============================================================
# read_ila.tcl
# 主机侧从板上读 System ILA(ila_dbg) 波形 -> CSV，用于分析
# s2mm 完成中断为何不产生（关键在 M_AXI_S2MM 写 DDR 握手）。
#
# 前提（必须是也已跑一次 explore，确保 on_hostJTAG 可达）：
#   - 板卡已通过 USB/JTAG 接到本主机（Hardware Manager 方式），
#     且已加载包含 ILA 的 bit（python scripts/fpga.py load 后重启）。
#   - 使用与 build 相同的 Vivado 2021.1。
#
# 用法（ins主机 PowerShell，从 repo 根）：
#   vivado -mode batch -nolog -nojournal -source scripts/read_ila.tcl
# 输出: build/ila_dump/s2mm_m_axi.{csv,tdc,txt}
# 注意：CSV 里是 16 进制 signed、时序数；读 CSV 时要按字节序/解析。
# ============================================================
set dumpdir [file join "build" "ila_dump"]
file mkdir $dumpdir

open_hw_manager
connect_hw_server
catch { open_hw_target } openres
puts "OPEN_HW_TARGET: $openres"

set devs [get_hw_devices -quiet]
if {[llength $devs] == 0} {
    puts "NO_HW_DEVICE (check JTAG/board power)"
    disconnect_hw_server
    close_hw_manager
    exit 1
}
current_hw_device [lindex $devs 0]
puts "DEVICE: [current_hw_device]"
refresh_hw_device -update_hw_probes false [current_hw_device]

set ila [current_hw_ila -quiet]
if {$ila eq ""} {
    puts "NO_ILA (bit may lack debug core; verify with fpga read 0x4 / /proc/interrupts)"
    disconnect_hw_server
    close_hw_manager
    exit 1
}
puts "ILA: $ila"

# 可选触发：抓 M_AXI_S2MM 写发起。若 datamover 从不写，awvalid 恒低。
# 这里先做整窗 capture（默认）。把所需信息先落盘：
write_hw_ila_data -force -quiet \
    -csv_file [file join $dumpdir "s2mm_m_axi.csv"] \
    -tdc_file  [file join $dumpdir "s2mm_m_axi.tdc"] \
    -ovl_file  [file join $dumpdir "s2mm_m_axi.txt"] \
    $ila
puts "DUMP_DONE: [file join $dumpdir]"
disconnect_hw_server
close_hw_manager
exit 0