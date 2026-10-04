# catch errors using try/on error
try {

# ======== Create Project ======== 
create_project -force wizprj hdlverifier_wizard_project


# ======== Add source files to project ========
set SRC1 {D:/Project/FPGA_XC7A200T/learning/study_l1_speed_pi_hdl_compare/generated_hdl/baseline}
set SRC2 {D:/Project/FPGA_XC7A200T/learning/study_l1_speed_pi_hdl_compare/handwritten}
set SRC3 {D:/Project/FPGA_XC7A200T/motor_control_ip/foc/rtl}
set SRC4 {D:/Project/FPGA_XC7A200T/motor_control_ip/integration/rtl}
set SRC5 {D:/Project/FPGA_XC7A200T/motor_control_ip/pwm/rtl}
add_file "$SRC3/mc_fxp_pkg.sv"
add_file "$SRC3/mc_clarke.sv"
add_file "$SRC3/mc_sincos_lut.sv"
add_file "$SRC3/mc_park.sv"
add_file "$SRC3/mc_inv_park.sv"
add_file "$SRC3/mc_current_transform.sv"
add_file "$SRC3/mc_pi_fxp_pkg.sv"
add_file "$SRC3/mc_isqrt_u80.sv"
add_file "$SRC3/mc_udiv_u72_u41.sv"
add_file "$SRC3/mc_pi_dq_eval.sv"
add_file "$SRC3/mc_dq_limiter.sv"
add_file "$SRC3/mc_pi_dq_core.sv"
add_file "$SRC3/mc_svpwm_pkg.sv"
add_file "$SRC3/mc_svpwm_sector_xyz.sv"
add_file "$SRC3/mc_sector_svpwm.sv"
add_file "$SRC3/mc_foc_current_core.sv"
add_file "$SRC5/motor_pwm_core.sv"
add_file "$SRC4/mc_duty_to_cmp.sv"
add_file "$SRC4/mc_foc_pwm_top.sv"
add_file "$SRC4/mc_foc_cosim_top.sv"
add_file "$SRC1/PI.sv"
add_file "$SRC1/HDLCore.sv"
add_file "$SRC2/speed_pi_sv.sv"
add_file "$SRC2/study_l1_system_cosim_top.sv"


# ======== Elaboration options ========
set_property -name {xelab.snapshot} -value {mwcosim_query} -objects [get_filesets sim_1]

# ======== Compile and Elaborate ========
# Compile, elaborate, and start a sim image in order to auto determine
# the top module and its interface information.
set_property source_mgmt_mode All [current_project]
set_property SOURCE_SET sources_1 [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation

# ======== Gather Design Info ========
# DO NOT EDIT.  Needed for gathering top-level design information.
set TOP_MODULE [get_property top [get_fileset sim_1]]
set INPORT_NAMES [get_objects -filter { type == in_port }]
set OUTPORT_NAMES [get_objects -filter { type == out_port }]
report_scope [current_scope] > hdlverifier_tcl_query_info.txt
foreach {port} [concat $INPORT_NAMES $OUTPORT_NAMES] { report_object $port >> hdlverifier_tcl_query_info.txt}

} on error { errMsg errDetails } {
    puts "CAUGHT ERROR: $errMsg, $errDetails"
    exit 11
}

exit
