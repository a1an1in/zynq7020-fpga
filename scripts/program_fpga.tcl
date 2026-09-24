# ============================================================
# program_fpga.tcl  (cross-platform: Windows / Linux)
# Command-line programming: write the bit to the FPGA (JTAG) via Hardware Manager.
# Prereq: the board is connected and powered, and the USB/driver is recognized
#         by Vivado.
#
# Usage:
#   python scripts/fpga.py program --top <proj>
#   # or
#   vivado -mode batch -nolog -nojournal \
#          -source scripts/program_fpga.tcl -tclargs --top <proj>
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

set bit_file [file join "build" "bin" "${project_name}.bit"]
if {![file exists $bit_file]} {
    # fallback: look in the impl_1 run directory
    set cand [glob -nocomplain \
        [file join "build" "${project_name}_prj" "*.runs" "impl_1" "${project_name}.bit"]]
    if {[llength $cand] > 0} {
        set bit_file [lindex $cand 0]
    } else {
        error "Bit file not found: ${bit_file}"
    }
}

puts "Programming bit: ${bit_file}"
puts "Opening Hardware Manager and connecting to the device..."

open_hw_manager
connect_hw_server
set hw_target [get_hw_targets -regexp .*]
if {[llength $hw_target] == 0} {
    error "No JTAG/hardware target found. Check the board connection and driver."
}
open_hw_target $hw_target

# Select the first FPGA (usually device 0 for Zynq)
set hw_dev [lindex [get_hw_devices] 0]
current_hw_device $hw_dev
refresh_hw_device -update_hw_probes false $hw_dev

set_property PROGRAM.FILE $bit_file $hw_dev
program_hw_devices $hw_dev

puts "=================================================================="
puts "Programming complete: ${bit_file}"
puts "=================================================================="
close_hw_target $hw_target
close_hw_manager