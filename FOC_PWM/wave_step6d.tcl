# Load after launch_simulation, at 0 ns. Keep physical units in TB only.
set d6_scope [current_scope]
if {![string match {*mc_foc_pwm_top_tb*} $d6_scope]} {error {Launch the Step 6D simulation first}}
set group [add_wave_group {1 Sample and captured inputs}]
foreach name {clk reset_n run_enable sample_number sample_request sample_ready sample_valid ia_A ib_A ic_A theta_rad vdc_V} {
    add_wave -into $group [list "$d6_scope/$name"]
}
foreach name {cap_ia cap_ib cap_ic cap_theta cap_we cap_id_ref cap_iq_ref cap_vdc cap_pi_reset cap_uq_zero} {
    add_wave -into $group -radix dec [list "$d6_scope/dut/foc/$name"]
}
set group [add_wave_group {2 FOC raw modulation d_foc}]
foreach name {foc_mod_u foc_mod_v foc_mod_w} {add_wave -into $group [list "$d6_scope/$name"]}
foreach name {foc_result_valid foc_command_valid foc_error_code foc_duty_u foc_duty_v foc_duty_w} {add_wave -into $group -radix dec [list "$d6_scope/dut/$name"]}
set group [add_wave_group {3 Upper-switch D_high and CMP}]
foreach name {high_duty_u high_duty_v high_duty_w} {add_wave -into $group [list "$d6_scope/$name"]}
foreach name {adapter_valid pwm_cmd_valid pwm_cmd_ready cmp_handshake cmp_u_cmd cmp_v_cmd cmp_w_cmd} {add_wave -into $group -radix dec [list "$d6_scope/dut/$name"]}
set group [add_wave_group {4 Shadow active and transaction}]
foreach name {transaction_pending sample_cycle_id active_cycle_id shadow_pending compare_load_event cmp_u_shadow cmp_v_shadow cmp_w_shadow cmp_u_active cmp_v_active cmp_w_active} {add_wave -into $group -radix dec [list "$d6_scope/dut/$name"]}
set group [add_wave_group {5 Shared carrier and logical PWM}]
foreach name {tbctr count_up carrier_zero carrier_peak} {add_wave -into $group -radix dec [list "$d6_scope/dut/$name"]}
foreach name {pwm_u pwm_v pwm_w needs_reset fault_code} {add_wave -into $group [list "$d6_scope/$name"]}
set group [add_wave_group {6 Active-command average voltage}]
foreach name {active_row active_vdc_V active_alpha_V active_beta_V reconstructed_alpha_V reconstructed_beta_V} {add_wave -into $group [list "$d6_scope/$name"]}
