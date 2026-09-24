# ============================================================
# create_project.tcl
# Rebuild the Vivado project from source in one shot, running synth -> impl -> bitstream.
# Fully command-line; no GUI needed.
# ------------------------------------------------------------
# Usage (run from the zynq7020-fpga root):
#   // with the default top_name (single project):
#   vivado -mode batch -source scripts/create_project.tcl
#
#   // specify the project to build (recommended for many projects; --top takes the
#   // folder name under projects/):
#   vivado -mode batch -source scripts/create_project.tcl -tclargs --top another_proj
#
#   // or, inside the GUI, run interactively from the Tcl Console:
#   source scripts/create_project.tcl
# ============================================================

# ---------- parse args: --top <project> ----------
set project_name "proj1_template"      ;# default project
if {$argc > 0} {
    for {set i 0} {$i < $argc} {incr i} {
        if {[string equal [lindex $argv $i] "--top"]} {
            set project_name [lindex $argv [expr {$i + 1}]]
        }
    }
}

set fpga_part   "xc7z020clg484-2"      ;# Zynq-7020 / CLG484 (matches official MLK-F6-CZ06-7020); change for other boards

set proj_src     [file join "projects" $project_name]
set build_dir    [file join "build" "${project_name}_prj"]

# ---------- verify project directory exists ----------
if {![file isdirectory $proj_src]} {
    error "Project directory not found: ${proj_src}\nPlease make sure it exists under projects/."
}

# ---------- create project ----------
create_project ${project_name} $build_dir -part ${fpga_part} -force
set_property target_language VHDL   [current_project]
set_property default_lib   xil_defaultlib [current_project]

# ---------- auto-collect source files ----------
# Recurse with a proc instead of relying on glob "**" (not guaranteed to be supported
# on Tcl 8.5 / Vivado), keeping it cross-platform safe.
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
    puts "Added [llength $src_files] source file(s)."
} else {
    puts "Warning: no .v/.vhd/.vh/.sv source under ${proj_src}/src."
}

# ---------- auto-collect constraints ----------
set xdc_files [glob -nocomplain [file join $proj_src "constraints" "*xdc"]]
if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 $xdc_files
}

# ---------- auto-collect IP (.xci) ----------
set ip_files [glob -nocomplain [file join $proj_src "ip" "*.xci"]]
if {[llength $ip_files] > 0} {
    set_property ip_repo_paths [list [file normalize [file join $proj_src "ip"]]] [current_fileset]
    update_ip_catalog
    add_files $ip_files
}

# ---------- Block Design (optional; generic support for BD/PS projects) ----------
# Convention: put a BD export script (File -> Export -> Export Block Design to Tcl,
#       or write_bd_tcl -force -no_ip_version) under projects/<proj>/bd/.
#       It is sourced in file-name order at build time. The exported script rebuilds
#       the BD, creates the top wrapper, and sets the top to <bd>_wrapper (unless
#       exported with -no_project_wrapper).
set bd_scripts [lsort [glob -nocomplain [file join $proj_src "bd" "*.tcl"]]]
if {[llength $bd_scripts] > 0} {
    # BDs often reference custom IPs under ip/; add the project IP dir to the catalog first
    set ip_repo_dir [file normalize [file join $proj_src "ip"]]
    if {[file isdirectory $ip_repo_dir]} {
        set_property ip_repo_paths [list $ip_repo_dir] [current_fileset]
        update_ip_catalog
    }
    foreach bd_tcl $bd_scripts {
        puts "Sourcing Block Design script: ${bd_tcl}"
        source $bd_tcl
    }
} else {
    puts "No ${proj_src}/bd/*.tcl found; treating as a pure-RTL project."
}

# ---------- top module (optional: explicit, overrides auto-inference) ----------
# Convention: write the top module name into projects/<proj>/top.txt
#       (for BD projects this is usually <bd>_wrapper).
#       Without it, keep Vivado's auto-inference behavior.
set top_file [file join $proj_src "top.txt"]
if {[file exists $top_file]} {
    set fh [open $top_file r]
    set top_name [string trim [read $fh]]
    close $fh
    if {$top_name ne ""} {
        set_property top $top_name [current_fileset]
        puts "Top module (from top.txt): ${top_name}"
    }
}

puts "Project ${project_name} created: ${build_dir}"

# ---------- unattended: synthesis -> implementation -> bitstream ----------
puts "Starting synthesis (synth_1)..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis failed; check the src/ sources and constraints."
}

puts "Starting implementation and bitstream (impl_1)..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation / bitstream generation failed."
}

set bit_dir [get_property DIRECTORY [get_runs impl_1]]
puts "================================================================"
puts "Build OK! Bitstream at: ${bit_dir}/${project_name}.bit"
puts "Project files at: ${build_dir}/"
puts "================================================================"
# ---------- export XSA (hardware platform file for the ARM/software side; only when a BD/PS exists) ----------
# Note: do not rely on get_hw_defs from Hardware Manager (unavailable in batch mode and
#       reports "invalid command name"). Instead decide by "does a Block Design exist" --
#       the Zynq PS always lives in a BD, so a pure-PL project has none and skips it.
#       Very robust.
set out_dir [file join "build"]
file mkdir $out_dir
set xsa_file [file join $out_dir "${project_name}.xsa"]
set has_bd 0
catch {set has_bd [llength [get_bd_designs -quiet]]}
if {$has_bd > 0} {
    open_run impl_1
    write_hw_platform -fixed -include_bit -force $xsa_file
    puts "XSA exported: ${xsa_file} (includes bit; ready for ARM/software)"
} else {
    puts "No Block Design detected (no PS hardware platform); skipping XSA export."
    puts "(A pure-PL project needs no XSA; for ARM/Vitis, add a BD containing the Zynq PS.)"
}
puts "=================================================================="

# Note: if you only want to create the project without auto-running, comment out the
#       synthesis/implementation and XSA sections above.

# Note: to disable the auto bitstream (create only, no run), comment out this section.