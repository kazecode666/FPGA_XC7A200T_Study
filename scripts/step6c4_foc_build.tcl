# Step 6C4 acceptance in the original local project. No bitstream.
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set token [clock format [clock seconds] -format %Y%m%d_%H%M%S]
if {$argc} {set token [lindex $argv 0]}
if {![regexp {^[A-Za-z0-9_]+$} $token]} {error {Invalid run label}}
set reports [file join $root docs reports step6c4 $token]
if {[file exists $reports]} {error {Use a fresh run label}}
file mkdir $reports
set scratch [file join $root .Xil step6c4_$token]
proc write_text {path content} {set f [open $path w]; puts $f $content; close $f}
proc read_text {path} {set f [open $path r]; set t [read $f]; close $f; return $t}
proc require {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
proc require_file {path} {require {[file isfile $path]} "Required file missing: $path"}

write_text [file join $reports build_result.txt] "IN_PROGRESS\nRun=$token"

proc resolve_simulator_bin {installation} {
    require {$installation ne ""} {Active Vivado installation is empty}
    set resolved [file normalize [file join $installation bin]]
    foreach tool {xvlog xelab xsim} {
        require_file [file join $resolved ${tool}.bat]
    }
    return $resolved
}

proc process_exit {options} {
    if {[dict exists $options -errorcode]} {
        set ec [dict get $options -errorcode]
        if {[llength $ec] >= 3 && [lindex $ec 0] eq "CHILDSTATUS"} {return [lindex $ec 2]}
        return $ec
    }
    return 0
}

proc run_command {name command} {
    global reports
    set status [catch {exec {*}$command 2>@1} output options]
    set exitcode [process_exit $options]
    write_text [file join $reports ${name}.txt] "Command: $command\n$output\nTcl status=$status; process status=$exitcode"
    require {$status == 0} "$name failed with process status $exitcode"
    require {![regexp -nocase {(^|\n)[ \t]*(fatal|error)(:|[ \t])|FATAL_ERROR|\$fatal|\$error} $output]} "$name emitted Fatal/Error text"
    return $output
}

proc simulate {name top sources marker fragments vector_dir} {
    global root scratch reports bin
    set dir [file join $scratch sim_$name]
    file mkdir $dir
    foreach source $sources {require_file $source}
    if {$name eq "c1_current_transform"} {
        file copy [file join $root motor_control_ip foc rom sin_qw_4096x18.mem] $dir
    }
    cd $dir
    run_command ${name}_compile [list [file join $bin xvlog.bat] -sv {*}$sources]
    run_command ${name}_elaborate [list [file join $bin xelab.bat] $top -s ${name}_snapshot]
    set command [list [file join $bin xsim.bat] ${name}_snapshot -runall]
    # xsim.bat requires the plusarg value to retain literal quotes on Windows.
    if {$vector_dir ne ""} {lappend command -testplusarg \"VECTOR_DIR=$vector_dir\"}
    set status [catch {exec {*}$command 2>@1} output options]
    set exitcode [process_exit $options]
    write_text [file join $reports ${name}_simulate.txt] "Command: $command\n$output\nTcl status=$status; process status=$exitcode"
    cd $root
    require {$status == 0} "$name simulation process failed: $exitcode"
    require {[regexp -line -- "^${marker}( |$)" $output]} "$name missing exact success marker: $marker"
    require {![regexp -nocase {(^|\n)[ \t]*(fatal|error)(:|[ \t])|FATAL_ERROR|\$fatal|\$error} $output]} "$name simulation emitted Fatal/Error text"
    foreach fragment $fragments {
        require {[string first $fragment $output] >= 0} "$name missing expected result fragment: $fragment"
    }
    puts "STEP6C4_SIM_PASS $name"
}

proc require_run {name expected} {
    set run [get_runs $name]
    require {[get_property STATUS $run] eq $expected} "$name status is [get_property STATUS $run], expected $expected"
    require {[get_property PROGRESS $run] eq "100%"} "$name progress is [get_property PROGRESS $run]"
}

proc collect_messages {run_names path} {
    set text "Anchored severity lines retained from actual run logs.\n"
    foreach name $run_names {
        set run [get_runs $name]
        set log [file join [get_property DIRECTORY $run] runme.log]
        append text "\n$name status=[get_property STATUS $run] progress=[get_property PROGRESS $run]\n"
        set counts [dict create ERROR 0 {CRITICAL WARNING} 0 WARNING 0]
        set messages {}
        if {[file isfile $log]} {
            foreach line [split [read_text $log] \n] {
                if {[regexp {^(ERROR|CRITICAL WARNING|WARNING):} $line -> severity]} {
                    dict incr counts $severity
                    lappend messages $line
                }
            }
        }
        append text "Counts include repeated anchored lines: $counts\n[join [lsort -unique $messages] \n]\n"
    }
    write_text $path $text
}

proc parse_utilization {path} {
    set text [read_text $path]
    set result ""
    foreach {label pattern} {
        {Slice LUT} {(?m)^\|[ \t]*Slice LUTs\*?[ \t]*\|[ \t]*([0-9,]+)[ \t]*\|}
        FF {(?m)^\|[ \t]*(?:Slice Registers|Register as Flip Flop)[ \t]*\|[ \t]*([0-9,]+)[ \t]*\|}
        DSP {(?m)^\|[ \t]*(?:DSPs|DSP48E1 only)[ \t]*\|[ \t]*([0-9,]+)[ \t]*\|}
        BRAM {(?m)^\|[ \t]*(?:Block RAM Tile|Block RAMs)[ \t]*\|[ \t]*([0-9,.]+)[ \t]*\|}
    } {
        require {[regexp $pattern $text -> value]} "Cannot extract $label from utilization report"
        append result "$label=$value\n"
    }
    return $result
}

set status [catch {
    require {[version -short] eq "2026.1"} {Expected Vivado 2026.1}
    set bin [resolve_simulator_bin $::env(XILINX_VIVADO)]
    file mkdir $scratch
    write_text [file join $reports provenance.txt] "MAIN=$root\nVivado=[version]\nPython=[exec python --version]\nTested code commit=[exec git rev-parse HEAD]\nBranch=[exec git branch --show-current]\nSimulator=$bin"
    foreach {name command marker} {
        python_c4_unit {python scripts/step6c4_foc_reference_test.py} {OK}
        python_c4_check {python scripts/step6c4_foc_reference.py --check} {STEP6C4_REFERENCE_CHECK_PASS rows=672}
        python_c3_check {python scripts/step6c3_svpwm_reference.py --check} {STEP6C3_REFERENCE_CHECK_PASS}
        python_c2_check {python scripts/step6c2_pi_reference.py --check} {C2_ORACLE_PASS: checked}
        python_c1_check {python scripts/step6c1_fixed_transform_reference.py --check} {PASS:}
        python_step6a {python scripts/reference_audit/verify_step6a_vectors.py} {PASS: 160 actual-source rows}
    } {
        set output [run_command $name $command]
        require {[string first $marker $output] >= 0} "$name missing marker"
    }
    simulate step6b_pwm motor_pwm_core_tb [list [file join $root motor_control_ip pwm rtl motor_pwm_core.sv] [file join $root motor_control_ip pwm tb motor_pwm_core_tb.sv]] {ALL STEP 6B MOTOR PWM TESTS PASSED} {} ""
    open_project [file join $root FOC_Current FOC_Current.xpr]
    require {[get_property PART [current_project]] eq "xc7a200tfbg484-2"} {Wrong device}
    require {[get_property TOP [get_filesets sources_1]] eq "mc_foc_current_core"} {Wrong design top}
    require {[get_property TOP [get_filesets sim_1]] eq "mc_foc_current_core_tb"} {Wrong simulation top}
    set sources [get_files -compile_order sources -used_in synthesis]
    require {[llength $sources] == 16} {Expected sixteen accepted/integration RTL files}
    set inventory "MAIN=$root\nXPR=[file join $root FOC_Current FOC_Current.xpr]\n"
    foreach f [get_files] {
        set f [file normalize $f]
        require {[file isfile $f] && [string first "$root/" $f] == 0} "Source outside MAIN or missing: $f"
        append inventory "$f\n"
    }
    set constraints [get_files -of_objects [get_filesets constrs_1]]
    require {[llength $constraints] == 1} {Expected one XDC}
    require {[string trim [read_text [lindex $constraints 0]]] eq {create_clock -name sys_clk -period 20.000 [get_ports clk]}} {Clock constraint mismatch}
    write_text [file join $reports project_paths.txt] $inventory
    set_property generic {PI_PROFILE=0} [get_filesets sources_1]
    set_property -name xsim.simulate.xsim.more_options -value "-testplusarg \"VECTOR_DIR=$root/motor_control_ip/foc/tb/vectors/step6c4\"" -objects [get_filesets sim_1]
    # Profile 1 first; the retained default snapshot/WDB and project finish at 0.
    foreach profile {1 0} {
        set_property generic "PI_PROFILE=$profile" [get_filesets sim_1]
        launch_simulation
        source [file join $root FOC_Current wave_step6c4.tcl]
        run all
        set logfile [file join $root FOC_Current FOC_Current.sim sim_1 behav xsim simulate.log]
        set output [read_text $logfile]
        write_text [file join $reports c4_profile${profile}_simulate.txt] $output
        require {[string first "ALL STEP 6C4 FOC CURRENT TESTS PASSED profile=$profile base=336 accepted=349 responses=347 aborted=2 latency=512 poisoned=175616" $output] >= 0} "Profile $profile missing exact success/counts"
        require {[string first "C4_BASE_PASS profile=$profile historical=80 seeded=256 rows=336 spacing=5000" $output] >= 0} {Base row count failed}
        require {![regexp -nocase {(^|\n)[ \t]*(fatal|error)(:|[ \t])|FATAL_ERROR|\$fatal|\$error} $output]} {Simulation reported failure}
        save_wave_config [file join $root FOC_Current FOC_Current.sim step6c4.wcfg]
        close_sim
    }
    write_text [file join $reports regression_summary.txt] "PASS: six Python checks; C4 profiles 0/1 (672 base rows, 698 accepts, 694 responses, 4 reset aborts); Step 6B PWM."
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    require_run synth_1 {synth_design Complete!}
    file copy [file join [get_property DIRECTORY [get_runs synth_1]] runme.log] [file join $reports synth_runme.txt]
    open_run synth_1
    report_utilization -file [file join $reports synth_utilization.rpt]
    report_utilization -hierarchical -file [file join $reports synth_hierarchy.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $reports synth_timing_summary.rpt]
    set latch_count [llength [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]]
    set blackbox_count [llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]]
    require {$latch_count == 0} {Inferred latch detected}
    require {$blackbox_count == 0} {Black box or unresolved module detected}
    set primitive_text "Synthesis primitive inventory\nLATCH=$latch_count\nBLACKBOX=$blackbox_count\n"
    foreach {name filter} {DSP48E1 {REF_NAME == DSP48E1} RAMB36E1 {REF_NAME == RAMB36E1} RAMB18E1 {REF_NAME == RAMB18E1} LUT {REF_NAME =~ LUT*} FF {REF_NAME =~ FD*}} {
        append primitive_text "$name=[llength [get_cells -hier -quiet -filter $filter]]\n"
    }
    append primitive_text [parse_utilization [file join $reports synth_utilization.rpt]]
    write_text [file join $reports synth_resources.txt] $primitive_text
    close_design

    launch_runs impl_1 -to_step route_design -jobs 4
    wait_on_run impl_1
    require_run impl_1 {route_design Complete!}
    file copy [file join [get_property DIRECTORY [get_runs impl_1]] runme.log] [file join $reports impl_runme.txt]
    open_run impl_1
    require {[llength [get_clocks]] == 1} {Expected exactly one clock}
    require {[get_property NAME [get_clocks]] eq "sys_clk" && [get_property PERIOD [get_clocks sys_clk]] == 20.0} {sys_clk period is not 20.000 ns}
    report_clocks -file [file join $reports clocks.rpt]
    report_utilization -file [file join $reports routed_utilization.rpt]
    report_utilization -hierarchical -file [file join $reports routed_hierarchy.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $reports routed_timing_summary.rpt]
    check_timing -verbose -file [file join $reports check_timing.rpt]
    report_timing -delay_type max -max_paths 5 -file [file join $reports setup_paths.rpt]
    report_timing -delay_type min -max_paths 5 -file [file join $reports hold_paths.rpt]
    report_route_status -file [file join $reports route_status.rpt]
    report_drc -file [file join $reports drc.rpt]
    report_methodology -file [file join $reports methodology.rpt]

    set route [read_text [file join $reports route_status.rpt]]
    foreach {key var} {{# of routable nets} routable {# of fully routed nets} routed {# of nets with routing errors} route_errors} {
        require {[regexp [format {%s[. ]*:[ ]*([0-9]+)} $key] $route -> $var]} "Missing route count: $key"
    }
    require {$routable > 0 && $routed == $routable && $route_errors == 0} {Routing is incomplete or has errors}

    set timing [read_text [file join $reports routed_timing_summary.rpt]]
    set header [string first {WNS(ns)} $timing]
    require {$header >= 0} {Routed timing summary header missing}
    set table [string range $timing $header end]
    set num {[-+]?[0-9]+(?:\.[0-9]+)?}
    set pattern [format {(?m)^\s*(%s)\s+(%s)\s+([0-9]+)\s+([0-9]+)\s+(%s)\s+(%s)\s+([0-9]+)\s+([0-9]+)\s+} $num $num $num $num]
    require {[regexp $pattern $table -> wns tns setup_fail setup_total whs ths hold_fail hold_total]} {Cannot extract routed WNS/TNS/WHS/THS}
    require {$setup_total > 0 && $hold_total > 0 && $setup_fail == 0 && $hold_fail == 0} {Routed timing endpoint/failure count gate failed}
    require {$wns >= 0 && $tns == 0 && $whs >= 0 && $ths == 0} {Routed setup/hold timing failed}
    set raw_text ""
    foreach delay {max min} {
        set path [get_timing_paths -delay_type $delay -max_paths 1]
        require {[llength $path] == 1 && [get_property SLACK $path] >= 0} "Raw routed $delay path failed"
        append raw_text "$delay SLACK=[get_property SLACK $path] STARTPOINT=[get_property STARTPOINT_PIN $path] ENDPOINT=[get_property ENDPOINT_PIN $path]\n"
    }
    set checks [read_text [file join $reports check_timing.rpt]]
    foreach category {no_clock unconstrained_internal_endpoints loops latch_loops} {
        require {[regexp -- [format {checking %s \(([0-9]+)\)} $category] $checks -> count] && $count == 0} "Timing category failed: $category"
    }
    set blockers {}
    set drc_text "All DRC findings retained without severity changes.\n"
    foreach violation [get_drc_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        append drc_text "$severity $violation\n"
        if {$severity in {Error {Critical Warning}} && ![regexp {^(UCIO-1|NSTD-1|CFGBVS-1)(#|$)} $violation]} {lappend blockers $violation}
    }
    require {[llength $blockers] == 0} "Blocking non-board DRCs: $blockers"
    write_text [file join $reports drc_categories.txt] $drc_text
    write_text [file join $reports route_timing_gate.txt] "PASS\nsys_clk=20.000 ns\nroutable=$routable fully_routed=$routed routing_errors=$route_errors\nWNS=$wns TNS=$tns setup_failing=$setup_fail setup_total=$setup_total\nWHS=$whs THS=$ths hold_failing=$hold_fail hold_total=$hold_total\n$raw_text\nno_clock=0 unconstrained_internal_endpoints=0 loops=0 latch_loops=0\nClock-only internal core timing; board pins, IOSTANDARD and external I/O delays are absent."
    write_text [file join $reports routed_resources.txt] [parse_utilization [file join $reports routed_utilization.rpt]]
    collect_messages {synth_1 impl_1} [file join $reports warning_categories.txt]
    write_text [file join $reports build_result.txt] "PASS\nSTEP6C4_BUILD_PASS\nRun=$token\nTested code commit=[exec git rev-parse HEAD]\nDefault PI_PROFILE=0\nMAIN=$root\nWNS=$wns TNS=$tns WHS=$whs THS=$ths\nRouted=$routed/$routable errors=$route_errors\nNo bitstream or hardware; profile 1 simulation only"
    puts "STEP6C4_BUILD_PASS WNS=$wns TNS=$tns WHS=$whs THS=$ths ROUTED=$routed/$routable"
} detail options]
if {$status} {
    write_text [file join $reports build_result.txt] "FAILED\n$detail\n[dict get $options -errorinfo]"
    puts stderr "STEP6C4_BUILD_FAILED: $detail"
}
catch {close_project}
exit [expr {$status ? 1 : 0}]
