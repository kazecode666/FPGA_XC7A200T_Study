# Learning view: one coherent transaction and its four module boundaries.
add_wave /mc_foc_current_core_tb/clk
add_wave /mc_foc_current_core_tb/reset_n
add_wave /mc_foc_current_core_tb/sample_valid
add_wave /mc_foc_current_core_tb/sample_ready
add_wave /mc_foc_current_core_tb/result_valid
add_wave /mc_foc_current_core_tb/command_valid
add_wave -radix dec /mc_foc_current_core_tb/duty_u
add_wave -radix dec /mc_foc_current_core_tb/duty_v
add_wave -radix dec /mc_foc_current_core_tb/duty_w
add_wave /mc_foc_current_core_tb/error_code
add_wave /mc_foc_current_core_tb/dut/age
add_wave /mc_foc_current_core_tb/dut/transform_valid
add_wave /mc_foc_current_core_tb/dut/pi_valid
add_wave /mc_foc_current_core_tb/dut/inv_valid
add_wave /mc_foc_current_core_tb/dut/svpwm_valid
