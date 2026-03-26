# Minimal timing constraint for core-level synthesis/implementation.
# Replace this with board pin constraints when you switch to the FPGA wrapper top.
create_clock -name clk -period 10.000 [get_ports clk]
