# Same top/adapter, 14 diagnostics, register boundaries, constraints and flow.
# No bitstream or hardware commands.
if {$argc != 4} { error "Usage: variant coder_directory fresh_report_directory actual_part" }
set variant [lindex $argv 0]
set src [file normalize [lindex $argv 1]]
set out [file normalize [lindex $argv 2]]
set part [lindex $argv 3]
if {$variant ni {hand baseline csd}} { error "Unknown variant" }
if {[file exists $out]} { error "Fresh report directory required" }
file mkdir $out
set study [file dirname [file dirname [info script]]]
set_param general.maxThreads 8
if {$part ne "xc7a200tfbg484-2" || [llength [get_parts -quiet $part]] != 1} { error "Actual part gate" }
if {$variant eq "hand"} {
    read_verilog -sv [list [file join $study handwritten speed_pi_sv.sv] [file join $study handwritten speed_pi_compare.sv]]
    set synth_options [list -verilog_define HAND_SV]
} else {
    read_verilog -sv [list [file join $src PI.sv] [file join $src HDLCore.sv] [file join $study handwritten speed_pi_compare.sv]]
    set synth_options {}
}
read_xdc [file join [file dirname [info script]] study_l1_50mhz.xdc]
synth_design -top speed_pi_compare -part $part -mode out_of_context {*}$synth_options
report_utilization -file [file join $out synth_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out synth_timing.rpt]
write_checkpoint [file join $out post_synth.dcp]
opt_design
place_design
route_design
write_checkpoint [file join $out post_route.dcp]
report_utilization -file [file join $out route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out route_timing.rpt]
report_timing -delay_type max -max_paths 5 -input_pins -file [file join $out critical_paths.rpt]
report_route_status -file [file join $out route_status.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_drc -file [file join $out drc.rpt]
set clocks [get_clocks]
if {[llength $clocks] != 1 || [get_property PERIOD $clocks] != 20.0} { error "Clock gate" }
set f [open [file join $out check_timing.rpt] r]; set coverage [read $f]; close $f
foreach category {no_clock unconstrained_internal_endpoints no_input_delay no_output_delay loops latch_loops} {
    if {![regexp "checking $category \\(0\\)" $coverage]} { error "Coverage gate: $category" }
}
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set ff [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]
set dsp [llength [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]]
set b18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
set b36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
set f [open [file join $out metrics.json] w]
puts $f "{\"variant\":\"$variant\",\"part\":\"$part\",\"clock_mhz\":50,\"mode\":\"out_of_context\",\"WNS_ns\":$wns,\"WHS_ns\":$whs,\"FF\":$ff,\"DSP48\":$dsp,\"RAMB18\":$b18,\"RAMB36\":$b36}"
close $f
# Negative slack is a measured outcome, retained for an honest comparison.
puts "STUDY_L1_C_IMPLEMENTATION_COMPLETE variant=$variant WNS=$wns WHS=$whs FF=$ff DSP=$dsp"
