# OOC IP interface budget: 2 ns on each synchronous input/output.
# No multicycle/false paths; every hardware path must meet the 20 ns clock.
create_clock -name clk_50mhz -period 20.000 [get_ports clk]
set_input_delay -clock clk_50mhz 2.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk_50mhz 2.000 [all_outputs]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
