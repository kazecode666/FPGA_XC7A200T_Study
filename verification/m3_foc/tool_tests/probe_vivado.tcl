puts "M3_TOOL_VERSION [version -short]"
set part [get_parts -quiet xc7a200tfbg484-2]
if {[llength $part] != 1} { error "M3 requested part is not installed" }
report_property $part
puts "M3_LICENSE_COMMANDS [info commands *license*]"
puts "M3_TOOL_PROBE_PASS no_design_opened no_synthesis_run"
exit 0
