# 50 MHz system clock; external I/O timing and board pins are not defined yet.
create_clock -name sys_clk -period 20.000 [get_ports clk]
