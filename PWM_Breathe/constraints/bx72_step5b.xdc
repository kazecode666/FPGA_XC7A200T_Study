# Frozen, physically verified Step 5A facts: coordination/HANDOFF.md.
set_property PACKAGE_PIN Y18 [get_ports clk]
set_property PACKAGE_PIN V17 [get_ports key2_n]
set_property PACKAGE_PIN AA18 [get_ports led1]
set_property IOSTANDARD LVCMOS33 [get_ports {clk key2_n led1}]
create_clock -name sys_clk -period 20.000 [get_ports clk]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Only the external asynchronous reset entry is excepted. Stage-to-stage data
# and synchronized reset recovery/removal paths remain timed.
set_false_path -from [get_ports key2_n] -to [get_pins -of_objects [get_cells -hier -filter {NAME =~ reset_release_reg*}] -filter {REF_PIN_NAME == CLR}]
# KEY2 and LED1 are human-interface GPIO, not a synchronous external bus.
