try {

open_project hdlverifier_wizard_project/wizprj.xpr
set_property -name {xelab.debug_level} -value {off} -objects [get_filesets sim_1]
set_property -name {xelab.more_options} -value { --timescale 1ps/1ps --override_timeprecision } -objects [get_filesets sim_1]
set_property -name {xelab.dll} -value {1} -objects [get_filesets sim_1]
set_property -name {xelab.snapshot} -value {design} -objects [get_filesets sim_1]

launch_simulation

# The xsim.dir must be co-located with the model.
# - save off existing xsim.dir
if {[file exists xsim.dir] == 1} {
    set mtime [file mtime xsim.dir]
    set mtimestamp [clock format $mtime -format %Y%m%d_%H%M%S]
    set xsim_savefile "xsim.dir.$mtimestamp"
    file rename xsim.dir $xsim_savefile
}
# - copy up newly elaborated xsim.dir area from project to the current working directory.
set proj_xsim_dir {hdlverifier_wizard_project/wizprj.sim/sim_1/behav/xsim/xsim.dir}
set proj_mtime [file mtime "$proj_xsim_dir/design"]
file copy -force $proj_xsim_dir .
file mtime xsim.dir $proj_mtime

} on error { errMsg errDetails } {
    puts "CAUGHT ERROR: $errMsg, $errDetails"
    # Exit code 12 is arbitrary but distinct from the compilation error code (11)
    # in case we want to differentiate error handling in the future.
    exit 12
}

exit
