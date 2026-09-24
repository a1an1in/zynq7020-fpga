# ============================================================
# simulate.tcl  (cross-platform: Windows / Linux)
# Command-line behavioral simulation (Vivado's xsim).
# Prereq: a testbench named <top>_tb under src/ or tb/. By default it looks
# for *.tb.v / *_tb.vhd under projects/<proj>/tb.
#
# Usage:
#   python scripts/fpga.py sim --top <proj>
#   # or
#   vivado -mode batch -nolog -nojournal \
#          -source scripts/simulate.tcl -tclargs --top <proj>
# ============================================================

# ---------- parse args: --top <project> ----------
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

# Reuse the source collector (cross-platform recursion)
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

# If the project isn't built yet, bail out (must build first)
if {![file isdirectory $build_dir]} {
    error "Please build first: python scripts/fpga.py build --top ${project_name}"
}
open_project $build_dir/${project_name}.xpr

# Add testbench (convention: under projects/<proj>/tb/)
set tb_files [collect_sources [file join $proj_src "tb"] {.v .vhd .sv}]
if {[llength $tb_files] == 0} {
    puts "[hint] No testbench under ${proj_src}/tb; searching for *tb* named files..."
    set tb_files [collect_sources [file join $proj_src "src"] {_tb.v _tb.vhd _tb.sv}]
}
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 $tb_files
    puts "Added testbench: $tb_files"
} else {
    error "No testbench found. Add <module>_tb.v/.vhd under projects/${project_name}/tb."
}

# Run with the first testbench module as the simulation top
set tb_top [file rootname [file tail [lindex $tb_files 0]]]
set_property top ${tb_top} [get_filesets sim_1]

# Clear any stale incremental xsim build so a repeated `sim` always links cleanly
# (otherwise xsim --incr can fail to link against leftover objects).
set sim_xsim_dir [file join $build_dir "${project_name}.sim" "sim_1" "behav" "xsim"]
file delete -force $sim_xsim_dir

launch_simulation
run -all
# End the batch simulation. If the testbench calls $finish the xsim session is
# already closed, so swallow any error from quit_sim (batch mode).
catch { quit_sim -quiet }