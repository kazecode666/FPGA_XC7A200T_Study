# Vivado 2026.1 batch entrypoint; route only, no bitstream/hardware or deletion.
# Reproduce: vivado -mode batch -nojournal -log .Xil/step6c1_build.log -source scripts/step6c1_foc_transforms_build.tcl
# All generated work is unique under .Xil; tracked XPR and accepted PWM remain read-only.
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set reports [file join $root docs reports step6c1]
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
    require {[regexp -line -- "^${marker}( |$)" $content]} "$tb did not report PASS"
    require {![regexp -nocase {(^|\n)[ \t]*(fatal|error)(:|[ \t])|\$fatal|\$error} $content]} "$tb reported a failure"
}
proc write_messages {status detail} {
    global reports run_names root
    set text "Step 6C1 execution: $status\nVivado: [version -short]\n$detail\n"
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
    # The documented command uses this driver log. Override via -tclargs <log>.
    set driver_log [file join $root .Xil step6c1_build.log]
    if {$::argc > 0} { set driver_log [file normalize [lindex $::argv 0]] }
    if {[file exists $driver_log]} {
        set counts [dict create ERROR 0 {CRITICAL WARNING} 0 WARNING 0]
        set messages {}
        foreach line [split [read_text $driver_log] \n] {
            if {[regexp {^(ERROR|CRITICAL WARNING|WARNING):} $line -> severity]} {
                dict incr counts $severity
                lappend messages $line
            }
        }
        write_text [file join $reports driver_warnings.txt] "Driver log $driver_log\nSnapshot before final close/exit; includes echoed child-run messages.\nAnchored severity counts: $counts\n[join [lsort -unique $messages] \n]"
    }
    append text "\nClock-only internal timing; no board I/O timing sign-off, bitstream or hardware test.\n"
    write_text [file join $reports messages.txt] $text
}

