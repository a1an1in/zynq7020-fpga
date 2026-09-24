# ============================================================
# simulate.tcl  （跨平台：Windows / Linux 通用）
# 命令行行为仿真（Vivado 自带 xsim）。
# 前提：工程 src/ 或 tb/ 下有名为 <top>_tb 的 testbench（当前示例默认
# 找 projects/<工程名>/tb 下的 *.tb.v / *_tb.vhd）。
#
# 用法：
#   python scripts/fpga.py sim --top <工程名>
#   # 或
#   vivado -mode batch -nolog -nojournal \
#          -source scripts/simulate.tcl --top <工程名>
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

set proj_src  [file join "projects" $project_name]
set build_dir [file join "build" "${project_name}_prj"]

# 复用源码收集（跨平台递归）
proc collect_sources {dir pats} {
    set result [list]
    if {![file isdirectory $dir]} { return $result }
    foreach f [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $f]} {
            set result [concat $result [collect_sources $f $pats]]
        } else {
            foreach p $pats {
                if {[string match "*${p}" [file tail $f]]} {
                    lappend result $f
                    break
                }
            }
        }
    }
    return $result
}

# 若工程尚未 build，则建一个仿真工程（或提示先 build）
if {![file isdirectory $build_dir]} {
    error "请先运行 build，再执行仿真： python scripts/fpga.py build --top ${project_name}"
}
open_project $build_dir/${project_name}.xpr

# 加入 testbench（约定放在 projects/<工程>/tb/）
set tb_files [collect_sources [file join $proj_src "tb"] {.v .vhd .sv}]
if {[llength $tb_files] == 0} {
    puts "【提示】未在 ${proj_src}/tb 下找到 testbench，正在查找 *tb* 命名文件..."
    set tb_files [collect_sources [file join $proj_src "src"] {_tb.v _tb.vhd _tb.sv}]
}
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 $tb_files
    puts "加入 testbench：$tb_files"
} else {
    error "找不到 testbench。请在 projects/${project_name}/tb 下添加 <模块>_tb.v/.vhd。"
}

# 用第一个 testbench 模块作为仿真顶层运行
set tb_top [file rootname [file tail [lindex $tb_files 0]]]
set_property top ${tb_top} [get_filesets sim_1]

launch_simulation
run -all
# 自动结束 batch 仿真（不阻塞等待波形窗口）
quit_sim -quiet