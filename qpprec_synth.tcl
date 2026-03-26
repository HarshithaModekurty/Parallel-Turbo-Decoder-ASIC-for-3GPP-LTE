read_vhdl -vhdl2008 rtl/turbo_pkg.vhd
read_vhdl -vhdl2008 rtl/simple_dp_bram.vhd
read_vhdl -vhdl2008 rtl/siso_maxlogmap.vhd
read_vhdl -vhdl2008 rtl/turbo_decoder_top.vhd
synth_design -top turbo_decoder_top -part xc7z010clg400-1
report_utilization -file utilization_qpprec_tmp.txt
report_utilization -hierarchical -file utilization_hier_qpprec_tmp.txt
exit
