# Standalone non-project OOC IP flow; no pin assignment, bitstream or hardware.
if {$argc != 3} { error "Usage: generated_source_directory fresh_report_directory actual_part" }
set src [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set part [lindex $argv 2]
if {[file exists $out]} { error "Use a fresh report directory: $out" }
file mkdir $out
set_param general.maxThreads 8
if {[llength [get_parts -quiet $part]] != 1} { error "Actual audited part unavailable: $part" }
puts "STUDY_L1_TARGET part=$part clock=50MHz non-project OOC"
set sources [glob -directory $src *.sv]
read_verilog -sv $sources
read_xdc [file join [file dirname [info script]] study_l1_50mhz.xdc]
synth_design -top HDLCore -part $part -mode out_of_context
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
if {[llength $clocks] != 1 || [get_property PERIOD $clocks] != 20.0} { error "Expected one 50 MHz clock" }
set coverage_file [open [file join $out check_timing.rpt] r]
set check_report [read $coverage_file]
close $coverage_file
foreach category {no_clock unconstrained_internal_endpoints no_input_delay no_output_delay loops latch_loops} {
    if {![regexp "checking $category \\(0\\)" $check_report]} { error "Timing coverage gate failed: $category" }
}
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set dsp [llength [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]]
set bram18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
set bram36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
set ff [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]
set f [open [file join $out metrics.json] w]
puts $f "{\"part\":\"$part\",\"clock_mhz\":50,\"mode\":\"out_of_context\",\"WNS_ns\":$wns,\"WHS_ns\":$whs,\"FF\":$ff,\"DSP48\":$dsp,\"RAMB18\":$bram18,\"RAMB36\":$bram36}"
close $f
puts "STUDY_L1_ROUTE WNS=$wns WHS=$whs FF=$ff DSP48=$dsp BRAM18=$bram18 BRAM36=$bram36"
if {$wns < 0 || $whs < 0} { error "50 MHz timing gate failed; analyze baseline before changing configuration." }
puts "STUDY_L1_IMPLEMENTATION_PASS"
