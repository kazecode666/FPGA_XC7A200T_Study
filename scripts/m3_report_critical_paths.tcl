# Read-only post-synthesis diagnostics; no synthesis, placement or constraints changed.
if {[llength $argv] < 2 || [llength $argv] > 3} {error "usage: checkpoint new_output_dir ?feedback?"}
set checkpoint [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {[file exists $out]} {error "preserve existing diagnostics"}
file mkdir $out
open_checkpoint $checkpoint
proc csv {s} {return "\"[string map {\" \"\"} $s]\""}
set h [open [file join $out paths.csv] w]
puts $h "group,rank,startpoint,endpoint,slack_ns,logic_ns,net_ns,levels"
set groups {}
if {[llength $argv] == 2} {
set groups [list worst [get_timing_paths -delay_type max -max_paths 100 -nworst 1]]
foreach {label pattern} {limiter *u_dq_voltage_limiter* inverse_park *u_InversePark* sector_xyz *u_SVPWMG* pi_d *u_Id* pi_q *u_Iq*} {
    set cells [get_cells -hier -quiet -filter "NAME =~ $pattern && IS_SEQUENTIAL == 1"]
    if {[llength $cells]} {lappend groups $label [get_timing_paths -delay_type max -from $cells -max_paths 20 -nworst 1]}
}
}
set feedback [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && (NAME =~ *u_Id*x_d_z* || NAME =~ *u_Iq*x_q_z* || NAME =~ *u_dq_voltage_limiter*Unit_Delay*)}]
if {[llength $argv] == 3 && [lindex $argv 2] eq "aw"} {
    set feedback [get_cells -hier -quiet -filter {IS_SEQUENTIAL == 1 && NAME =~ *u_dq_voltage_limiter*Unit_Delay*}]
}
if {[llength $feedback]} {
    set sinks [get_pins -of_objects $feedback -filter {REF_PIN_NAME == D}]
    lappend groups feedback [get_timing_paths -delay_type max -to $sinks -max_paths 20 -nworst 1]
}
foreach {label paths} $groups {
    set rank 0
    foreach p $paths {
        incr rank
        set detail [report_timing -of_objects $p -return_string -input_pins -nets]
        set logic unresolved; set net unresolved; set levels unresolved
        regexp {Data Path Delay:\s+[0-9.]+ns\s+\(logic\s+([0-9.]+)ns.*route\s+([0-9.]+)ns} $detail ignored logic net
        regexp {Logic Levels:\s+([0-9]+)} $detail ignored levels
        puts $h [join [list $label $rank [csv [get_property STARTPOINT_PIN $p]] [csv [get_property ENDPOINT_PIN $p]] [get_property SLACK $p] $logic $net $levels] ,]
    }
    if {[llength $paths]} {report_timing -of_objects $paths -path_type full_clock_expanded -input_pins -nets -file [file join $out ${label}_setup.rpt]}
}
close $h
report_timing -delay_type min -max_paths 20 -file [file join $out hold.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
set h [open [file join $out dsp_registers.csv] w]
puts $h "cell,AREG,BREG,MREG,PREG"
foreach c [get_cells -hier -filter {REF_NAME == DSP48E1}] {
    puts $h [join [list [csv $c] [get_property AREG $c] [get_property BREG $c] [get_property MREG $c] [get_property PREG $c]] ,]
}
close $h
puts "M3_PATH_DIAGNOSTICS_COMPLETE $out"
exit
