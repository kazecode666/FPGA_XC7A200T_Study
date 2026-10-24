# Non-project core-only synthesis. Invoke through m3_run_xsim.ps1 -Mode synth.
# The wrapper validates source/staged SHA256s and emits a data-only manifest.
proc m3_json_string {value} {
    set value [string map [list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"] $value]
    return "\"${value}\""
}
proc m3_bool {value} { if {$value} { return true }; return false }
proc m3_util {text labels} {
    foreach label $labels {
        foreach line [split $text "\n"] {
            set cells [split $line |]
            if {[llength $cells] < 3} { continue }
            set name [string trim [lindex $cells 1] " \t*"]
            if {$name eq $label} {
                set number [string map {, ""} [string trim [lindex $cells 2]]]
                if {[string is double -strict $number]} { return $number }
            }
        }
    }
    error "Utilization row absent: $labels"
}
if {[llength $argv] != 2} { error "Usage: m3_synth_foc_ooc.tcl manifest_ooc.tcl new_output_dir" }
set config [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set checkout [file normalize [file join [file dirname [info script]] ..]]
set allowed [string tolower [file normalize [file join $checkout .runtime]]]
if {![string match "${allowed}/*" [string tolower $out]]} { error "OOC output must be in this checkout .runtime" }
if {![file isfile $config]} { error "M3 OOC manifest missing" }
if {[file exists $out]} { error "M3 OOC output exists; preserving prior evidence" }
source $config
foreach key {m3_root m3_top m3_clock_port m3_part m3_clock_period_ns m3_design_files m3_hashes_verified m3_manifest_sha256} {
    if {![info exists $key]} { error "M3 OOC manifest lacks $key" }
}
if {$m3_hashes_verified != 1} { error "Use the SHA256-validating PowerShell wrapper" }
if {![info exists m3_include_dirs]} { set m3_include_dirs {} }
if {![info exists m3_defines]} { set m3_defines {} }
if {$m3_part ne "xc7a200tfbg484-2" || $m3_clock_period_ns != 20} { error "Unexpected M3 part/clock contract" }
foreach value [list $m3_top $m3_clock_port] { if {![regexp {^[A-Za-z_][A-Za-z0-9_$]*$} $value]} { error "Invalid HDL identifier" } }
if {[llength $m3_design_files] == 0} { error "No design RTL in manifest" }
foreach path $m3_design_files { if {![file isfile $path]} { error "Design RTL missing: $path" } }
file mkdir $out
cd $m3_root
set completed 0; set resources_ok 0; set timing_ok 0; set message ""
set lut -1; set ff -1; set dsp -1; set bram -1; set wns null; set whs null
set no_clock -1; set unconstrained_internal -1; set loops -1; set latch_loops -1
set latch -1; set blackbox -1; set cell_count 0
set part_obj [get_parts -quiet $m3_part]
if {[llength $part_obj] != 1} { error "Requested part is not installed" }
set lut_capacity [get_property LUT_ELEMENTS $part_obj]
set ff_capacity [get_property FLIPFLOPS $part_obj]
set dsp_capacity [get_property DSP $part_obj]
set bram_capacity [get_property BLOCK_RAMS $part_obj]
set failure [catch {
    set_param general.maxThreads 4
    foreach path $m3_design_files { read_verilog -sv $path }
    set xdc [file join $out m3_core_clock.xdc]
    set handle [open $xdc w]
    puts $handle "create_clock -name m3_core_clk -period 20.000 \[get_ports {$m3_clock_port}\]"
    close $handle
    read_xdc $xdc
    # No input constants, IO buffers, placement, routing, bitstream or board pins.
    set synth_args [list -top $m3_top -part $m3_part -mode out_of_context -flatten_hierarchy none]
    if {[llength $m3_include_dirs] > 0} { lappend synth_args -include_dirs $m3_include_dirs }
    foreach macro $m3_defines { lappend synth_args -verilog_define $macro }
    synth_design {*}$synth_args
    set completed 1
} message]
if {$failure} { puts "M3_OOC_SYNTH_DIAGNOSTIC $message" }
if {[llength [get_designs -quiet]] > 0} {
    if {[catch {
        set clock_port [get_ports -quiet $m3_clock_port]
        if {[llength $clock_port] != 1 || [get_property DIRECTION $clock_port] ne "IN"} { error "HDL clock port absent/not a scalar input" }
        set clocks [get_clocks -quiet -of_objects $clock_port]
        if {[llength $clocks] != 1 || abs([get_property PERIOD $clocks]-20.0) > 1e-9} { error "Actual clock constraint is not 20ns" }
        report_clocks -file [file join $out clocks.rpt]
        report_utilization -hierarchical -file [file join $out utilization_hierarchical.rpt]
        report_utilization -file [file join $out utilization.rpt]
        report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
        check_timing -verbose -file [file join $out check_timing.rpt]
        report_drc -file [file join $out drc.rpt]
        set handle [open [file join $out utilization.rpt] r]; set utilization [read $handle]; close $handle
        set lut [m3_util $utilization {{Slice LUTs} {CLB LUTs}}]
        set ff [m3_util $utilization {{Slice Registers} {CLB Registers}}]
        set dsp [m3_util $utilization {DSPs}]
        set bram [m3_util $utilization {{Block RAM Tile}}]
        set cell_count [llength [get_cells -hierarchical -quiet]]
        set latch [llength [get_cells -hierarchical -quiet -filter {IS_PRIMITIVE == 1 && REF_NAME =~ LD*}]]
        set blackbox [llength [get_cells -hierarchical -quiet -filter {IS_BLACKBOX == 1}]]
        set handle [open [file join $out check_timing.rpt] r]; set checks [read $handle]; close $handle
        if {![regexp -nocase {checking no_clock\s*\(([0-9]+)\)} $checks ignored no_clock]} { error "Could not classify no_clock diagnostic" }
        foreach {category variable} {unconstrained_internal_endpoints unconstrained_internal loops loops latch_loops latch_loops} {
            if {![regexp -nocase [format {checking %s\s*\(([0-9]+)\)} $category] $checks ignored $variable]} { error "Could not classify $category diagnostic" }
        }
        set setup [get_timing_paths -quiet -delay_type max -max_paths 1 -nworst 1]
        set hold [get_timing_paths -quiet -delay_type min -max_paths 1 -nworst 1]
        if {[llength $setup] != 1 || [llength $hold] != 1} { error "No valid sequential timing path; cannot claim timing" }
        set wns [get_property SLACK $setup]; set whs [get_property SLACK $hold]
        set resources_ok [expr {$cell_count > 0 && $ff > 0 && ($lut+$dsp) > 0 && $lut <= $lut_capacity && $ff <= $ff_capacity && $dsp <= $dsp_capacity && $bram <= $bram_capacity && $latch == 0 && $blackbox == 0}]
        set timing_ok [expr {$wns >= 0 && $whs >= 0 && $no_clock == 0 && $unconstrained_internal == 0 && $loops == 0 && $latch_loops == 0}]
        write_checkpoint [file join $out post_synth.dcp]
    } report_error]} {
        set message "$message; report/contract failure: $report_error"
        set timing_ok 0
        puts "M3_OOC_REPORT_DIAGNOSTIC $report_error"
    }
}
set result [format {
{
  "stage": "core_ooc_synthesis",
  "completed": %s,
  "resources_ok": %s,
  "timing_ok": %s,
  "part": "xc7a200tfbg484-2",
  "clock_period_ns": 20,
  "manifest_sha256": %s,
  "top": %s,
  "clock_port": %s,
  "used": {"LUT": %s, "FF": %s, "DSP": %s, "BRAM36_equivalent": %s},
  "capacity": {"LUT": %s, "FF": %s, "DSP": %s, "BRAM36_equivalent": %s},
  "worst_setup_slack_ns": %s,
  "worst_hold_slack_ns": %s,
  "no_clock_checks": %s,
  "unconstrained_internal_endpoints": %s,
  "combinational_loops": %s,
  "latch_loops": %s,
  "latches": %s,
  "blackboxes": %s,
  "hierarchical_cells": %s,
  "external_input_output_timing_signed_off": false,
  "place_route_or_bitstream_run": false,
  "diagnostic": %s
}
} [m3_bool $completed] [m3_bool $resources_ok] [m3_bool $timing_ok] [m3_json_string $m3_manifest_sha256] [m3_json_string $m3_top] [m3_json_string $m3_clock_port] $lut $ff $dsp $bram $lut_capacity $ff_capacity $dsp_capacity $bram_capacity $wns $whs $no_clock $unconstrained_internal $loops $latch_loops $latch $blackbox $cell_count [m3_json_string $message]]
set handle [open [file join $out ooc_result.json] w]; puts $handle $result; close $handle
puts "M3_OOC_RESULT completed=$completed resources_ok=$resources_ok timing_ok=$timing_ok output=$out"
# The wrapper consumes this verdict and returns nonzero for failed checks.
# A diagnostic result can still preserve real resources after a synthesis failure.
exit 0
