# ============================================================
# export_bit.tcl  (alternative note)
# In the current create_project.tcl, the bitstream is already generated when the
# project is created (synth -> impl -> write_bitstream).
#
# If you only need to run synth/bit without rebuilding the project, change to:
#     open_project build/<proj>_prj/<proj>.xpr
#     launch_runs synth_1 -jobs 4
#     wait_on_run synth_1
#     launch_runs impl_1 -to_step write_bitstream -jobs 4
#     wait_on_run impl_1
#     set bit [
#         file join [get_property DIRECTORY [get_runs impl_1]] <proj>.bit]
#     puts "bit: $bit"
#
# One-shot command-line build that produces the bit:
#   vivado -mode batch -nolog -nojournal \
#          -source scripts/create_project.tcl -tclargs --top <proj>
# ============================================================
puts "Hint: use scripts/create_project.tcl (command line `--top <proj>`) to create the project and generate the bitstream. This file is a reference for running synth/bit separately."