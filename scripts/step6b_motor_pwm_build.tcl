# vivado -mode batch -nojournal -log step6b_local.log -source scripts/step6b_motor_pwm_build.tcl
# Independent portable motor PWM project. Route only; no bitstream or hardware.
# Existing legacy projects are never opened or written. No files are deleted.
set root [file normalize [file join [file dirname [info script]] ..]]
set reports [file join $root docs reports step6b]
set project_dir [file join $root Motor_PWM]
set xpr [file join $project_dir Motor_PWM.xpr]
set run_names {}
file mkdir $reports

proc write_text {path content} {
    set h [open $path w]
    puts $h $content
    close $h
}
proc read_text {path} {
    set h [open $path r]
    set content [read $h]
    close $h
    return $content
}
proc require {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc require_run {name status} {
    require {[get_property STATUS [get_runs $name]] eq $status} "$name failed/incomplete"
    require {[get_property PROGRESS [get_runs $name]] eq "100%"} "$name progress incomplete"
}
proc add_source {fileset path} {
    require {[file isfile $path]} "Source missing: $path"
    if {[llength [get_files -quiet -of_objects [get_filesets $fileset] $path]] == 0} {
        add_files -fileset $fileset -norecurse $path
    }
}
proc simulate {project_dir project_name tb marker} {
    global reports
    set_property top $tb [get_filesets sim_1]
    set_property top_auto_set 0 [get_filesets sim_1]
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    update_compile_order -fileset sim_1
    set code [catch {
        launch_simulation -simset sim_1 -mode behavioral
        run all
    } detail options]
    catch {close_sim}
    set log [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
    set content ""
    if {[file exists $log]} { set content [read_text $log] }
    write_text [file join $reports ${tb}.txt] "$content\nSimulation Tcl status: $code\n$detail"
    if {$code} { return -options $options $detail }
    require {[string first $marker $content] >= 0} "$tb did not report PASS"
    require {![regexp -nocase {(^|\n)[ \t]*(fatal|error)(:|[ \t])|\$fatal|\$error} $content]} "$tb reported a failure"
}
proc write_messages {status detail} {
    global reports run_names
    set text "Step 6B execution: $status\nVivado: [version -short]\n$detail\n"
    foreach name $run_names {
        set run [get_runs -quiet $name]
        if {[llength $run] == 0} { continue }
        append text "\n$name: [get_property STATUS $run] ([get_property PROGRESS $run])\n"
        set log [file join [get_property DIRECTORY $run] runme.log]
        if {![file exists $log]} { continue }
        set counts [dict create ERROR 0 {CRITICAL WARNING} 0 WARNING 0]
        set messages {}
        foreach line [split [read_text $log] \n] {
            if {[regexp {^(ERROR|CRITICAL WARNING|WARNING):} $line -> severity]} {
                dict incr counts $severity
                lappend messages $line
            }
        }
        append text "Counts include repeated anchored severity lines: $counts\n"
        append text "[join [lsort -unique $messages] \n]\n"
    }
    append text "\nClock-only internal timing; no board I/O timing sign-off, bitstream or hardware test.\n"
    write_text [file join $reports messages.txt] $text
}

write_text [file join $reports build_result.txt] "STEP6B_BUILD_IN_PROGRESS; not a PASS result"
set result [catch {
    require {[version -short] eq "2026.1"} "Expected Vivado 2026.1"
    require {[file isfile $xpr]} "Tracked Motor_PWM/Motor_PWM.xpr is missing; restore it from the repository before building"
    # A unique scratch project prevents regressions from touching legacy outputs.
    set token "[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]"
    set scratch [file normalize [file join $::env(TEMP) step6b_legacy_$token]]
    require {![file exists $scratch]} "Scratch directory already exists: $scratch"
    create_project step6b_legacy $scratch -part xc7a200tfbg484-2
    require {[get_property PART [current_project]] eq "xc7a200tfbg484-2"} "Wrong FPGA part"
    foreach relative {
        PWM_Controller/PWM_Controller.srcs/sources_1/new/pwm_control.sv
        PWM_Controller/PWM_Controller.srcs/sources_1/new/pwm_demo_top.sv
        PWM_Breathe/rtl/pwm_breathe_top.sv
    } { add_source sources_1 [file join $root $relative] }
    foreach relative {
        PWM_Controller/PWM_Controller.srcs/sim_1/new/pwm_controller_tb.sv
        PWM_Controller/PWM_Controller.srcs/sim_1/new/pwm_demo_top_tb.sv
        PWM_Breathe/tb/pwm_breathe_top_tb.sv
    } { add_source sim_1 [file join $root $relative] }
    foreach {tb marker} {
        pwm_controller_tb {ALL STEP 2.5 PWM TESTS PASSED}
        pwm_demo_top_tb {ALL STEP 5A BOARD TESTS PASSED}
        pwm_breathe_top_tb {ALL STEP 5B BREATHING TESTS PASSED}
    } { simulate $scratch step6b_legacy $tb $marker }
    close_project

    # The portable XPR is a tracked input, like the RTL and clock constraint.
    # Open it rather than recreating a populated project directory.
    open_project $xpr
    require {[get_property PART [current_project]] eq "xc7a200tfbg484-2"} "Wrong FPGA part"
    set_property target_language Verilog [current_project]
    add_source sources_1 [file join $root motor_control_ip pwm rtl motor_pwm_core.sv]
    add_source sim_1 [file join $root motor_control_ip pwm tb motor_pwm_core_tb.sv]
    set xdc [file join $project_dir Motor_PWM.srcs constrs_1 new motor_pwm_clock.xdc]
    require {[string trim [read_text $xdc]] eq {create_clock -name sys_clk -period 20.000 [get_ports clk]}} "Clock-only XDC contract changed"
    add_source constrs_1 $xdc
    require {[llength [get_files -of_objects [get_filesets sources_1]]] == 1} "Unexpected motor design sources"
    require {[llength [get_files -of_objects [get_filesets sim_1]]] == 1} "Unexpected motor simulation sources"
    require {[llength [get_files -of_objects [get_filesets constrs_1]]] == 1} "Unexpected constraints"
    set_property top motor_pwm_core [get_filesets sources_1]
    set_property top_auto_set 0 [get_filesets sources_1]
    # No generic overrides: synthesize the real TBPRD=2500 RTL default.
    set_property generic {} [get_filesets sources_1]
    update_compile_order -fileset sources_1
    simulate $project_dir Motor_PWM motor_pwm_core_tb {ALL STEP 6B MOTOR PWM TESTS PASSED}

    # Fresh uniquely named runs retain prior evidence without reset_run/cleanup.
    set synth step6b_synth_$token
    set impl step6b_impl_$token
    create_run $synth -flow {Vivado Synthesis 2026} -strategy {Vivado Synthesis Defaults} -constrset constrs_1
    create_run $impl -parent_run $synth -flow {Vivado Implementation 2026} -strategy {Vivado Implementation Defaults} -constrset constrs_1
    set run_names [list $synth $impl]
    current_run -synthesis [get_runs $synth]
    current_run -implementation [get_runs $impl]
    launch_runs $synth -jobs 4
    wait_on_run $synth
    require_run $synth {synth_design Complete!}
    open_run $synth
    report_utilization -file [file join $reports synth_utilization.rpt]
    require {[llength [get_cells -hier -filter {REF_NAME =~ LD*}]] == 0} "Inferred latch detected"
    # The real default produces a 12-bit visible counter (ceil(log2(2501))).
    require {[llength [get_ports -quiet {tbctr[*]}]] == 12} "Real TBPRD counter width mismatch"
    close_design
    launch_runs $impl -to_step route_design -jobs 4
    wait_on_run $impl
    require_run $impl {route_design Complete!}
    open_run $impl
    require {[llength [get_clocks]] == 1 && [get_property PERIOD [get_clocks sys_clk]] == 20.0} "Clock audit mismatch"
    report_utilization -file [file join $reports impl_utilization.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $reports timing_summary.rpt]
    check_timing -verbose -file [file join $reports check_timing.rpt]
    report_timing -delay_type max -max_paths 5 -file [file join $reports setup_paths.rpt]
    report_timing -delay_type min -max_paths 5 -file [file join $reports hold_paths.rpt]
    report_drc -file [file join $reports drc.rpt]
    report_methodology -file [file join $reports methodology.rpt]
    report_route_status -file [file join $reports route_status.rpt]
    report_exceptions -file [file join $reports exceptions.rpt]

    # Parse the design summary's numeric row, not arbitrary per-path slack text.
    set timing [read_text [file join $reports timing_summary.rpt]]
    set header [string first {WNS(ns)} $timing]
    require {$header >= 0} "Timing summary header missing"
    set table [string range $timing $header end]
    set numeric {[-+]?[0-9]+(?:\.[0-9]+)?}
    set pattern [format {(?m)^\s*(%s)\s+(%s)\s+([0-9]+)\s+([0-9]+)\s+(%s)\s+(%s)\s+([0-9]+)\s+([0-9]+)\s+} $numeric $numeric $numeric $numeric]
    require {[regexp $pattern $table -> wns tns setup_fail setup_total whs ths hold_fail hold_total]} "Cannot extract WNS/TNS/WHS/THS"
    require {$setup_total > 0 && $hold_total > 0} "No timed endpoints"
    require {$wns >= 0 && $tns == 0 && $whs >= 0 && $ths == 0 && $setup_fail == 0 && $hold_fail == 0} "Routed internal timing failed"
    # Unrounded path properties independently guard against rounded negative slack.
    foreach delay {max min} {
        set worst [get_timing_paths -delay_type $delay -max_paths 1]
        require {[llength $worst] == 1 && [get_property SLACK $worst] >= 0} "Internal $delay timing failed"
    }
    # Pin/voltage DRCs are expected for an intentionally clock-only portable core.
    set blockers {}
    foreach violation [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}] {
        if {![regexp {^(UCIO-1|NSTD-1|CFGBVS-1)(#|$)} $violation]} { lappend blockers $violation }
    }
    require {[llength $blockers] == 0} "Blocking non-board DRCs: $blockers"
    write_messages PASS "WNS=$wns TNS=$tns WHS=$whs THS=$ths"
    write_text [file join $reports build_result.txt] "STEP6B_BUILD_PASS\nVivado: [version -short]\nPart: [get_property PART [current_project]]\nTop: motor_pwm_core; TBPRD=2500; 50 MHz / 10 kHz\nMotor simulation and all three unchanged legacy regressions: PASS\nSynthesis: [get_property STATUS [get_runs $synth]]\nImplementation: [get_property STATUS [get_runs $impl]]\nRouted internal WNS=$wns ns TNS=$tns ns WHS=$whs ns THS=$ths ns\nExternal I/O delays and pin assignments: intentionally absent; no board-level timing sign-off\nBitstream: NOT GENERATED\nPhysical hardware: NOT TESTED"
    puts "STEP6B_BUILD_PASS WNS=$wns TNS=$tns WHS=$whs THS=$ths"
} detail options]
if {$result} {
    catch {write_messages FAIL $detail}
    write_text [file join $reports build_result.txt] "STEP6B_BUILD_FAILED: $detail\nNo board-level timing sign-off or hardware validation."
    puts stderr "STEP6B_BUILD_FAILED: $detail\n[dict get $options -errorinfo]"
}
catch {close_project}
exit [expr {$result ? 1 : 0}]
