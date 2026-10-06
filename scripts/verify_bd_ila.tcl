# ============================================================
# verify_bd_ila.tcl
# 只验证 ILA 段加入后 system.tcl 能否正确重建 BD 并通过 validate，
# 不跑综合/实现。临时工程写 C:\TmpILAVerify（Windows 本地盘，
# 避免 UNC/WSL 写入路径问题），结束后即可删除。
# 用法(vivado batch)：
#   vivado -mode batch -nolog -nojournal -source scripts/verify_bd_ila.tcl
# 成功时打印 VERIFY_BD_ILA_PASS；任何 ILA/pin/validate 错误会直接报出。
# ============================================================
set tdir C:/TmpILAVerify
file mkdir $tdir
catch {create_project ila_verify $tdir -part xc7z020clg484-2 -force} msg
puts "create_project(ila_verify): $msg"

# system.tcl 是 Windows(WSL)UNC 路径；Vivado 用正斜杠 UNC 引用
set bd_tcl "//wsl.localhost/Ubuntu-24.04/home/alan/workspace/zynq/zynq7020-fpga/projects/aurora/bd/system.tcl"
set rc [catch { source $bd_tcl } errmsg]
if {$rc} {
    puts "ERROR: source system.tcl FAILED:"
    puts "$errmsg"
    exit 1
}
# ---- 诊断：ILA 实际配置与 probe/intf pin，判定 set_property 是否生效 ----
if {[llength [get_bd_cells -quiet ila_dbg]] > 0} {
    set ilac [get_bd_cells ila_dbg]
    puts "ILA  vlnv = [get_property VLNV $ilac]"
    foreach p {C_NUM_OF_PROBES C_PROBE0_WIDTH C_PROBE1_WIDTH C_PROBE2_WIDTH \
               C_PROBE17_WIDTH C_DATA_DEPTH} {
        puts "ILA  CONFIG.$p = [get_property CONFIG.$p $ilac]"
    }
    puts "ILA  data pins = [lsort [get_bd_pins -of_objects $ilac]]"
    puts "ILA  intf pins = [lsort [get_bd_intf_pins -of_objects $ilac]]"
} else {
    puts "ILA  ila_dbg NOT FOUND after source"
}
# ---- 诊断: ila_sig (ila:6.2 Native probe) 离散完成/送 PS 信号是否挂上 ----
if {[llength [get_bd_cells -quiet ila_sig]] > 0} {
    set ilac2 [get_bd_cells ila_sig]
    puts "ILA_SIG  vlnv = [get_property VLNV $ilac2]"
    puts "ILA_SIG  C_NUM_OF_PROBES = [get_property CONFIG.C_NUM_OF_PROBES $ilac2]"
    puts "ILA_SIG  probe pins = [lsort [get_bd_pins -quiet -filter {DIR == I} -of_objects $ilac2]]"
    foreach pb {probe0 probe1} {
        set pn [get_bd_nets -quiet -of_objects [get_bd_pins $ilac2/$pb]]
        puts "ILA_SIG  $pb  net = $pn"
    }
} else {
    puts "ILA_SIG  ila_sig NOT FOUND after source"
}
puts "VERIFY_BD_ILA_PASS"
exit 0