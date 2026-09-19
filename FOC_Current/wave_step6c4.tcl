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
foreach name {cap_ia cap_ib cap_ic cap_theta cap_we cap_id_ref cap_iq_ref cap_vdc saved_alpha saved_beta saved_id saved_iq saved_sin saved_cos saved_ud saved_uq saved_v_alpha saved_v_beta svpwm_sector error_stage} {
  add_wave -radix dec /mc_foc_current_core_tb/dut/$name
}
foreach name {dbg_xd_old dbg_xq_old dbg_du_d_old dbg_du_q_old dbg_sat_old dbg_xd_next dbg_xq_next dbg_du_d_next dbg_du_q_next} {
  add_wave -radix dec /mc_foc_current_core_tb/dut/pi_core/$name
}
