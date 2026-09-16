# vivado -mode batch -nojournal -log <local-log> -source scripts/step5a_bx72_build.tcl
# Audit gate evidence is recorded in coordination/reports/step5a_codex_report.md.
# No hardware programming; no Step 5B. Existing Step 4 runs are retained.
set root [file normalize [file join [file dirname [info script]] ..]]
set reports [file join $root docs reports step5a]
file mkdir $reports
open_project [file join $root PWM_Controller PWM_Controller.xpr]

proc require {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc require_run {name status} {
    require {[get_property STATUS [get_runs $name]] eq $status} "$name failed/incomplete"
    require {[get_property PROGRESS [get_runs $name]] eq "100%"} "$name progress incomplete"
}

set result [catch {
    require {[version -short] eq "2026.1"} "Expected Vivado 2026.1"
    require {[get_property PART [current_project]] eq "xc7a200tfbg484-2"} "Wrong FPGA part"
    set src [file join $root PWM_Controller PWM_Controller.srcs]
    foreach {fileset relative} {sources_1 sources_1/new/pwm_demo_top.sv sim_1 sim_1/new/pwm_demo_top_tb.sv} {
        set path [file join $src $relative]
        if {[llength [get_files -quiet -of_objects [get_filesets $fileset] $path]] == 0} {
            add_files -fileset $fileset -norecurse $path
        }
    }
    if {[llength [get_filesets -quiet constrs_step5a]] == 0} {
        create_fileset -constrset constrs_step5a
    }
    set path [file join $src constrs_1 new bx72_step5a.xdc]
    if {[llength [get_files -quiet -of_objects [get_filesets constrs_step5a] $path]] == 0} {
        add_files -fileset constrs_step5a -norecurse $path
    }
    set_property top pwm_demo_top [get_filesets sources_1]
    set_property top_auto_set 0 [get_filesets sources_1]
    update_compile_order -fileset sources_1
    foreach {tb marker} {
        pwm_controller_tb {ALL STEP 2.5 PWM TESTS PASSED}
        pwm_demo_top_tb {ALL STEP 5A BOARD TESTS PASSED}
    } {
        set_property top $tb [get_filesets sim_1]
        set_property top_auto_set 0 [get_filesets sim_1]
        set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
        update_compile_order -fileset sim_1
        launch_simulation -simset sim_1 -mode behavioral
        run all
        close_sim
        set simlog [file join $root PWM_Controller PWM_Controller.sim sim_1 behav xsim simulate.log]
        set f [open $simlog r]; set content [read $f]; close $f
        set f [open [file join $reports ${tb}.txt] w]; puts $f $content; close $f
        require {[string first $marker $content] >= 0} "$tb did not report PASS"
        require {![regexp {Fatal:|FATAL|ERROR:} $content]} "$tb reported a failure"
    }
    if {[llength [get_runs -quiet step5a_synth]] == 0} {
        create_run step5a_synth -flow {Vivado Synthesis 2026} -strategy {Vivado Synthesis Defaults} -constrset constrs_step5a
    }
    if {[llength [get_runs -quiet step5a_impl]] == 0} {
        create_run step5a_impl -parent_run step5a_synth -flow {Vivado Implementation 2026} -strategy {Vivado Implementation Defaults} -constrset constrs_step5a
    }
    current_run -synthesis [get_runs step5a_synth]
    current_run -implementation [get_runs step5a_impl]
    reset_run step5a_synth
    launch_runs step5a_synth -jobs 4
    wait_on_run step5a_synth
    require_run step5a_synth {synth_design Complete!}
    open_run step5a_synth
    report_utilization -file [file join $reports synthesis_utilization.rpt]
    close_design
    launch_runs step5a_impl -to_step route_design -jobs 4
    wait_on_run step5a_impl
    require_run step5a_impl {route_design Complete!}
    open_run step5a_impl
    require {[llength [get_clocks]] == 1 && [get_property PERIOD [get_clocks sys_clk]] == 20.0} "Clock audit mismatch"
    foreach {port pin} {clk Y18 key2_n V17 led1 AA18} {
        require {[get_property PACKAGE_PIN [get_ports $port]] eq $pin} "Wrong pin for $port"
        require {[get_property IOSTANDARD [get_ports $port]] eq "LVCMOS33"} "Wrong voltage for $port"
    }
    require {[llength [get_ports]] == 3} "Unexpected board ports"
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $reports timing_summary.rpt]
    report_timing -delay_type max -max_paths 5 -file [file join $reports setup_paths.rpt]
    report_timing -delay_type min -max_paths 5 -file [file join $reports hold_paths.rpt]
    report_drc -file [file join $reports drc.rpt]
    report_methodology -file [file join $reports methodology.rpt]
    report_utilization -file [file join $reports implementation_utilization.rpt]
    report_io -file [file join $reports io.rpt]
    report_cdc -file [file join $reports cdc.rpt]
    report_exceptions -file [file join $reports exceptions.rpt]
    report_route_status -file [file join $reports route_status.rpt]
    set sync_clears [get_pins -hier -filter {NAME =~ *reset_release_reg*/CLR}]
    require {[llength $sync_clears] == 2} "Reset exception must target exactly two synchronizer CLR pins"
    set f [open [file join $reports board_properties.txt] w]
    puts $f "TOP=[get_property TOP [get_filesets sources_1]] PART=[get_property PART [current_project]]"
    puts $f "CFGBVS=[get_property CFGBVS [current_design]] CONFIG_VOLTAGE=[get_property CONFIG_VOLTAGE [current_design]]"
    foreach p {clk key2_n led1} { puts $f "$p PIN=[get_property PACKAGE_PIN [get_ports $p]] IOSTANDARD=[get_property IOSTANDARD [get_ports $p]]" }
    foreach c [get_cells -hier -filter {NAME =~ *reset_release_reg*}] {
        puts $f "$c TYPE=[get_property REF_NAME $c] INIT=[get_property INIT $c] ASYNC_REG=[get_property ASYNC_REG $c] LOC=[get_property LOC $c]"
    }
    puts $f "EXTERNAL_RESET_EXCEPTION_ENDPOINTS=$sync_clears"
    close $f
    foreach delay {max min} {
        set worst [get_timing_paths -delay_type $delay -max_paths 1]
        require {[llength $worst] == 1 && [get_property SLACK $worst] >= 0} "Internal $delay timing failed"
    }
    set blocking [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}]
    require {[llength $blocking] == 0} "Blocking DRCs: $blocking"
    close_design
    launch_runs step5a_impl -to_step write_bitstream -jobs 4
    wait_on_run step5a_impl
    require_run step5a_impl {write_bitstream Complete!}
    set bit [file join [get_property DIRECTORY [get_runs step5a_impl]] pwm_demo_top.bit]
    require {[file exists $bit] && [file size $bit] > 0} "Bitstream missing"
    set f [open [file join $reports build_result.txt] w]
    puts $f "STEP5A_BUILD_PASS\nVivado: [version -short]\nPart: [get_property PART [current_project]]\nBitstream: $bit\nPhysical hardware: NOT TESTED"
    foreach r {step5a_synth step5a_impl} { puts $f "$r: [get_property STATUS [get_runs $r]]" }
    close $f
    puts "STEP5A_BUILD_PASS BITSTREAM=$bit"
} detail options]
close_project
if {$result} { puts stderr "STEP5A_BUILD_FAILED: $detail\n[dict get $options -errorinfo]"; exit 1 }
exit 0
