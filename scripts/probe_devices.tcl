# probe_devices.tcl —— 列出 JTAG 上所有 hw_device；DAP 无 PROGRAM_STATE，用 try/catch 防中断
proc safe {expr fallback} {
    set r [catch {uplevel 1 $expr} res]
    if {$r} { return $fallback }
    return $res
}
open_hw_manager
connect_hw_server
catch { open_hw_target } openres
puts "OPEN_HW_TARGET: $openres"

proc list_devs {label} {
    set dl [get_hw_devices]
    puts "[string toupper $label]  COUNT=[llength $dl]"
    foreach d $dl {
        set name [safe {get_property NAME $d} "?"]
        set part [safe {get_property PART $d} "?"]
        set idc  [safe {get_property IDCODE $d} "?"]
        puts "    DEV $d | NAME=$name PART=$part IDCODE=$idc"
    }
}

list_devs "BEFORE_REFRESH"
current_hw_device [lindex [get_hw_devices] 0]
refresh_hw_device [current_hw_device]
list_devs "AFTER_REFRESH"

# 列出 ILA 核（此时应能到 PL 上的 debug hub）
set ilas [get_hw_ilas -quiet]
puts "N_ILA_CORES: [llength $ilas]"
foreach ic $ilas {
    puts "    ILA $ic"
    foreach p [get_hw_probe -of_objects $ic -quiet] {
        puts "        probe $p width=[safe {get_property width $p} ?]"
    }
}

disconnect_hw_server
close_hw_manager
puts "PROBE_DONE"
exit 0