write_text [file join $reports build_result.txt] "STEP6C1_BUILD_IN_PROGRESS; not a PASS result"
set result [catch {
    require {[version -short] eq "2026.1"} "Expected Vivado 2026.1"
    foreach {name command} {
        step6a_python {python scripts/reference_audit/verify_step6a_vectors.py}
        reference_python {python scripts/step6c1_fixed_transform_reference.py --check}
    } {
        set code [catch {exec {*}$command 2>@1} output]
        write_text [file join $reports ${name}.txt] "$output\nExit status: $code"
        require {$code == 0} "$name failed: $output"
    }
    set code [catch {exec python -O scripts/step6c1_fixed_transform_reference.py --check 2>@1} output options]
    write_text [file join $reports reference_optimized_rejected.txt] "$output\nTcl status: $code\nError code: [dict get $options -errorcode]"
    require {$code != 0 && [string first {optimized Python disables acceptance assertions} $output] >= 0} "Optimized Python guard failed"
    # Parse XML without opening or saving the portable input project.
    set audit_code {
import sys, xml.etree.ElementTree as ET
from pathlib import Path
root=Path(sys.argv[1]); project=root/'FOC_Transforms'; xpr=project/'FOC_Transforms.xpr'
tree=ET.parse(xpr).getroot()
def check(ok, message):
    if not ok: raise RuntimeError(message)
check(tree.attrib['Path']=='$PPRDIR/FOC_Transforms.xpr','nonportable XPR root')
check(tree.find("./Configuration/Option[@Name='Part']").attrib['Val']=='xc7a200tfbg484-2','part')
rtl=['mc_fxp_pkg','mc_clarke','mc_park','mc_sincos_lut','mc_current_transform','mc_inv_park']
tbs=['mc_current_transform_tb','mc_clarke_tb','mc_sincos_lut_tb','mc_park_tb']
expected={'sources_1':[root/'motor_control_ip/foc/rtl'/f'{n}.sv' for n in rtl]+[root/'motor_control_ip/foc/rom/sin_qw_4096x18.mem'],
          'sim_1':[root/'motor_control_ip/foc/tb'/f'{n}.sv' for n in tbs],
          'constrs_1':[project/'FOC_Transforms.srcs/constrs_1/new/foc_transforms_clock.xdc']}
for name, paths in expected.items():
    fs=tree.find(f"./FileSets/FileSet[@Name='{name}']")
    files=fs.findall('File')
    actual=[Path(f.attrib['Path'].replace('$PPRDIR',str(project)).replace('$PSRCDIR',str(project/'FOC_Transforms.srcs'))).resolve() for f in files]
    check(len(actual)==len(paths) and set(actual)==set(p.resolve() for p in paths),name+' inventory')
    check(all(p.is_file() for p in actual),name+' missing file')
    for file in files:
        used={a.attrib['Val'] for a in file.findall("./FileInfo/Attr[@Name='UsedIn']")}
        check(('simulation' in used) if name=='sim_1' else ('synthesis' in used),name+' disabled source')
        if file.attrib['Path'].endswith('.mem'):
            check(file.find('FileInfo').attrib.get('SFType')=='MIF' and {'synthesis','simulation'}<=used,'ROM attributes')
    print(f'{name}: {len(actual)} exact external source paths verified')
check(tree.find("./FileSets/FileSet[@Name='sources_1']/Config/Option[@Name='TopModule']").attrib['Val']=='mc_current_transform','top')
check(tree.find("./FileSets/FileSet[@Name='sim_1']/Config/Option[@Name='TopModule']").attrib['Val']=='mc_current_transform_tb','simulation top')
print('PASS: portable XPR part/top/inventory/ROM attributes; clock text checked by Tcl')
    }
    set code [catch {exec python -c $audit_code $root 2>@1} output]
    write_text [file join $reports project_build_contract.txt] "$output\nExit status: $code"
    require {$code == 0} "XPR XML audit failed: $output"
    set token "[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]"
    set scratch [file join $root .Xil step6c1_$token]
    require {![file exists $scratch]} "Scratch already exists"
    create_project pwm_regression [file join $scratch pwm] -part xc7a200tfbg484-2
    add_source sources_1 [file join $root motor_control_ip pwm rtl motor_pwm_core.sv]
    add_source sim_1 [file join $root motor_control_ip pwm tb motor_pwm_core_tb.sv]
    simulate [file join $scratch pwm] pwm_regression motor_pwm_core_tb {ALL STEP 6B MOTOR PWM TESTS PASSED}
    close_project
    # Task6 separately audits XPR relocation. Read-only source inventory avoids
    # a Vivado native exit observed opening an XPR after closing XSim.
    require {[file isfile [file join $root FOC_Transforms FOC_Transforms.xpr]]} "Portable XPR missing"
    set design_files {}
    foreach name {mc_fxp_pkg mc_clarke mc_sincos_lut mc_park mc_inv_park mc_current_transform} {
        lappend design_files [file join $root motor_control_ip foc rtl ${name}.sv]
    }
    lappend design_files [file join $root motor_control_ip foc rom sin_qw_4096x18.mem]
    set tb_files [glob [file join $root motor_control_ip foc tb *.sv]]
    set constraint_files [list [file join $root FOC_Transforms FOC_Transforms.srcs constrs_1 new foc_transforms_clock.xdc]]
    require {[llength $tb_files] == 4} "TB source inventory mismatch"
    require {[string trim [read_text [lindex $constraint_files 0]]] eq {create_clock -name sys_clk -period 20.000 [get_ports clk]}} "Clock-only XDC changed"
    set project_dir [file join $scratch foc]
    create_project foc_build $project_dir -part xc7a200tfbg484-2
    foreach path $design_files { add_source sources_1 $path }
    foreach path $tb_files { add_source sim_1 $path }
    foreach path $constraint_files { add_source constrs_1 $path }
    set rom [get_files *sin_qw_4096x18.mem]
    set_property file_type {Memory Initialization Files} $rom
    set_property used_in_synthesis true $rom
    set_property used_in_simulation true $rom
    set_property top mc_current_transform [get_filesets sources_1]
    set_property top_auto_set 0 [get_filesets sources_1]
    update_compile_order -fileset sources_1
    set fixture_cwd [file join $project_dir foc_build.sim sim_1 behav xsim motor_control_ip foc tb vectors]
    file mkdir $fixture_cwd
    foreach path [glob [file join $root motor_control_ip foc tb vectors *.txt]] { file copy $path $fixture_cwd }
    foreach {tb marker} {
        mc_clarke_tb {ALL STEP 6C1 CLARKE TESTS PASSED}
        mc_sincos_lut_tb {ALL STEP 6C1 SINCOS TESTS PASSED}
        mc_park_tb {ALL STEP 6C1 PARK TESTS PASSED}
        mc_current_transform_tb {ALL STEP 6C1 TRANSFORM TESTS PASSED}
    } { simulate $project_dir foc_build $tb $marker }
    # Fresh uniquely named runs retain prior evidence without reset_run/cleanup.
    set synth step6c1_synth_$token
    set impl step6c1_impl_$token
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
    report_utilization -hierarchical -file [file join $reports synth_hierarchy.rpt]
    set resources "Synthesis cell inventory (actual inferred primitives):\nLUT below counts logical LUT primitive cells, not packed Slice LUTs; utilization reports give packed totals.\nMapping matches 6 DSP (2 Clarke + 4 Park) and 2 RAMB36 for 4096 x 18 dual-read ROM; no deviation.\n"
    foreach {label filter} {DSP48E1 {REF_NAME == DSP48E1} RAMB36E1 {REF_NAME == RAMB36E1} RAMB18E1 {REF_NAME == RAMB18E1} LUT {REF_NAME =~ LUT*} FF {REF_NAME =~ FD*} LATCH {REF_NAME =~ LD*}} {
        set cells [get_cells -hier -quiet -filter $filter]
        append resources "$label=[llength $cells]\n"
        if {$label in {DSP48E1 RAMB36E1 RAMB18E1}} {
            foreach cell $cells { append resources "  $cell\n" }
        }
    }
    set brams [get_cells -hier -filter {REF_NAME == RAMB36E1}]
    foreach cell $brams {
        set initialized 0
        foreach property [list_property $cell] {
            if {[regexp {^INIT_[0-9A-F]+$} $property]} {
                set value [get_property $property $cell]
                append resources "$cell $property=$value\n"
                if {[regexp {[1-9a-fA-F]} [lindex [split $value h] end]]} { set initialized 1 }
            }
        }
        require {$initialized} "ROM has no nonzero INIT data: $cell"
    }
    write_text [file join $reports resource_audit.txt] $resources
    require {[llength [get_cells -hier -filter {REF_NAME == DSP48E1}]] == 6 && [llength $brams] == 2} "Resource mapping differs from 6 DSP / 2 RAMB36; inspect hierarchy before accepting"
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
    # Route completeness gate, also independently exercised on the saved report.
    set route_text [read_text [file join $reports route_status.rpt]]
    require {[regexp {# of routable nets[. ]*:[ ]*([0-9]+)} $route_text -> routable]} "Missing routable-net count"
    require {[regexp {# of fully routed nets[. ]*:[ ]*([0-9]+)} $route_text -> routed]} "Missing fully-routed count"
    require {[regexp {# of nets with routing errors[. ]*:[ ]*([0-9]+)} $route_text -> route_errors]} "Missing routing-error count"
    require {$routable > 0 && $routed == $routable && $route_errors == 0} "Incomplete routing"
    write_text [file join $reports route_gate.txt] "PASS: routable=$routable fully_routed=$routed routing_errors=$route_errors"
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
    set paths "Unrounded routed path properties:\n"
    foreach delay {max min} {
        set worst [get_timing_paths -delay_type $delay -max_paths 1]
        append paths "$delay SLACK=[get_property SLACK $worst] STARTPOINT=[get_property STARTPOINT_PIN $worst] ENDPOINT=[get_property ENDPOINT_PIN $worst]\n"
    }
    write_text [file join $reports worst_paths.txt] $paths
    set checks [read_text [file join $reports check_timing.rpt]]
    foreach category {no_clock unconstrained_internal_endpoints loops latch_loops} {
        require {[regexp -- [format {checking %s \(([0-9]+)\)} $category] $checks -> count] && $count == 0} "Timing category failed: $category"
    }
    # Pin/voltage DRCs are expected for an intentionally clock-only portable core.
    set blockers {}
    foreach violation [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}] {
        if {![regexp {^(UCIO-1|NSTD-1|CFGBVS-1)(#|$)} $violation]} { lappend blockers $violation }
    }
    require {[llength $blockers] == 0} "Blocking non-board DRCs: $blockers"
    write_messages PASS "WNS=$wns TNS=$tns WHS=$whs THS=$ths"
    write_text [file join $reports build_result.txt] "STEP6C1_BUILD_PASS\nVivado: [version -short]\nPart: xc7a200tfbg484-2\nTop: mc_current_transform; sys_clk=20.000 ns (50 MHz)\nFour FOC simulations, unchanged Step6B PWM simulation, Step6A Python and C1 Python --check: PASS\nOptimized Python acceptance bypass: rejected\nDSP48E1=6 RAMB36E1=2 latches=0; initialized ROM verified\nSynthesis: [get_property STATUS [get_runs $synth]]\nImplementation: [get_property STATUS [get_runs $impl]]\nWNS=$wns ns TNS=$tns ns WHS=$whs ns THS=$ths ns\n$paths\nInternal timing categories: no_clock=0 unconstrained_internal_endpoints=0 loops=0 latch_loops=0\nBoard pins/IOSTANDARD/I/O delays absent; retained DRC warnings, no board timing sign-off\nNo bitstream generated; no physical hardware test"
    puts "STEP6C1_BUILD_PASS WNS=$wns TNS=$tns WHS=$whs THS=$ths"
} detail options]
if {$result} {
    catch {write_messages FAIL $detail}
    write_text [file join $reports build_result.txt] "STEP6C1_BUILD_FAILED: $detail"
    puts stderr "STEP6C1_BUILD_FAILED: $detail\n[dict get $options -errorinfo]"
}
catch {close_project}
exit [expr {$result ? 1 : 0}]
