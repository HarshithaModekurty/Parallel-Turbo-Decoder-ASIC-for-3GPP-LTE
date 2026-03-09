library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_qpp_interleaver is end;
architecture sim of tb_qpp_interleaver is
  signal clk,rst,start,valid,v : std_logic := '0';
  signal k,f1,f2,i,o : unsigned(12 downto 0) := (others=>'0');
begin
  dut: entity work.qpp_interleaver
    port map(clk=>clk,rst=>rst,start=>start,valid=>valid,k_len=>k,f1=>f1,f2=>f2,idx_i=>i,idx_o=>o,idx_valid=>v);
  clk <= not clk after 5 ns;
  process
  begin
    rst<='1'; wait for 20 ns; rst<='0';
    k<=to_unsigned(40,13); f1<=to_unsigned(3,13); f2<=to_unsigned(10,13);
    for n in 0 to 7 loop
      wait until rising_edge(clk);
      start<='1'; valid<='1'; i<=to_unsigned(n,13);
    end loop;
    wait until rising_edge(clk);
    valid<='0'; start<='0';
    wait for 100 ns;
    assert false report "tb_qpp_interleaver completed" severity failure;
  end process;
end;
