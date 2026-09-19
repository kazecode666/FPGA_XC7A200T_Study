# Vivado 2026.1: compact, fail-closed Step 6C3 acceptance. No bitstream.
# Run from the repository root with a fresh label:
#   vivado -mode batch -nojournal -nolog -source scripts/step6c3_svpwm_build.tcl -tclargs LABEL
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set token [clock format [clock seconds] -format %Y%m%d_%H%M%S]
if {$argc} {set token [lindex $argv 0]}
if {![regexp {^[A-Za-z0-9_]+$} $token]} {error {Run label must use letters, digits or underscore}}
set reports [file join $root docs reports step6c3 $token]
if {[file exists $reports]} {error {Run label already exists; use a fresh label}}
file mkdir $reports
set scratch [file join $root .Xil step6c3_$token]

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
    puts "STEP6C3_SIM_PASS $name"
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

proc audit_portable_project {} {
    global root reports
    set xpr [file join $root FOC_SVPWM FOC_SVPWM.xpr]
    require_file $xpr
    open_project -read_only $xpr
    require {[get_property PART [current_project]] eq "xc7a200tfbg484-2"} {Portable XPR part mismatch}
    require {[get_property TOP [get_filesets sources_1]] eq "mc_sector_svpwm"} {Portable XPR synthesis top mismatch}
    require {[get_property TOP [get_filesets sim_1]] eq "mc_sector_svpwm_tb"} {Portable XPR simulation top mismatch}
    set expected [list \
        [file join $root motor_control_ip foc rtl mc_svpwm_pkg.sv] \
        [file join $root motor_control_ip foc rtl mc_svpwm_sector_xyz.sv] \
        [file join $root motor_control_ip foc rtl mc_udiv_u72_u41.sv] \
        [file join $root motor_control_ip foc rtl mc_sector_svpwm.sv]]
    set actual [get_files -compile_order sources -used_in synthesis]
    require {[llength $actual] == 4} {Portable XPR synthesis inventory count mismatch}
    foreach path $expected {require {[lsearch -exact $actual [file normalize $path]] >= 0} "Portable XPR missing synthesis source $path"}
    require {[file tail [lindex $actual 0]] eq "mc_svpwm_pkg.sv"} {Portable XPR package is not first in compile order}
    set sim_files [get_files -of_objects [get_filesets sim_1]]
    foreach name {mc_svpwm_pkg_tb.sv mc_svpwm_sector_xyz_tb.sv mc_sector_svpwm_tb.sv manifest.json sector_xyz_vectors.txt svpwm_vectors.txt} {
        set found 0
        foreach path $sim_files {if {[file tail $path] eq $name} {set found 1}}
        require {$found} "Portable XPR missing simulation file $name"
    }
    set xdc_files [get_files -of_objects [get_filesets constrs_1]]
    require {[llength $xdc_files] == 1} {Portable XPR constraint inventory mismatch}
    require {[string trim [read_text [lindex $xdc_files 0]]] eq {create_clock -name sys_clk -period 20.000 [get_ports clk]}} {Portable XPR clock constraint mismatch}
    write_text [file join $reports project_audit.txt] "PASS\nPart=xc7a200tfbg484-2\nTop=mc_sector_svpwm\nPackage-first synthesis order=$actual\nSimulation inventory=$sim_files\nConstraint=[lindex $xdc_files 0]"
    close_project
}

