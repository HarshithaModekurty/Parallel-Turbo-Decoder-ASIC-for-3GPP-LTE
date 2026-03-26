read_vhdl -vhdl2008 rtl/turbo_pkg.vhd
read_vhdl -vhdl2008 rtl/simple_dp_bram.vhd
read_vhdl -vhdl2008 rtl/siso_maxlogmap.vhd
read_vhdl -vhdl2008 rtl/turbo_decoder_top.vhd
read_xdc constraints/turbo_decoder_top_clock_only.xdc
synth_design -top turbo_decoder_top -part xc7z010clg400-1
opt_design
place_design
route_design
report_utilization -file implementation_utilization_qpprec_tmp.txt
report_timing_summary -file implementation_timing_qpprec_tmp.txt
exit
