# ============================================================
# create_project.tcl
# 从源码一键重建 Vivado 工程，并自动完成 综合->实现->生成bit 流。
# 全程命令行，不依赖图形界面。
# ------------------------------------------------------------
# 用法（在 zynq7020-fpga 根目录执行）：
#   // 用默认 top_name（单个工程）：
#   vivado -mode batch -source scripts/create_project.tcl
#
#   // 指定要构建的工程（多工程推荐，--top 传入 projects/ 下的目录名）：
#   vivado -mode batch -source scripts/create_project.tcl --top another_proj
#
#   // 也可以只在图形界面打开后，用 Tcl Console 交互执行：
#   source scripts/create_project.tcl
# ============================================================

# ---------- 参数解析：--top <工程名> ----------
set project_name "proj1_template"      ;# 默认工程
if {$argc > 0} {
    for {set i 0} {$i < $argc} {incr i} {
        if {[string equal [lindex $argv $i] "--top"]} {
            set project_name [lindex $argv [expr {$i + 1}]]
        }
    }
}

set fpga_part   "xc7z020clg400-1"      ;# Zynq-7020，按实际器件修改
set proj_src     [file join "projects" $project_name]
set build_dir    [file join "build" "${project_name}_prj"]

# ---------- 校验工程目录存在 ----------
if {![file isdirectory $proj_src]} {
    error "无法找到工程目录：${proj_src}\n请确认 projects/ 下存在该工程。"
}

# ---------- 创建工程 ----------
create_project ${project_name} $build_dir -part ${fpga_part} -force
set_property target_language VHDL   [current_project]
set_property default_lib   xil_defaultlib [current_project]

# ---------- 自动收集源文件 ----------
# 用递归 proc 遍历，避免 Tcl 8.5/Vivado 不保证支持的 glob "**"（跨平台安全）。
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
set src_files [collect_sources [file join $proj_src "src"] {.v .vhd .vh .sv}]
if {[llength $src_files] > 0} {
    add_files -norecurse $src_files
    puts "已加入源文件：[llength $src_files] 个"
} else {
    puts "警告：${proj_src}/src 下没有找到 .v/.vhd/.vh/.sv 源文件。"
}

# ---------- 自动收集约束 ----------
set xdc_files [glob -nocomplain [file join $proj_src "constraints" "*xdc"]]
if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 $xdc_files
}

# ---------- 自动收集 IP（xci） ----------
set ip_files [glob -nocomplain [file join $proj_src "ip" "*.xci"]]
if {[llength $ip_files] > 0} {
    set_property ip_repo_paths [list [file normalize [file join $proj_src "ip"]]] [current_fileset]
    update_ip_catalog
    add_files $ip_files
}

puts "工程 ${project_name} 创建完成：${build_dir}"

# ---------- 无人值守：综合 -> 实现 -> 生成 bit 流 ----------
puts "开始综合（synth_1）..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "综合失败，请检查 src/ 源码与约束。"
}

puts "开始实现并生成 bit 流（impl_1）..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "实现/出bit失败。"
}

set bit_dir [get_property DIRECTORY [get_runs impl_1]]
puts "================================================================"
puts "构建成功！bit 流位置：${bit_dir}/${project_name}.bit"
puts "工程文件位置：${build_dir}/"
puts "================================================================"
# ---------- 导出 XSA（硬件平台文件，供 ARM/软件侧使用）----------
set out_dir [file join "build"]
file mkdir $out_dir
set xsa_file [file join $out_dir "${project_name}.xsa"]
if {[llength [get_hw_defs -quiet]] > 0} {
    open_run impl_1
    write_hw_platform -fixed -include_bit -force $xsa_file
    puts "XSA 已导出: ${xsa_file}（含 bit，可提供给 ARM/软件侧）"
} else {
    puts "未检测到硬件平台（无 PS/Block Design），跳过 XSA 导出。"
    puts "（纯 PL 逻辑工程不需要 XSA；若需给 ARM/Vitis，请确保包含 Zynq PS 的 BD。）"
}
puts "=================================================================="

# 说明：若只想建工程不自动跑，注释掉上面综合/实现与 XSA 段。

# 说明：若想关闭自动 bit（只建工程不开跑），注释掉本段即可。