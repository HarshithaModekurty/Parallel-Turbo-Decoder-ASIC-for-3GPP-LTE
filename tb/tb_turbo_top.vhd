library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;
use std.textio.all;
use std.env.all;

entity tb_turbo_top is end;
architecture sim of tb_turbo_top is
  constant C_K_MAX : natural := 6144;
  type int_mem_t is array (0 to C_K_MAX-1) of integer;

  signal clk,rst,start,in_valid,out_valid,done : std_logic := '0';
  signal n_iter : unsigned(3 downto 0) := (others=>'0');
  signal k_len,f1,f2,in_idx,out_idx : unsigned(12 downto 0) := (others=>'0');
  signal ls,lp1,lp2,post : llr_t := (others=>'0');
  file vec_f : text open read_mode is "sim_vectors/lte_frame_input_vectors.txt";
  file io_trace_f : text open write_mode is "tb_turbo_top_io_trace.txt";
  file report_f : text open write_mode is "tb_turbo_top_report.txt";
begin
  dut: entity work.turbo_decoder_top
    port map(clk=>clk,rst=>rst,start=>start,n_iter=>n_iter,k_len=>k_len,f1=>f1,f2=>f2,
      in_valid=>in_valid,in_idx=>in_idx,l_sys_in=>ls,l_par1_in=>lp1,l_par2_in=>lp2,
      out_valid=>out_valid,out_idx=>out_idx,l_post=>post,done=>done);

  clk <= not clk after 5 ns;
  process
    variable out_cnt : integer := 0;
    variable l : line;
    variable l_in : line;
    variable bit_orig_mem : int_mem_t := (others => 0);
    variable bit_int_mem  : int_mem_t := (others => 0);
    variable lsys_mem : int_mem_t := (others => 0);
    variable lpar1_mem : int_mem_t := (others => 0);
    variable lpar2_mem : int_mem_t := (others => 0);
    variable seen_mem : int_mem_t := (others => 0);
    variable final_seen_mem : int_mem_t := (others => 0);
    variable final_llr_mem : int_mem_t := (others => 0);
    variable final_hd_mem : int_mem_t := (others => 0);
    variable bit_orig_v, bit_int_v, lsys_v, lpar1_v, lpar2_v : integer;
    variable idx_v, pass_v, llr_v, hard_v, pi_v : integer;
    variable vec_idx, vec_k, vec_iter, vec_f1, vec_f2 : integer;
    variable n_sym, n_iter_i, final_seen_cnt, err_cnt_int, err_cnt_orig_pi : integer;
  begin
    write(l, string'("# turbo_top IO trace"));
    writeline(io_trace_f, l);
    write(l, string'("# Input format : IN idx bit_orig bit_int l_sys_orig l_par1_orig l_par2_int"));
    writeline(io_trace_f, l);
    write(l, string'("# Output format: OUT seq idx_int pass bit_int bit_orig_pi l_sys_orig l_par1_orig l_par2_int l_post hard"));
    writeline(io_trace_f, l);

    readline(vec_f, l_in);
    read(l_in, vec_k);
    read(l_in, vec_iter);
    read(l_in, vec_f1);
    read(l_in, vec_f2);

    assert vec_k > 0 and vec_k <= C_K_MAX report "Invalid K in vector file" severity failure;
    assert vec_iter > 0 and vec_iter <= 15 report "Invalid iteration count in vector file" severity failure;

    rst<='1'; wait for 20 ns; rst<='0';
    n_iter<=to_unsigned(vec_iter,4);
    k_len<=to_unsigned(vec_k,13);
    f1<=to_unsigned(vec_f1,13);
    f2<=to_unsigned(vec_f2,13);

    -- Preload all samples from generated LTE-like vector file.
    for n in 0 to vec_k-1 loop
      readline(vec_f, l_in);
      read(l_in, vec_idx);
      read(l_in, bit_orig_v);
      read(l_in, bit_int_v);
      read(l_in, lsys_v);
      read(l_in, lpar1_v);
      read(l_in, lpar2_v);
      assert vec_idx=n report "Vector file index mismatch" severity failure;

      bit_orig_mem(n) := bit_orig_v;
      bit_int_mem(n) := bit_int_v;
      lsys_mem(n) := lsys_v;
      lpar1_mem(n) := lpar1_v;
      lpar2_mem(n) := lpar2_v;

      wait until rising_edge(clk);
      in_valid<='1'; in_idx<=to_unsigned(n,13);
      ls<=to_signed(lsys_v,8); lp1<=to_signed(lpar1_v,8); lp2<=to_signed(lpar2_v,8);

      write(l, string'("IN "));
      write(l, n);
      write(l, character'(' '));
      write(l, bit_orig_v);
      write(l, character'(' '));
      write(l, bit_int_v);
      write(l, character'(' '));
      write(l, lsys_v);
      write(l, character'(' '));
      write(l, lpar1_v);
      write(l, character'(' '));
      write(l, lpar2_v);
      writeline(io_trace_f, l);
    end loop;
    wait until rising_edge(clk);
    in_valid<='0';

    wait until rising_edge(clk);
    start<='1';
    wait until rising_edge(clk);
    start<='0';

    for cyc in 0 to 20000 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      if out_valid='1' then
        idx_v := to_integer(out_idx);
        pass_v := seen_mem(idx_v);
        seen_mem(idx_v) := seen_mem(idx_v) + 1;
        out_cnt := out_cnt + 1;
        llr_v := to_integer(post);
        if llr_v < 0 then
          hard_v := 1;
        else
          hard_v := 0;
        end if;
        final_seen_mem(idx_v) := 1;
        final_llr_mem(idx_v) := llr_v;
        final_hd_mem(idx_v) := hard_v;

        pi_v := (vec_f1*idx_v + vec_f2*idx_v*idx_v) mod vec_k;

        write(l, string'("OUT "));
        write(l, out_cnt);
        write(l, character'(' '));
        write(l, idx_v);
        write(l, character'(' '));
        write(l, pass_v);
        write(l, character'(' '));
        write(l, bit_int_mem(idx_v));
        write(l, character'(' '));
        write(l, bit_orig_mem(pi_v));
        write(l, character'(' '));
        write(l, lsys_mem(pi_v));
        write(l, character'(' '));
        write(l, lpar1_mem(pi_v));
        write(l, character'(' '));
        write(l, lpar2_mem(idx_v));
        write(l, character'(' '));
        write(l, llr_v);
        write(l, character'(' '));
        write(l, hard_v);
        writeline(io_trace_f, l);
      end if;
      exit when done='1';
    end loop;

    n_sym := to_integer(k_len);
    if n_sym > C_K_MAX then
      n_sym := C_K_MAX;
    end if;
    n_iter_i := to_integer(n_iter);
    final_seen_cnt := 0;
    err_cnt_int := 0;
    err_cnt_orig_pi := 0;
    for n in 0 to n_sym-1 loop
      if final_seen_mem(n)=1 then
        final_seen_cnt := final_seen_cnt + 1;
        if final_hd_mem(n) /= bit_int_mem(n) then
          err_cnt_int := err_cnt_int + 1;
        end if;
        pi_v := (vec_f1*n + vec_f2*n*n) mod n_sym;
        if final_hd_mem(n) /= bit_orig_mem(pi_v) then
          err_cnt_orig_pi := err_cnt_orig_pi + 1;
        end if;
      end if;
    end loop;

    write(l, string'("Turbo Decoder End-to-End Report"));
    writeline(report_f, l);
    write(l, string'("symbols=")); write(l, n_sym);
    write(l, string'(" n_iter=")); write(l, n_iter_i);
    write(l, string'(" f1=")); write(l, vec_f1);
    write(l, string'(" f2=")); write(l, vec_f2);
    write(l, string'(" total_outputs=")); write(l, out_cnt);
    write(l, string'(" expected_outputs=")); write(l, n_iter_i*n_sym);
    writeline(report_f, l);
    write(l, string'("final_decision_symbols=")); write(l, final_seen_cnt);
    write(l, string'(" bit_errors_vs_interleaved=")); write(l, err_cnt_int);
    write(l, string'(" bit_errors_vs_orig_pi=")); write(l, err_cnt_orig_pi);
    writeline(report_f, l);
    write(l, string'("idx_int pi(idx) bit_int bit_orig_pi l_sys_pi l_par1_pi l_par2_int final_llr hard_dec match_int"));
    writeline(report_f, l);
    for n in 0 to n_sym-1 loop
      pi_v := (vec_f1*n + vec_f2*n*n) mod n_sym;
      write(l, n);
      write(l, character'(' '));
      write(l, pi_v);
      write(l, character'(' '));
      write(l, bit_int_mem(n));
      write(l, character'(' '));
      write(l, bit_orig_mem(pi_v));
      write(l, character'(' '));
      write(l, lsys_mem(pi_v));
      write(l, character'(' '));
      write(l, lpar1_mem(pi_v));
      write(l, character'(' '));
      write(l, lpar2_mem(n));
      write(l, character'(' '));
      write(l, final_llr_mem(n));
      write(l, character'(' '));
      write(l, final_hd_mem(n));
      write(l, character'(' '));
      if final_hd_mem(n)=bit_int_mem(n) then
        write(l, string'("OK"));
      else
        write(l, string'("ERR"));
      end if;
      writeline(report_f, l);
    end loop;

    assert done='1' report "Top-level did not assert done within timeout" severity error;
    assert out_cnt = n_iter_i*n_sym report "Top-level output count mismatch" severity error;
    assert final_seen_cnt = n_sym report "Final output coverage mismatch" severity error;
    report "tb_turbo_top passed with out_cnt=" & integer'image(out_cnt) &
           " final_seen=" & integer'image(final_seen_cnt) &
           " err_int=" & integer'image(err_cnt_int) severity note;
    finish;
  end process;
end;
