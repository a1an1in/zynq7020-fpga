# ============================================================
# export_bit.tcl  （替代方案说明）
# 在当前已补全的 create_project.tcl 中，bit 流已经会在创建工程时
# 自动生成（综合->实现->write_bitstream）。
#
# 若你只需要单独跑综合/bit、而不想重复建工程，可改成：
#     open_project build/<工程名>_prj/<工程名>.xpr
#     launch_runs synth_1 -jobs 4
#     wait_on_run synth_1
#     launch_runs impl_1 -to_step write_bitstream -jobs 4
#     wait_on_run impl_1
#     set bit [
#         file join [get_property DIRECTORY [get_runs impl_1]] <工程名>.bit]
#     puts "bit: $bit"
#
# 一次性命令行并出bit的示例：
#   vivado -mode batch -nolog -nojournal \
#          -source scripts/create_project.tcl --top <工程名>
# ============================================================
puts "提示：请直接使用 scripts/create_project.tcl（命令行 `--top <工程名>`）即可创建工程并生成 bit 流。本文件为单独运行综合/bit 的参考。"