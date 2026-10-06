set dumpdir "C:/tmp/ila_dump"
file mkdir $dumpdir
open_hw_manager
connect_hw_server
if {[catch {current_hw_target [lindex [get_hw_targets -quiet] 0]} e]} {puts "tgterr $e"}
catch {open_hw_target}
set pl ""
foreach d [get_hw_devices -quiet] { if {[string match -nocase "*xc7z*" $d]} {set pl $d; break} }
if {$pl eq ""} {set pl [lindex [get_hw_devices -quiet] 0]}
puts "PL: $pl"
current_hw_device $pl
set_property PROBES.FILE C:/tmp/ila_probe.ltx [current_hw_device]
refresh_hw_device [current_hw_device]
set ilas [get_hw_ilas -quiet]
puts "ILAS: $ilas"
foreach ic $ilas {
  set base [lindex [split $ic "/"] end]
  # 不触发全窗 capture; run_hw_ila 后循环等待 STATUS.CORE_STATUS 指示完成再写
  run_hw_ila -quiet [get_hw_ilas $ic]
  set got 0
  for {set n 0} {$n<40} {incr n} {
     set st [get_property -quiet STATUS.CORE_STATUS [get_hw_ilas $ic]]
     if {[string match -nocase "*COMPLETE*" $st] || [string match -nocase "*TRIGGERED*" $st] } {set got 1; break}
     catch {exec cmd /c "ping -n 2 127.0.0.1 > NUL"}
  }
  puts "$base CORE_STATUS=[get_property -quiet STATUS.CORE_STATUS [get_hw_ilas $ic]] after-run got=$got"
  catch {
    write_hw_ila_data -force -quiet \
        -csv_file [file join $dumpdir "${base}.csv"] \
        -tdc_file  [file join $dumpdir "${base}.tdc"] \
        -ovl_file  [file join $dumpdir "${base}.txt"] \
        [get_hw_ilas $ic]
    puts "  DUMPED $base csv=[file exists [file join $dumpdir "${base}.csv"]]"
  } werr
  if {[info exists werr] && $werr ne ""} {puts "  WRITE_ERR: $werr"}
}
close_hw_manager
puts "ALL_DONE"
quit
