library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;
use std.env.all;

entity tb_siso_vector_compare is
end entity;

architecture sim of tb_siso_vector_compare is
  type int_vec40_t is array (0 to 39) of integer;
  signal clk, rst, start, in_valid, out_valid, done : std_logic := '0';
  signal seg_len, in_pair_idx, out_pair_idx : unsigned(12 downto 0) := (others => '0');
  signal sys_e, sys_o, par_e, par_o : chan_llr_t := (others => '0');
  signal apr_e, apr_o, ext_e, ext_o : ext_llr_t := (others => '0');
  signal post_e, post_o : post_llr_t := (others => '0');
begin
  dut: entity work.siso_maxlogmap
    generic map (G_SEG_MAX => 64, G_ADDR_W => 13)
    port map(
      clk => clk,
      rst => rst,
      start => start,
      seg_first => '1',
      seg_last => '0',
      seg_len => seg_len,
      in_valid => in_valid,
      in_pair_idx => in_pair_idx,
      sys_even => sys_e,
      sys_odd => sys_o,
      par_even => par_e,
      par_odd => par_o,
      apri_even => apr_e,
      apri_odd => apr_o,
      out_valid => out_valid,
      out_pair_idx => out_pair_idx,
      ext_even => ext_e,
      ext_odd => ext_o,
      post_even => post_e,
      post_odd => post_o,
      done => done
    );

  clk <= not clk after 5 ns;

  process
    constant lsys_v : int_vec40_t := (15, -9, 12, -13, -10, -9, 13, -16, 10, -11, 15, 15, -10, 5, 10, 13, 14, -9, 14, 15, -16, 3, 8, 2, -4, 15, 2, -14, -16, -7, 12, -15, -16, -13, 12, -15, -13, 12, 4, 0);
    constant lpar_v : int_vec40_t := (6, -16, 8, 12, -16, 13, 7, -5, 15, 11, 15, -4, 15, -16, -10, -16, 15, 15, 13, -14, 15, 13, -7, -14, -9, 6, 12, 10, 8, -14, -12, -12, 9, 9, -14, -10, -14, 14, 8, -5);
    constant exp_ext_v : int_vec40_t := (-32, 31, -32, 31, 31, 31, -32, 31, -32, 31, -32, -32, 31, -32, -32, -32, -32, 31, -32, -32, 31, 22, -32, 21, 25, -32, -25, 31, 31, 31, -32, 31, 31, 31, -32, 31, 30, -27, -11, -4);
    constant exp_post_v : int_vec40_t := (-64, 59, -52, 63, 52, 56, -57, 56, -52, 56, -64, -57, 56, -56, -57, -57, -60, 56, -55, -39, 46, 36, -39, 33, 33, -36, -33, 40, 55, 41, -49, 61, 55, 36, -40, 37, 31, -26, -12, -5);
    variable ext_obs, post_obs : int_vec40_t := (others => 0);
    variable out_cnt : integer := 0;
    variable pair_i : integer;
  begin
    rst <= '1';
    wait for 20 ns;
    rst <= '0';
    seg_len <= to_unsigned(40, seg_len'length);

    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    for pair in 0 to 19 loop
      in_valid <= '1';
      in_pair_idx <= to_unsigned(pair, in_pair_idx'length);
      sys_e <= sat_chan(lsys_v(2*pair));
      sys_o <= sat_chan(lsys_v(2*pair + 1));
      par_e <= sat_chan(lpar_v(2*pair));
      par_o <= sat_chan(lpar_v(2*pair + 1));
      apr_e <= to_signed(0, ext_llr_t'length);
      apr_o <= to_signed(0, ext_llr_t'length);
      wait until rising_edge(clk);
    end loop;
    in_valid <= '0';

    for cyc in 0 to 4000 loop
      wait until rising_edge(clk);
      if out_valid = '1' then
        pair_i := to_integer(out_pair_idx);
        ext_obs(2*pair_i) := to_integer(ext_e);
        ext_obs(2*pair_i + 1) := to_integer(ext_o);
        post_obs(2*pair_i) := to_integer(post_e);
        post_obs(2*pair_i + 1) := to_integer(post_o);
        out_cnt := out_cnt + 1;
      end if;
      exit when done = '1';
    end loop;

    assert done = '1' report "SISO vector compare did not finish" severity error;
    assert out_cnt = 20 report "Expected 20 pair outputs, got " & integer'image(out_cnt) severity error;
    for i in 0 to 39 loop
      assert ext_obs(i) = exp_ext_v(i)
        report "Vector ext mismatch at bit " & integer'image(i) & ": exp=" & integer'image(exp_ext_v(i)) & " got=" & integer'image(ext_obs(i))
        severity error;
      assert post_obs(i) = exp_post_v(i)
        report "Vector post mismatch at bit " & integer'image(i) & ": exp=" & integer'image(exp_post_v(i)) & " got=" & integer'image(post_obs(i))
        severity error;
    end loop;

    report "tb_siso_vector_compare passed" severity note;
    finish;
  end process;
end architecture;
