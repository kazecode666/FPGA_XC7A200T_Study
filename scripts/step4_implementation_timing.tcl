# Rebuild the existing project through route_design, then report routed timing.
# vivado -mode batch -nojournal -nolog -source scripts/step4_implementation_timing.tcl
# No board constraints, timing exceptions, or bitstream generation.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $repo_root docs reports]
file mkdir $report_dir

proc verify_clock {} {
    set clocks [get_clocks -quiet sys_clk]
    if {[llength $clocks] != 1} { error "Expected exactly one sys_clk" }
    set period [get_property PERIOD $clocks]
    if {abs($period - 20.0) > 0.000001} { error "Unexpected clock period: $period" }
    puts "STEP4_CLOCK=[get_clocks] PERIOD=$period ns"
}

proc verify_run {name expected} {
    set status [get_property STATUS [get_runs $name]]
    set progress [get_property PROGRESS [get_runs $name]]
    puts "STEP4_${name}_STATUS=$status PROGRESS=$progress"
    if {$progress ne "100%" || $status ne $expected} {
        error "$name incomplete: $status ($progress)"
    }
}

proc write_messages {result detail} {
    global report_dir
    set f [open [file join $report_dir step4_messages.txt] w]
    puts $f "Step 4 execution: $result"
    puts $f "Vivado: [version -short]"
    if {$detail ne ""} { puts $f "Blocker: $detail" }
    foreach name {synth_1 impl_1} {
        set run [get_runs -quiet $name]
        if {[llength $run] == 0} { continue }
        puts $f "\n$name status: [get_property STATUS $run]"
        puts $f "$name progress: [get_property PROGRESS $run]"
        puts $f "$name strategy: [get_property STRATEGY $run]"
        set log [file join [get_property DIRECTORY $run] runme.log]
        if {![file exists $log]} { puts $f "Run log unavailable"; continue }
        set h [open $log r]
        set lines [split [read $h] \n]
        close $h
        set counts [dict create ERROR 0 {CRITICAL WARNING} 0 WARNING 0]
        set messages {}
        foreach line $lines {
            if {[regexp {^(ERROR|CRITICAL WARNING|WARNING):} $line -> severity]} {
                dict incr counts $severity
                lappend messages $line
            }
        }
        puts $f "Counts: anchored severity lines in this run's runme.log (includes repeated occurrences)"
        dict for {severity count} $counts { puts $f "$severity: $count" }
        foreach line [lsort -unique $messages] { puts $f $line }
    }
    puts $f "\nNo bitstream or hardware programming requested. External I/O timing remains incomplete."
    close $f
}

open_project [file join $repo_root PWM_Controller PWM_Controller.xpr]
set code [catch {
    if {[version -short] ne "2026.1"} { error "Expected Vivado 2026.1" }
    if {[get_property TOP [get_filesets sources_1]] ne "pwm_controller"} { error "Unexpected top" }
    if {[get_property PART [current_project]] ne "xc7a200tfbg484-2"} { error "Unexpected part" }
    set xdc_path [file join $repo_root PWM_Controller PWM_Controller.srcs constrs_1 new pwm_timing.xdc]
    set xdc [get_files -quiet -of_objects [get_filesets constrs_1] $xdc_path]
    if {[llength $xdc] != 1} { error "pwm_timing.xdc must already belong to constrs_1" }
    foreach phase {SYNTHESIS IMPLEMENTATION} {
        if {![get_property USED_IN_$phase $xdc]} { error "XDC disabled for $phase" }
    }
    if {[get_property STRATEGY [get_runs impl_1]] ne "Vivado Implementation Defaults"} {
        error "Expected default implementation strategy"
    }
    # Reset only the named Vivado runs; no filesystem cleanup is performed here.
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    verify_run synth_1 "synth_design Complete!"
    open_run synth_1
    verify_clock
    close_design
    reset_run impl_1
    launch_runs impl_1 -to_step route_design -jobs 4
    wait_on_run impl_1
    verify_run impl_1 "route_design Complete!"
    open_run impl_1
    verify_clock
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 5 -file [file join $report_dir step4_timing_summary.rpt]
    report_timing -delay_type max -max_paths 5 -path_type full_clock_expanded -input_pins -file [file join $report_dir step4_worst_setup_paths.rpt]
    report_timing -delay_type min -max_paths 5 -path_type full_clock_expanded -input_pins -file [file join $report_dir step4_worst_hold_paths.rpt]
    check_timing -verbose -file [file join $report_dir step4_check_timing.rpt]
    report_utilization -file [file join $report_dir step4_impl_utilization.rpt]
    report_clock_utilization -file [file join $report_dir step4_clock_utilization.rpt]
    report_methodology -file [file join $report_dir step4_methodology.rpt]
    # Supplemental route/DRC evidence stays inside the allowed check report.
    report_route_status -append -file [file join $report_dir step4_check_timing.rpt]
    report_drc -append -file [file join $report_dir step4_check_timing.rpt]
    set f [open [file join $report_dir step4_impl_utilization.rpt] a]
    puts $f "\nPlaced primitive inventory (actual LOC / BEL)"
    foreach cell [lsort [get_cells -hierarchical -filter {IS_PRIMITIVE == 1}]] {
        puts $f "$cell | [get_property REF_NAME $cell] | [get_property LOC $cell] | [get_property BEL $cell]"
    }
    close $f
} detail options]
write_messages [expr {$code == 0 ? "PASS" : "FAIL"}] $detail
if {$code != 0} {
    puts stderr "STEP4_BLOCKER=$detail"
    close_project
    exit 1
}
puts "STEP4_ROUTE_AND_REPORTS_PASS"
close_project
