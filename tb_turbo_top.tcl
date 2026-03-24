if {[string length [current_wave_config]] == 0} {
  create_wave_config
}

add_wave /tb_turbo_top/clk
add_wave /tb_turbo_top/rst
add_wave /tb_turbo_top/start
add_wave /tb_turbo_top/in_valid
add_wave /tb_turbo_top/in_idx
add_wave /tb_turbo_top/ls
add_wave /tb_turbo_top/lp1
add_wave /tb_turbo_top/lp2
add_wave /tb_turbo_top/n_half_iter
add_wave /tb_turbo_top/k_len
add_wave /tb_turbo_top/f1
add_wave /tb_turbo_top/f2
add_wave /tb_turbo_top/out_valid
add_wave /tb_turbo_top/out_idx
add_wave /tb_turbo_top/post
add_wave /tb_turbo_top/done

run all
