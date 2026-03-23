library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_qpp_interleaver is
end entity;

architecture sim of tb_qpp_interleaver is
  signal clk,rst,start,valid,v : std_logic := '0';
  signal k,f1,f2,o : unsigned(12 downto 0) := (others=>'0');
begin
  dut: entity work.qpp_interleaver
    port map(clk=>clk,rst=>rst,start=>start,valid=>valid,k_len=>k,f1=>f1,f2=>f2,idx_o=>o,idx_valid=>v);
  clk <= not clk after 5 ns;
  process
    variable exp : integer;
  begin
    rst<='1'; wait for 20 ns; rst<='0';
    k<=to_unsigned(40,13); f1<=to_unsigned(3,13); f2<=to_unsigned(10,13);
    start<='1';
    valid<='0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert v='1' report "QPP valid missing at n=0" severity error;
    assert o=to_unsigned(0,13)
      report "QPP mismatch at n=0 exp=0 got=" & integer'image(to_integer(o))
      severity error;

    start<='0';
    for n in 1 to 7 loop
      valid<='1';
      wait until rising_edge(clk);
      wait for 1 ns;
      exp := (3*n + 10*n*n) mod 40;
      assert v='1' report "QPP valid missing at n=" & integer'image(n) severity error;
      assert o=to_unsigned(exp,13)
        report "QPP mismatch at n=" & integer'image(n) &
               " exp=" & integer'image(exp) &
               " got=" & integer'image(to_integer(o))
        severity error;
    end loop;
    valid<='0'; start<='0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert v='0' report "QPP valid should deassert when valid input is low" severity error;
    report "tb_qpp_interleaver passed" severity note;
    finish;
  end process;
end architecture;
