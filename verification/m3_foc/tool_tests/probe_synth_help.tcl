puts [help read_verilog]
puts [help synth_design]
set file [open [file join [file dirname [info script]] .. .. .. scripts m3_synth_foc_ooc.tcl] r]
set text [read $file]; close $file
if {![info complete $text]} { error "M3 OOC Tcl is not a complete script" }
puts "M3_OOC_TCL_PARSE_PASS no_synthesis_run"
exit 0
