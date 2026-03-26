read_vhdl -vhdl2008 rtl/turbo_pkg.vhd
read_vhdl -vhdl2008 rtl/fpga_smoke_vectors_pkg.vhd
read_vhdl -vhdl2008 rtl/simple_dp_bram.vhd
read_vhdl -vhdl2008 rtl/siso_maxlogmap.vhd
read_vhdl -vhdl2008 rtl/turbo_decoder_top.vhd
read_vhdl -vhdl2008 rtl/turbo_decoder_zybo_smoke_top.vhd
read_xdc constraints/turbo_decoder_zybo_smoke_top.xdc
synth_design -top turbo_decoder_zybo_smoke_top -part xc7z010clg400-1
report_utilization -file utilization_zybo_smoke_tmp.txt
exit
