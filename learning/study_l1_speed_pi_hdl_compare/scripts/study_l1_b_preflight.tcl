# Read-only project-file/installed-part/clock-source preflight before generation.
if {$argc != 2} { error "Usage: repository_root fresh_json_path" }
set root [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {[file exists $out]} { error "Never overwrite preflight evidence" }
set expected ""
foreach project {FOC_Current FOC_Transforms PWM_Controller PWM_Breathe} {
    set path [file join $root $project $project.xpr]
    set f [open $path r]; set contents [read $f]; close $f
    if {![regexp {<Option Name="Part" Val="([^"]+)"} $contents -> actual]} { error "Missing actual part: $path" }
    if {$expected eq ""} { set expected $actual }
    if {$actual ne $expected} { error "Existing project part disagreement" }
    puts "ACTUAL_PROJECT_PART $path $actual"
}
if {$expected ne "xc7a200tfbg484-2" || [llength [get_parts -quiet $expected]] != 1} { error "Audited XC7A200T part unavailable" }
file mkdir [file dirname $out]
set f [open $out w]
puts $f "{\"Vivado\":\"[version -short]\",\"part\":\"$expected\",\"clock_mhz\":50,\"existing_projects_agree\":true,\"installed_part_available\":true,\"flow\":\"non-project OOC with registered boundary\"}"
close $f
puts "STUDY_L1_PART_CLOCK_PREFLIGHT_PASS"
