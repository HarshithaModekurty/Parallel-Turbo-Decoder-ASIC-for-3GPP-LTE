library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;
use std.env.all;

entity tb_siso_smoke is
end entity;

architecture sim of tb_siso_smoke is
  signal clk,rst,start,in_valid,out_valid,done : std_logic := '0';
  signal seg_len,in_pair_idx,out_pair_idx : unsigned(12 downto 0) := (others=>'0');
  signal sys_e,sys_o,par_e,par_o : chan_llr_t := (others=>'0');
  signal apr_e,apr_o,ext_e,ext_o : ext_llr_t := (others=>'0');
  signal post_e,post_o : post_llr_t := (others=>'0');
begin
  dut: entity work.siso_maxlogmap
    generic map (G_SEG_MAX=>64, G_ADDR_W=>13)
    port map(
      clk=>clk, rst=>rst, start=>start, seg_first=>'1', seg_last=>'1', seg_len=>seg_len,
      in_valid=>in_valid, in_pair_idx=>in_pair_idx,
      sys_even=>sys_e, sys_odd=>sys_o, par_even=>par_e, par_odd=>par_o,
      apri_even=>apr_e, apri_odd=>apr_o,
      out_valid=>out_valid, out_pair_idx=>out_pair_idx,
      ext_even=>ext_e, ext_odd=>ext_o, post_even=>post_e, post_odd=>post_o,
      done=>done
    );

  clk <= not clk after 5 ns;

  process
    variable out_cnt : integer := 0;
  begin
    rst <= '1';
    wait for 20 ns;
    rst <= '0';
    seg_len <= to_unsigned(32, 13);

    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    for n in 0 to 15 loop
      in_valid <= '1';
      in_pair_idx <= to_unsigned(n, 13);
      sys_e <= sat_chan((n mod 7) - 3);
      sys_o <= sat_chan(((n + 2) mod 7) - 3);
      par_e <= sat_chan((n mod 5) - 2);
      par_o <= sat_chan(((n + 1) mod 5) - 2);
      apr_e <= (others => '0');
      apr_o <= (others => '0');
      wait until rising_edge(clk);
    end loop;
    in_valid <= '0';

    for cyc in 0 to 2000 loop
      wait until rising_edge(clk);
      if out_valid='1' then
        out_cnt := out_cnt + 1;
        assert not is_x(std_logic_vector(ext_e)) report "ext_even has X" severity error;
        assert not is_x(std_logic_vector(ext_o)) report "ext_odd has X" severity error;
        assert not is_x(std_logic_vector(post_e)) report "post_even has X" severity error;
        assert not is_x(std_logic_vector(post_o)) report "post_odd has X" severity error;
      end if;
      exit when done='1';
    end loop;

    assert done='1' report "SISO did not assert done within timeout" severity error;
    assert out_cnt=16 report "SISO pair output count mismatch, expected 16 got " & integer'image(out_cnt) severity error;
    report "tb_siso_smoke passed" severity note;
    finish;
  end process;
end architecture;
