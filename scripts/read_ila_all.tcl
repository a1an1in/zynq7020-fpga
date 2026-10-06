# ============================================================
# read_ila_all.tcl
# 从板上遍历读回所有 ILA 核 -> dump 到 build/ila_dump/。
# 适用于 aurora 新 bit：两个 debug 核
#   ila_dbg (System ILA, 2 AXI slots): SLOT0=M_AXI_S2MM, SLOT1=M_AXI_SG
#   ila_sig (Native, probe0=s2mm_introut, probe1=dma_intr_or/Res)
# 每个核单独 run(整窗无触发) -> write_hw_ila_data 导出 CSV/TDC/txt。
#
# 用法(Windows PowerShell, repo 根):
#   vivado -mode batch -nolog -nojournal -source scripts/read_ila_all.tcl
# 输出: build/ila_dump/<core>.csv (每个 slot/probe 一列)
# ============================================================
set dumpdir "W:/build/ila_dump"
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
# Zynq-7000 JTAG 有两个 device: arm_dap_0(DAP) 和 xc7z020_1(PL)。ILA 在 PL。
set pl_dev ""
foreach d $devs {
    set nm [string tolower [get_property NAME $d]]
    if {[string match "arm_dap*" $nm]} { continue }
    if {$pl_dev eq ""} { set pl_dev $d }
}
if {$pl_dev eq ""} { set pl_dev [lindex $devs 0] }
current_hw_device $pl_dev
puts "PL_DEVICE: $pl_dev"
# 关联 .ltx（probe 端口名校验），与当前板上 bit 匹配
set probes_file [lindex [glob -nocomplain \
    [file join "build" "aurora_prj" "*.runs" "impl_1" "aurora_top.ltx"]] 0]
set_property PROBES.FILE $probes_file $pl_dev
refresh_hw_device $pl_dev

# ---- 列出所有 ILA 核与各自探针 ----
set ilas [get_hw_ilas -quiet]
puts "N_ILA_CORES: [llength $ilas]"
foreach ic $ilas {
    set probes [get_hw_probe -of_objects $ic -quiet]
    puts "  ILA $ic : probes=[llength $probes]"
    foreach p $probes {
        puts "      probe $p : [get_property width $p]"
    }
}

if {[llength $ilas] == 0} {
    puts "NO_ILA (bit may lack debug core)"
    disconnect_hw_server
    close_hw_manager
    exit 1
}

# ---- 整窗 trace 两核并 dump（绝对路径，暴露真实错误）----
foreach ic $ilas {
    set base [lindex [split $ic "/"] end]
    puts "CAPTURE: $ic -> ${base}"
    run_hw_ila -quiet [get_hw_ilas $ic]
    puts "  run issued"
    exec cmd /c "ping -n 4 127.0.0.1 > NUL"
    set datah [get_hw_ila_data -of_objects [get_hw_ilas $ic]]
    write_hw_ila_data -force -quiet \
        -csv_file [file join $dumpdir "${base}.csv"] \
        $datah
    puts "  DUMPED ${dumpdir}/${base}.csv exists=[file exists [file join $dumpdir "${base}.csv"]]"
}

disconnect_hw_server
close_hw_manager
puts "DUMP_DONE: $dumpdir"
exit 0