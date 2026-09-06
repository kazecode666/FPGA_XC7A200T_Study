# Step 3 synthesis baseline for the existing PWM Vivado project.
# Run with:
#   vivado -mode batch -source scripts/step3_synthesis.tcl

set script_dir   [file dirname [file normalize [info script]]]
set repo_root    [file normalize [file join $script_dir ..]]
set project_file [file join $repo_root PWM_Controller PWM_Controller.xpr]
set report_dir   [file join $repo_root docs reports]
set util_report  [file join $report_dir step3_synth_utilization.rpt]
set msg_report   [file join $report_dir step3_synth_messages.txt]

file mkdir $report_dir
open_project $project_file

set design_top [get_property TOP [get_filesets sources_1]]
set design_part [get_property PART [current_project]]
if {$design_top ne "pwm_controller"} {
    error "Unexpected synthesis top: $design_top"
}
if {$design_part ne "xc7a200tfbg484-2"} {
    error "Unexpected target part: $design_part"
}

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status   [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
puts "STEP3_SYNTH_STATUS=$synth_status"
puts "STEP3_SYNTH_PROGRESS=$synth_progress"

if {$synth_progress ne "100%" || ![string match -nocase "*complete*" $synth_status]} {
    error "synth_1 did not complete successfully: $synth_status ($synth_progress)"
}

open_run synth_1
report_utilization -file $util_report

# Append an inventory of actual primitives in the synthesized netlist.
set primitive_counts [dict create]
foreach cell [get_cells -hierarchical -filter {IS_PRIMITIVE == 1}] {
    set ref_name [get_property REF_NAME $cell]
    dict incr primitive_counts $ref_name
}

set report_handle [open $util_report a]
puts $report_handle ""
puts $report_handle "Step 3 synthesized primitive inventory"
puts $report_handle "--------------------------------------"
foreach ref_name [lsort [dict keys $primitive_counts]] {
    puts $report_handle [format "%-16s %d" $ref_name [dict get $primitive_counts $ref_name]]
}

puts $report_handle ""
puts $report_handle "State-related synthesized cells"
puts $report_handle "-------------------------------"
foreach pattern {period_set_reg compare_value_reg time_cnt pwm_out_reg next_time_cnt next_pwm_out} {
    set matches [get_cells -hierarchical -quiet -filter "NAME =~ *${pattern}*"]
    puts $report_handle [format "%-22s %d" $pattern [llength $matches]]
    foreach match $matches {
        puts $report_handle [format "  %-58s %s" $match [get_property REF_NAME $match]]
    }
}
close $report_handle

# Keep only the synthesis message summary and actionable message lines.
set run_dir [get_property DIRECTORY [get_runs synth_1]]
set run_log [file join $run_dir runme.log]
set error_lines {}
set critical_warning_lines {}
set warning_lines {}
if {[file exists $run_log]} {
    set log_handle [open $run_log r]
    while {[gets $log_handle line] >= 0} {
        if {[regexp {^ERROR:} $line]} {
            lappend error_lines $line
        } elseif {[regexp {^CRITICAL WARNING:} $line]} {
            lappend critical_warning_lines $line
        } elseif {[regexp {^WARNING:} $line]} {
            lappend warning_lines $line
        }
    }
    close $log_handle
}

set message_handle [open $msg_report w]
puts $message_handle "Vivado synthesis message summary"
puts $message_handle "Synthesis status: $synth_status"
puts $message_handle "Synthesis progress: $synth_progress"
puts $message_handle "ERROR: [llength $error_lines]"
puts $message_handle "CRITICAL WARNING: [llength $critical_warning_lines]"
puts $message_handle "WARNING: [llength $warning_lines]"
foreach line [concat $error_lines $critical_warning_lines $warning_lines] {
    puts $message_handle $line
}
close $message_handle

puts "STEP3_UTILIZATION_REPORT=$util_report"
puts "STEP3_MESSAGE_REPORT=$msg_report"
close_project
