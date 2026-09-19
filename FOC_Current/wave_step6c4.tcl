# XSim includes a generic override in the elaborated top scope name.
set c4_scope [current_scope]
if {![string match {*mc_foc_current_core_tb*} $c4_scope]} {error {Launch the C4 behavioral simulation before loading this wave script}}
# Learning view: one coherent transaction and its four module boundaries.
add_wave [list "$c4_scope/clk"]
add_wave [list "$c4_scope/reset_n"]
add_wave [list "$c4_scope/sample_valid"]
add_wave [list "$c4_scope/sample_ready"]
add_wave [list "$c4_scope/result_valid"]
add_wave [list "$c4_scope/command_valid"]
add_wave -radix dec [list "$c4_scope/duty_u"]
add_wave -radix dec [list "$c4_scope/duty_v"]
add_wave -radix dec [list "$c4_scope/duty_w"]
add_wave [list "$c4_scope/error_code"]
add_wave [list "$c4_scope/dut/age"]
add_wave [list "$c4_scope/dut/transform_valid"]
add_wave [list "$c4_scope/dut/pi_valid"]
add_wave [list "$c4_scope/dut/inv_valid"]
add_wave [list "$c4_scope/dut/svpwm_valid"]
foreach name {cap_ia cap_ib cap_ic cap_theta cap_we cap_id_ref cap_iq_ref cap_vdc saved_alpha saved_beta saved_id saved_iq saved_sin saved_cos saved_ud saved_uq saved_v_alpha saved_v_beta svpwm_sector error_stage} {
  add_wave -radix dec [list "$c4_scope/dut/$name"]
}
foreach name {dbg_xd_old dbg_xq_old dbg_du_d_old dbg_du_q_old dbg_sat_old dbg_xd_next dbg_xq_next dbg_du_d_next dbg_du_q_next} {
  add_wave -radix dec [list "$c4_scope/dut/pi_core/$name"]
}
