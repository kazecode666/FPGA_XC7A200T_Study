# Load after launch_simulation at 0 ns; all state below is simulation observation.
set e6_scope [current_scope]
if {![string match {*mc_foc_gate_top_tb*} $e6_scope]} {error {Launch the Step 6E simulation first}}
set group [add_wave_group {1 Raw logical PWM before deadtime}]
foreach name {clk pwm_u pwm_v pwm_w} {add_wave -into $group [list "$e6_scope/$name"]}
set group [add_wave_group {2 U leg gates and waiting}]
foreach name {gate_uh gate_ul} {add_wave -into $group [list "$e6_scope/$name"]}
foreach name {target target_valid remaining} {add_wave -into $group -radix dec [list "$e6_scope/dut/leg_u/$name"]}
set group [add_wave_group {3 V W complementary gates}]
foreach name {gate_vh gate_vl gate_wh gate_wl} {add_wave -into $group [list "$e6_scope/$name"]}
foreach leg {leg_v leg_w} {add_wave -into $group -radix dec [list "$e6_scope/dut/$leg/remaining"]}
set group [add_wave_group {4 Enable shutdown and reset}]
foreach name {reset_n run_enable trip_req trip_latched needs_reset fault_code} {add_wave -into $group [list "$e6_scope/$name"]}
foreach name {armed gate_enable control_run control_needs_reset} {add_wave -into $group [list "$e6_scope/dut/$name"]}
set group [add_wave_group {5 Sample to real active load}]
foreach name {sample_number sample_request sample_ready sample_valid} {add_wave -into $group -radix dec [list "$e6_scope/$name"]}
add_wave -into $group [list "$e6_scope/dut/pwm_command_loaded"]
foreach name {sample_accept cmp_handshake carrier_zero carrier_peak tbctr cmp_u_active cmp_v_active cmp_w_active} {add_wave -into $group -radix dec [list "$e6_scope/dut/control/$name"]}
set group [add_wave_group {6 Stable physical inputs and modulation}]
foreach name {ia_A ib_A ic_A theta_rad vdc_V foc_mod_u foc_mod_v foc_mod_w high_duty_u high_duty_v high_duty_w} {add_wave -into $group [list "$e6_scope/$name"]}
