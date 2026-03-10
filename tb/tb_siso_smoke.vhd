library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;
use std.env.all;

entity tb_siso_smoke is end;
architecture sim of tb_siso_smoke is
  signal clk,rst,start,in_valid,out_valid,done : std_logic := '0';
  signal k_len,in_idx,out_idx : unsigned(12 downto 0) := (others=>'0');
  signal ls,lp,la,le : llr_t := (others=>'0');
begin
  dut: entity work.siso_maxlogmap
    port map(clk=>clk,rst=>rst,start=>start,k_len=>k_len,in_valid=>in_valid,in_idx=>in_idx,
      l_sys=>ls,l_par=>lp,l_apri=>la,out_valid=>out_valid,out_idx=>out_idx,l_ext=>le,done=>done);
  clk <= not clk after 5 ns;
  process
    variable out_cnt : integer := 0;
  begin
    rst<='1'; wait for 20 ns; rst<='0';
    k_len <= to_unsigned(32,13);
    wait until rising_edge(clk);
    start <= '1';
    for n in 0 to 31 loop
      wait until rising_edge(clk);
      start <= '0'; in_valid <= '1'; in_idx<=to_unsigned(n,13);
      ls <= to_signed((n mod 5)-2,8);
      lp <= to_signed((n mod 3)-1,8);
      la <= (others=>'0');
    end loop;
    wait until rising_edge(clk);
    in_valid <= '0';

    for cyc in 0 to 2000 loop
      wait until rising_edge(clk);
      if out_valid='1' then
        out_cnt := out_cnt + 1;
      end if;
      exit when done='1';
    end loop;

    assert done='1' report "SISO did not assert done within timeout" severity error;
    assert out_cnt=32 report "SISO out_valid count mismatch, expected 32 got " & integer'image(out_cnt) severity error;
    report "tb_siso_smoke passed" severity note;
    finish;
  end process;
end;
