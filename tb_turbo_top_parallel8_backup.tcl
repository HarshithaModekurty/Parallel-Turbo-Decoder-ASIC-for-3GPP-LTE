if {[string length [current_wave_config]] == 0} {
  create_wave_config
}

add_wave /tb_turbo_top_parallel8_backup/clk
add_wave /tb_turbo_top_parallel8_backup/rst
add_wave /tb_turbo_top_parallel8_backup/start
add_wave /tb_turbo_top_parallel8_backup/in_valid
add_wave /tb_turbo_top_parallel8_backup/in_idx
add_wave /tb_turbo_top_parallel8_backup/ls
add_wave /tb_turbo_top_parallel8_backup/lp1
add_wave /tb_turbo_top_parallel8_backup/lp2
add_wave /tb_turbo_top_parallel8_backup/n_half_iter
add_wave /tb_turbo_top_parallel8_backup/k_len
add_wave /tb_turbo_top_parallel8_backup/f1
add_wave /tb_turbo_top_parallel8_backup/f2
add_wave /tb_turbo_top_parallel8_backup/out_valid
add_wave /tb_turbo_top_parallel8_backup/out_idx
add_wave /tb_turbo_top_parallel8_backup/post
add_wave /tb_turbo_top_parallel8_backup/done

run all