set status [catch {
    require {[version -short] eq "2026.1"} {Expected Vivado 2026.1}
    require {[info exists ::env(XILINX_VIVADO)]} {Active Vivado launcher did not define XILINX_VIVADO}
    set bin [resolve_simulator_bin $::env(XILINX_VIVADO)]
    require {![file exists $scratch]} {Fresh scratch directory already exists}
    file mkdir $scratch
    set provenance "Vivado=[version]\nActive executable=[info nameofexecutable]\nActive installation=$::env(XILINX_VIVADO)\nResolved simulator directory=$bin\nPython=[exec python --version]\nTested code commit=[exec git rev-parse HEAD]\nBranch=[exec git branch --show-current]\nRun=$token\nScratch=$scratch\n"
    foreach tool {xvlog xelab xsim} {
        set output [run_command tool_${tool}_version [list [file join $bin ${tool}.bat] -version]]
        require {[regexp -line {^Vivado Simulator v2026\.1\s*$} $output]} "Unexpected $tool version"
        append provenance "$tool=$output\n"
    }
    write_text [file join $reports provenance.txt] $provenance

    foreach {name command marker} {
        python_c3_unit {python scripts/step6c3_svpwm_reference_test.py} {OK}
        python_c3_check {python scripts/step6c3_svpwm_reference.py --check} {STEP6C3_REFERENCE_CHECK_PASS}
        python_c2_check {python scripts/step6c2_pi_reference.py --check} {C2_ORACLE_PASS: checked}
        python_c1_check {python scripts/step6c1_fixed_transform_reference.py --check} {PASS:}
        python_step6a {python scripts/reference_audit/verify_step6a_vectors.py} {PASS: 160 actual-source rows}
    } {
        set output [run_command $name $command]
        require {[string first $marker $output] >= 0} "$name missing marker: $marker"
    }

    set c3_pkg [file join $root motor_control_ip foc rtl mc_svpwm_pkg.sv]
    set c3_sector [file join $root motor_control_ip foc rtl mc_svpwm_sector_xyz.sv]
    set divider [file join $root motor_control_ip foc rtl mc_udiv_u72_u41.sv]
    set c3_top [file join $root motor_control_ip foc rtl mc_sector_svpwm.sv]
    set c3_vectors [file join $root motor_control_ip foc tb vectors step6c3]
    set c2_vectors [file join $root motor_control_ip foc tb vectors step6c2]
    set c1_vectors [file join $root motor_control_ip foc tb vectors]
    simulate c3_pkg mc_svpwm_pkg_tb [list $c3_pkg [file join $root motor_control_ip foc tb mc_svpwm_pkg_tb.sv]] {ALL STEP 6C3 SVPWM PKG TESTS PASSED} {} ""
    simulate c3_sector mc_svpwm_sector_xyz_tb [list $c3_pkg $c3_sector [file join $root motor_control_ip foc tb mc_svpwm_sector_xyz_tb.sv]] {ALL STEP 6C3 SECTOR XYZ TESTS PASSED} {{rows=790 fields=16 directed=22 seeded=768}} $c3_vectors
    simulate c3_top mc_sector_svpwm_tb [list $c3_pkg $c3_sector $divider $c3_top [file join $root motor_control_ip foc tb mc_sector_svpwm_tb.sv]] {ALL STEP 6C3 SECTOR SVPWM TESTS PASSED} {{rows=790 accepted=791 responses=790 latency=128 aborts=1 poisoned_cycles=101120} {PROTOCOL_BUSY_INPUT_IMMUNITY_PASS rows=790 poisoned_cycles=101120} {PROTOCOL_FIXED_LATENCY_PASS responses=790 latency=128} {PROTOCOL_EARLIEST_NEXT_ACCEPT_PASS completion_edges_blocked=790 following_edge_accepts=789} {PROTOCOL_RESET_ABORT_PASS aborts=1 stale_responses=0}} $c3_vectors
    simulate c2_divider mc_udiv_u72_u41_tb [list $divider [file join $root motor_control_ip foc tb mc_udiv_u72_u41_tb.sv]] {ALL STEP 6C2 UDIV TESTS PASSED} {{fixture_rows=2058 transactions=4125 aborts=72 idle_clocks=5000}} $c2_vectors
    set c2_sources {}
    foreach name {mc_pi_fxp_pkg mc_isqrt_u80 mc_udiv_u72_u41 mc_pi_dq_eval mc_dq_limiter mc_pi_dq_core} {lappend c2_sources [file join $root motor_control_ip foc rtl ${name}.sv]}
    lappend c2_sources [file join $root motor_control_ip foc tb mc_pi_dq_core_tb.sv]
    simulate c2_core mc_pi_dq_core_tb $c2_sources {ALL STEP 6C2 PI DQ CORE TESTS PASSED} {{profile=0 accepted=2751 completed=2493 successful=2229 invalid_vdc=129 range=128 internal=7 aborted=258 latency=256}} $c2_vectors
    set c1_sources {}
    foreach name {mc_fxp_pkg mc_clarke mc_sincos_lut mc_park mc_current_transform} {lappend c1_sources [file join $root motor_control_ip foc rtl ${name}.sv]}
    lappend c1_sources [file join $root motor_control_ip foc tb mc_current_transform_tb.sv]
    simulate c1_current_transform mc_current_transform_tb $c1_sources {ALL STEP 6C1 TRANSFORM TESTS PASSED} {} $c1_vectors
    simulate step6b_pwm motor_pwm_core_tb [list [file join $root motor_control_ip pwm rtl motor_pwm_core.sv] [file join $root motor_control_ip pwm tb motor_pwm_core_tb.sv]] {ALL STEP 6B MOTOR PWM TESTS PASSED} {} ""
    write_text [file join $reports regression_summary.txt] "PASS\n5 Python checks\n7 simulations: C3 package, C3 Sector/XYZ, C3 full top, C2 divider, C2 core profile 0, C1 current transform, Step 6B motor PWM"

    audit_portable_project

    set project_dir [file join $scratch project]
    create_project step6c3_build $project_dir -part xc7a200tfbg484-2
    foreach path [list $c3_pkg $c3_sector $divider $c3_top] {add_files -norecurse $path}
    add_files -fileset constrs_1 -norecurse [file join $root FOC_SVPWM FOC_SVPWM.srcs constrs_1 new foc_svpwm_clock.xdc]
    set_property TOP mc_sector_svpwm [get_filesets sources_1]
    set_property TOP_AUTO_SET 0 [get_filesets sources_1]
    update_compile_order -fileset sources_1
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
    write_text [file join $reports build_result.txt] "PASS\nSTEP6C3_BUILD_PASS\nRun=$token\nTested code commit=[exec git rev-parse HEAD]\nVivado=[version -short]\nPart=xc7a200tfbg484-2 Top=mc_sector_svpwm sys_clk=20.000 ns\n5 Python checks and 7 compact simulations PASS\nSynthesis diagnostics and routed timing summaries retained\nWNS=$wns ns TNS=$tns ns WHS=$whs ns THS=$ths ns\nRoutable=$routable fully_routed=$routed routing_errors=$route_errors\nLatches=0 blackboxes=0 loops=0 latch_loops=0\nClock-only internal core timing; board I/O warnings retained\nNo bitstream generated; no physical hardware, C4 or Step 6D work"
    puts "STEP6C3_BUILD_PASS WNS=$wns TNS=$tns WHS=$whs THS=$ths ROUTED=$routed/$routable"
} detail options]

if {$status} {
    catch {collect_messages {synth_1 impl_1} [file join $reports warning_categories.txt]}
    write_text [file join $reports build_result.txt] "FAILED\nRun=$token\n$detail\n[dict get $options -errorinfo]"
    puts stderr "STEP6C3_BUILD_FAILED: $detail"
}
catch {close_project}
exit [expr {$status ? 1 : 0}]
