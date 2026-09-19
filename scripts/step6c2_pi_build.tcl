# Vivado 2026.1: fresh, fail-closed C2 acceptance. Never creates a bitstream.
# Run from repo: vivado -mode batch -source scripts/step6c2_pi_build.tcl
# Optional -tclargs LABEL (letters/digits/underscore); reports are never reused.
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set token [clock format [clock seconds] -format %m%d_%H%M%S]
if {$argc} {set token [lindex $argv 0]}
if {![regexp {^[a-zA-Z0-9_]+$} $token]} {error {Invalid run label}}
set reports [file join $root docs reports step6c2 $token]
if {[file exists $reports]} {error {Run label already exists; choose a fresh label}}
file mkdir $reports
proc write_text {path content} {set f [open $path w]; puts $f $content; close $f}
proc read_text {path} {set f [open $path r]; set t [read $f]; close $f; return $t}
proc require {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
write_text [file join $reports build_result.txt] "IN_PROGRESS\nRun=$token"
set scratch [file join $root .Xil c2_$token]
set bin E:/AMDDesignTools/2026.1/Vivado/bin
set rtl_names {mc_pi_fxp_pkg mc_isqrt_u80 mc_udiv_u72_u41 mc_pi_dq_eval mc_dq_limiter mc_pi_dq_core}
set tb_names {mc_pi_fxp_tb mc_isqrt_u80_tb mc_udiv_u72_u41_tb mc_pi_dq_eval_tb mc_dq_limiter_tb mc_pi_dq_core_tb}
set vectors {round_vectors.txt range_vectors.txt sqrt_vectors.txt divider_vectors.txt evaluator_vectors.txt limiter_vectors.txt golden_core_vectors.txt seeded_core_vectors.txt error_core_vectors.txt}
set xdc [file join $root FOC_PI FOC_PI.srcs constrs_1 new foc_pi_clock.xdc]
proc source_exists {path} {require {[file isfile $path]} "Source missing: $path"}
proc run_command {name command} {
    global reports
    set status [catch {exec {*}$command 2>@1} output options]
    set exitcode 0
    if {$status} {set exitcode [dict get $options -errorcode]}
    write_text [file join $reports ${name}.txt] "Command: $command\n$output\nTcl status=$status; process status=$exitcode"
    require {$status == 0} "$name failed; see ${name}.txt: $exitcode"
    require {![regexp -nocase {(^|\n)[ \t]*(fatal|error)(:|[ \t])|FATAL_ERROR} $output]} "$name emitted fatal/error"
    return $output
}
proc check_sim {status output marker} {
    require {$status == 0} {Simulation process failed}
    require {[regexp -line -- "^${marker}( |$)" $output]} "Missing success marker: $marker"
    require {![regexp -nocase {(^|\n)[ \t]*(fatal|error)(:|[ \t])|FATAL_ERROR|\$fatal|\$error} $output]} {Simulation fatal/error}
}
proc stage_vectors {dir base c1} {
    global vectors
    file mkdir $dir
    if {$c1} {set files [glob [file join $base motor_control_ip foc tb vectors *.txt]]} else {
        set files {}; foreach v $vectors {lappend files [file join $base motor_control_ip foc tb vectors step6c2 $v]}
    }
    foreach f $files {source_exists $f; file copy $f $dir}
}
proc simulate {name top sources marker fragments {bad ""}} {
    global root scratch reports bin
    set dir [file join $scratch $name]; file mkdir $dir
    stage_vectors [file join $dir motor_control_ip foc tb vectors step6c2] $root 0
    stage_vectors [file join $dir motor_control_ip foc tb vectors] $root 1
    file copy [file join $root motor_control_ip foc rom sin_qw_4096x18.mem] $dir
    if {$bad ne ""} {
        set file [file join $dir motor_control_ip foc tb vectors step6c2 round_vectors.txt]
        set lines [split [string trimright [read_text $file]] \n]
        if {$bad eq "truncated"} {set lines [lrange $lines 0 end-1]} else {lset lines 1 "g[string range [lindex $lines 1] 1 end]"}
        write_text $file [join $lines \n]
    }
    cd $dir
    run_command ${name}_compile [list [file join $bin xvlog.bat] -sv {*}$sources]
    run_command ${name}_elaborate [list [file join $bin xelab.bat] $top -s sim]
    set command [list [file join $bin xsim.bat] sim -runall]
    set status [catch {exec {*}$command 2>@1} output options]
    write_text [file join $reports ${name}_simulate.txt] "Command: $command\n$output\nTcl status=$status; options=$options"
    cd $root
    check_sim $status $output $marker
    foreach fragment $fragments {require {[string first $fragment $output] >= 0} "$name count/profile mismatch: $fragment"}
    puts "C2_SIM_PASS $name"
    return $output
}
proc create_portable {} {
    global root rtl_names tb_names vectors xdc
    set dir [file join $root FOC_PI]
    if {[file isfile [file join $dir FOC_PI.xpr]]} {return}
    create_project FOC_PI $dir -part xc7a200tfbg484-2
    file mkdir [file dirname $xdc]
    write_text $xdc {create_clock -name sys_clk -period 20.000 [get_ports clk]}
    foreach n $rtl_names {add_files -norecurse [file join $root motor_control_ip foc rtl $n.sv]}
    foreach n $tb_names {add_files -fileset sim_1 -norecurse [file join $root motor_control_ip foc tb $n.sv]}
    foreach v $vectors {
        set f [file join $root motor_control_ip foc tb vectors step6c2 $v]
        add_files -fileset sim_1 -norecurse $f
        set_property file_type {Memory Initialization Files} [get_files $f]
        set_property used_in_synthesis false [get_files $f]
    }
    add_files -fileset constrs_1 -norecurse $xdc
    set_property top mc_pi_dq_core [get_filesets sources_1]
    set_property generic PI_PROFILE=0 [get_filesets sources_1]
    set_property top_auto_set 0 [get_filesets sources_1]
    set_property top mc_pi_dq_core_tb [get_filesets sim_1]
    set_property top_auto_set 0 [get_filesets sim_1]
    set_property xsim.simulate.runtime all [get_filesets sim_1]
    set_property -name xsim.simulate.xsim.more_options -value {-testplusarg "VECTOR_DIR=."} -objects [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    close_project
    set xp [file join $dir FOC_PI.xpr]
    set xml [read_text $xp]
    regsub {(<Project[^>]* Path=")[^"]+} $xml {\1$PPRDIR/FOC_PI.xpr} xml
    write_text $xp [string trimright $xml]
}
proc audit_portable {} {
    global root scratch reports rtl_names tb_names vectors
    set relocated [file join $scratch rel]
    foreach n $rtl_names {
        set dest [file join $relocated motor_control_ip foc rtl]; file mkdir $dest
        file copy [file join $root motor_control_ip foc rtl $n.sv] $dest
    }
    foreach n $tb_names {
        set dest [file join $relocated motor_control_ip foc tb]; file mkdir $dest
        file copy [file join $root motor_control_ip foc tb $n.sv] $dest
    }
    stage_vectors [file join $relocated motor_control_ip foc tb vectors step6c2] $root 0
    set proj [file join $relocated FOC_PI]; file mkdir $proj
    file copy [file join $root FOC_PI FOC_PI.xpr] $proj
    set dest [file join $proj FOC_PI.srcs constrs_1 new]; file mkdir $dest
    file copy [file join $root FOC_PI FOC_PI.srcs constrs_1 new foc_pi_clock.xdc] $dest
    open_project -read_only [file join $proj FOC_PI.xpr]
    require {[get_property PART [current_project]] eq "xc7a200tfbg484-2"} {Portable part}
    require {[get_property top [get_filesets sources_1]] eq "mc_pi_dq_core"} {Portable synthesis top}
    require {[get_property generic [get_filesets sources_1]] eq "PI_PROFILE=0"} {Portable profile}
    require {[get_property top [get_filesets sim_1]] eq "mc_pi_dq_core_tb"} {Portable simulation top}
    set audit "Actual relocated read-only open: $relocated\n"
    foreach {fs expected} [list sources_1 6 sim_1 15 constrs_1 1] {
        set files [get_files -of_objects [get_filesets $fs]]
        require {[llength $files] == $expected} "$fs inventory count"
        set expected_names {}
        if {$fs eq "sources_1"} {foreach n $rtl_names {lappend expected_names $n.sv}}
        if {$fs eq "sim_1"} {foreach n $tb_names {lappend expected_names $n.sv}; set expected_names [concat $expected_names $vectors]}
        if {$fs eq "constrs_1"} {set expected_names {foc_pi_clock.xdc}}
        set actual_names {}
        foreach f $files {
            set path [file normalize $f]
            require {[string first "$relocated/" $path] == 0 && [file isfile $path]} "Nonrelocated/missing source $path"
            lappend actual_names [file tail $path]
            set ft [get_property FILE_TYPE $f]
            if {[file extension $path] eq ".sv"} {require {$ft eq "SystemVerilog"} "Wrong SV type $f"}
            if {[file extension $path] eq ".txt"} {require {$ft eq "Memory Initialization Files"} "Wrong fixture type $f"}
            if {[file extension $path] eq ".xdc"} {require {$ft eq "XDC" && [string trim [read_text $path]] eq {create_clock -name sys_clk -period 20.000 [get_ports clk]}} {Wrong clock constraint}}
            append audit "$fs $ft $path\n"
        }
        require {[lsort $actual_names] eq [lsort $expected_names]} "$fs exact inventory"
    }
    set order [get_files -compile_order sources -used_in synthesis]
    require {[llength $order] == 6 && [file tail [lindex $order 0]] eq "mc_pi_fxp_pkg.sv"} {Package-first compile order}
    append audit "Synthesis compile order: $order\nSimulation compile order: [get_files -compile_order sources -used_in simulation]\n"
    append audit "Pre-launch simulator property: <[get_property xsim.simulate.xsim.more_options [get_filesets sim_1]]>\n"
    close_project
    open_project [file join $proj FOC_PI.xpr]
    launch_simulation -scripts_only
    set simdir [file join $proj FOC_PI.sim sim_1 behav xsim]
    foreach v $vectors {
        require {[file isfile [file join $simdir $v]] && [read_text [file join $simdir $v]] eq [read_text [file join $relocated motor_control_ip foc tb vectors step6c2 $v]]} "Actual simulation fixture staging failed: $v"
    }
    require {[string first {-testplusarg "VECTOR_DIR=."} [read_text [file join $simdir simulate.bat]]] >= 0} {Exported simulation command missing portable VECTOR_DIR}
    append audit "Actual exported scripts: $simdir\nAll 9 fixture bytes match staged external sources. Exported simulate.bat uses VECTOR_DIR=.\nPASS\n"
    write_text [file join $reports portable_audit.txt] $audit
    close_project
    # Execute exactly the exported portable project scripts in their real cwd.
    cd $simdir
    run_command portable_compile [list [file join $simdir compile.bat]]
    run_command portable_elaborate [list [file join $simdir elaborate.bat]]
    set output [run_command portable_simulate [list [file join $simdir simulate.bat]]]
    check_sim 0 $output {ALL STEP 6C2 PI DQ CORE TESTS PASSED}
    require {[string first {profile=0 accepted=2751 completed=2493 successful=2229 invalid_vdc=129 range=128 internal=7 aborted=258 latency=256} $output] >= 0} {Portable default core profile/count}
    cd $root
    puts C2_PORTABLE_PASS
}
proc resources {path} {
    set result "Actual primitive inventory; LUT counts logical primitives (packed utilization separately).\n"
    foreach {name filter} {DSP48E1 {REF_NAME == DSP48E1} RAMB36E1 {REF_NAME == RAMB36E1} RAMB18E1 {REF_NAME == RAMB18E1} LUT {REF_NAME =~ LUT*} FF {REF_NAME =~ FD*} LATCH {REF_NAME =~ LD*} BLACKBOX {IS_BLACKBOX == 1}} {
        set cells [get_cells -hier -quiet -filter $filter]
        append result "$name=[llength $cells]\n"
        if {$name in {LATCH BLACKBOX}} {require {[llength $cells] == 0} "$name found"}
    }
    write_text $path $result
}
proc profile_build {p sources} {
    global root scratch reports xdc
    set dir [file join $scratch p$p]
    set out [file join $reports profile$p]; file mkdir $out
    create_project p$p $dir -part xc7a200tfbg484-2
    add_files -norecurse $sources
    add_files -fileset constrs_1 -norecurse $xdc
    set_property top mc_pi_dq_core [get_filesets sources_1]
    set_property generic PI_PROFILE=$p [get_filesets sources_1]
    update_compile_order -fileset sources_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    foreach run {synth_1 impl_1} {
        if {$run eq "impl_1"} {launch_runs impl_1 -to_step route_design -jobs 4; wait_on_run impl_1}
        set expected [expr {$run eq "synth_1" ? "synth_design Complete!" : "route_design Complete!"}]
        set log [file join [get_property DIRECTORY [get_runs $run]] runme.log]
        if {[file isfile $log]} {file copy $log [file join $out ${run}_runme.txt]}
        require {[get_property STATUS [get_runs $run]] eq $expected && [get_property PROGRESS [get_runs $run]] eq "100%"} "Profile $p $run incomplete"
        open_run $run
        report_utilization -file [file join $out ${run}_utilization.rpt]
        report_utilization -hierarchical -file [file join $out ${run}_hierarchy.rpt]
        resources [file join $out ${run}_primitives.txt]
        if {$run eq "synth_1"} {close_design}
    }
    require {[llength [get_clocks]] == 1 && [get_property PERIOD [get_clocks sys_clk]] == 20.0} {Clock mismatch}
    report_clocks -file [file join $out clocks.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $out timing_summary.rpt]
    check_timing -verbose -file [file join $out check_timing.rpt]
    report_timing -delay_type max -max_paths 5 -file [file join $out setup_paths.rpt]
    report_timing -delay_type min -max_paths 5 -file [file join $out hold_paths.rpt]
    report_drc -file [file join $out drc.rpt]
    report_methodology -file [file join $out methodology.rpt]
    report_route_status -file [file join $out route_status.rpt]
    report_exceptions -file [file join $out exceptions.rpt]
    set route [read_text [file join $out route_status.rpt]]
    foreach {key var} {{# of routable nets} routable {# of fully routed nets} routed {# of nets with routing errors} route_errors} {
        require {[regexp [format {%s[. ]*:[ ]*([0-9]+)} $key] $route -> $var]} "Missing route count $key"
    }
    require {$routable > 0 && $routed == $routable && $route_errors == 0} {Incomplete route}
    set timing [read_text [file join $out timing_summary.rpt]]
    set header [string first {WNS(ns)} $timing]; require {$header >= 0} {Timing summary header missing}
    set table [string range $timing $header end]
    set num {[-+]?[0-9]+(?:\.[0-9]+)?}
    set pattern [format {(?m)^\s*(%s)\s+(%s)\s+([0-9]+)\s+([0-9]+)\s+(%s)\s+(%s)\s+([0-9]+)\s+([0-9]+)\s+(%s)\s+(%s)\s+([0-9]+)\s+([0-9]+)\s*$} $num $num $num $num $num $num]
    require {[regexp $pattern $table -> wns tns sf st whs ths hf ht wpws tpws pf pt]} {Cannot extract all setup/hold/pulse fields}
    set evidence "Profile=$p sys_clk=20.000\nWNS=$wns TNS=$tns setup_failing=$sf setup_total=$st\nWHS=$whs THS=$ths hold_failing=$hf hold_total=$ht\nWPWS=$wpws TPWS=$tpws pulse_failing=$pf pulse_total=$pt\nRoutable=$routable routed=$routed errors=$route_errors\n"
    foreach delay {max min} {
        set worst [get_timing_paths -delay_type $delay -max_paths 1]
        require {[llength $worst] == 1} {No timed raw path}
        set slack [get_property SLACK $worst]
        append evidence "$delay raw_SLACK=$slack STARTPOINT=[get_property STARTPOINT_PIN $worst] ENDPOINT=[get_property ENDPOINT_PIN $worst]\n"
        set raw_$delay $slack
    }
    write_text [file join $out gates.txt] $evidence
    set checks [read_text [file join $out check_timing.rpt]]
    foreach category {no_clock unconstrained_internal_endpoints loops latch_loops} {
        require {[regexp -- [format {checking %s \(([0-9]+)\)} $category] $checks -> count] && $count == 0} "Timing category failed $category"
    }
    set blockers {}; set findings "All DRC findings retained (no severity changes):\n"
    foreach violation [get_drc_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        append findings "$severity $violation\n"
        if {$severity in {Error {Critical Warning}} && ![regexp {^(UCIO-1|NSTD-1|CFGBVS-1)(#|$)} $violation]} {lappend blockers $violation}
    }
    write_text [file join $out drc_categories.txt] $findings
    require {[llength $blockers] == 0} "Non-board DRC blockers $blockers"
    require {$st > 0 && $ht > 0 && $pt > 0 && $wns >= 0 && $whs >= 0 && $wpws >= 0 && $tns == 0 && $ths == 0 && $tpws == 0 && $sf == 0 && $hf == 0 && $pf == 0 && $raw_max >= 0 && $raw_min >= 0} "Profile $p routed timing failed: $evidence"
    close_project
    puts "C2_PROFILE_${p}_PASS"
}
set status [catch {
    require {[version -short] eq "2026.1"} {Expected Vivado 2026.1}
    require {![file exists $scratch]} {Scratch already exists}
    file mkdir $scratch
    write_text [file join $reports provenance.txt] "Vivado=[version]\nPython=[exec python --version]\nTested code commit=[exec git rev-parse HEAD]\nBranch=[exec git branch --show-current]\nRun=$token\nScratch=$scratch\n"
    set sources {}; foreach n $rtl_names {set f [file join $root motor_control_ip foc rtl $n.sv]; source_exists $f; lappend sources $f}
    create_portable
    audit_portable
    foreach {name command} {
        python_unit {python scripts/step6c2_pi_reference_test.py}
        python_c2 {python scripts/step6c2_pi_reference.py --check}
        python_c1 {python scripts/step6c1_fixed_transform_reference.py --check}
        python_step6a {python scripts/reference_audit/verify_step6a_vectors.py}
    } {run_command $name $command}
    foreach flag {-O -OO} {
        foreach script {step6c2_pi_reference.py step6c2_pi_reference_test.py} {
            set code [catch {exec python $flag [file join scripts $script] --check 2>@1} output options]
            write_text [file join $reports optimized_${flag}_${script}.txt] "$output\nTcl status=$code; options=$options"
            require {$code != 0 && [string first {C2 rejects optimized Python} $output] >= 0} {Optimized acceptance bypass}
        }
    }
    foreach {name top tb marker fragments} {
        fxp mc_pi_fxp_tb mc_pi_fxp_tb {ALL STEP 6C2 FXP TESTS PASSED} {{round_rows=1101 range_rows=9}}
        sqrt mc_isqrt_u80_tb mc_isqrt_u80_tb {ALL STEP 6C2 ISQRT TESTS PASSED} {{fixture_rows=2078 transactions=6193 aborts=40 idle_clocks=5000}}
        div mc_udiv_u72_u41_tb mc_udiv_u72_u41_tb {ALL STEP 6C2 UDIV TESTS PASSED} {{fixture_rows=2058 transactions=4125 aborts=72 idle_clocks=5000}}
        eval0 mc_pi_dq_eval_p0_tb mc_pi_dq_eval_tb {ALL STEP 6C2 PI EVAL TESTS PASSED} {{profile=0 fixture_rows=521 total_fixture_rows=1042 directed=16 transactions=556 aborts=18 idle_clocks=5000}}
        eval1 mc_pi_dq_eval_p1_tb mc_pi_dq_eval_tb {ALL STEP 6C2 PI EVAL TESTS PASSED} {{profile=1 fixture_rows=521 total_fixture_rows=1042 directed=16 transactions=556 aborts=18 idle_clocks=5000}}
        limiter mc_dq_limiter_tb mc_dq_limiter_tb {ALL STEP 6C2 LIMITER TESTS PASSED} {{fixture_rows=4246 transactions=4287 errors=56} {aborts=160 latency=160 idle_clocks=5000}}
        core1 mc_pi_dq_core_p1_tb mc_pi_dq_core_tb {ALL STEP 6C2 PI DQ CORE TESTS PASSED} {{profile=1 accepted=2751 completed=2493 successful=2229 invalid_vdc=129 range=128 internal=7 aborted=258 latency=256}}
    } {simulate $name $top [concat $sources [list [file join $root motor_control_ip foc tb $tb.sv]]] $marker $fragments}
    set c1 {}; foreach n {mc_fxp_pkg mc_clarke mc_sincos_lut mc_park mc_inv_park mc_current_transform} {lappend c1 [file join $root motor_control_ip foc rtl $n.sv]}
    foreach {tb marker} {
        mc_clarke_tb {ALL STEP 6C1 CLARKE TESTS PASSED}
        mc_sincos_lut_tb {ALL STEP 6C1 SINCOS TESTS PASSED}
        mc_park_tb {ALL STEP 6C1 PARK TESTS PASSED}
        mc_current_transform_tb {ALL STEP 6C1 TRANSFORM TESTS PASSED}
    } {simulate $tb $tb [concat $c1 [list [file join $root motor_control_ip foc tb $tb.sv]]] $marker {}}
    simulate pwm motor_pwm_core_tb [list [file join $root motor_control_ip pwm rtl motor_pwm_core.sv] [file join $root motor_control_ip pwm tb motor_pwm_core_tb.sv]] {ALL STEP 6B MOTOR PWM TESTS PASSED} {}
    puts C2_REGRESSION_13_PASS
    foreach probe {malformed truncated missing_source failed_marker} {
        set state [file join $reports probe_${probe}_result.txt]
        write_text $state IN_PROGRESS
        set code [catch {
            switch $probe {
                malformed - truncated {simulate probe_$probe mc_pi_fxp_tb [concat $sources [list [file join $root motor_control_ip foc tb mc_pi_fxp_tb.sv]]] {ALL STEP 6C2 FXP TESTS PASSED} {} $probe}
                missing_source {source_exists [file join $scratch nonexistent.sv]}
                failed_marker {simulate probe_failed_marker mc_pi_fxp_tb [concat $sources [list [file join $root motor_control_ip foc tb mc_pi_fxp_tb.sv]]] {INTENTIONALLY ABSENT SUCCESS MARKER} {}}
            }
        } detail]
        if {$code} {write_text $state "FAILED\n$detail"}
        require {$code != 0 && [string match "FAILED*" [read_text $state]]} "Failure probe incorrectly passed $probe"
        if {$probe in {malformed truncated}} {
            set negative [read_text [file join $reports probe_${probe}_simulate.txt]]
            require {[string first {Fatal: PI_FXP_TB_FAIL} $negative] >= 0 && [string first FATAL_ERROR $negative] < 0} "Fixture probe must reject explicitly without native crash: $probe"
        }
    }
    # Independent builds: retain the other profile's evidence even when one fails.
    set failed {}
    foreach p {0 1} {
        if {[catch {profile_build $p $sources} detail options]} {
            write_text [file join $reports profile${p}_failure.txt] "$detail\n[dict get $options -errorinfo]"
            lappend failed $p
            catch {close_project}
        }
    }
    require {[llength $failed] == 0} "Failed profile(s): $failed"
    write_text [file join $reports build_result.txt] "PASS\nSTEP6C2_BUILD_PASS\nRun=$token\n13 simulations; Python checks; optimized rejection; portable execution; four failure probes; both profile routes PASS\nClock-only internal timing; external I/O and board constraints absent. No board timing sign-off, bitstream or hardware test."
    puts STEP6C2_BUILD_PASS
} detail options]
if {$status} {
    write_text [file join $reports build_result.txt] "FAILED\nRun=$token\n$detail\n[dict get $options -errorinfo]"
    puts stderr "STEP6C2_BUILD_FAILED: $detail"
}
catch {close_project}
exit [expr {$status ? 1 : 0}]
