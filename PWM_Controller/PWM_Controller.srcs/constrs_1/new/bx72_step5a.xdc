# Hardware evidence: coordination/reports/step5a_codex_report.md.
# Schematic p1/p4/p7, pin table Sheet1 rows 1/3/8, vendor io.xdc.
set_property PACKAGE_PIN Y18 [get_ports clk]
set_property PACKAGE_PIN V17 [get_ports key2_n]
set_property PACKAGE_PIN AA18 [get_ports led1]
set_property IOSTANDARD LVCMOS33 [get_ports {clk key2_n led1}]
create_clock -name sys_clk -period 20.000 [get_ports clk]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# KEY2 has no phase relationship to sys_clk. Only its asynchronous clear
# paths into the two reset-release flops are excepted. The synchronized
# reset's recovery/removal and stage-to-stage data path remain timed.
set_false_path -from [get_ports key2_n] -to [get_pins -hier -filter {NAME =~ *reset_release_reg*/CLR}]
# No invented external bus delays for a pushbutton and a human-visible LED.
