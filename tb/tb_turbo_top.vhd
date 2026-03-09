library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity tb_turbo_top is end;
architecture sim of tb_turbo_top is
  signal clk,rst,start,in_valid,out_valid,done : std_logic := '0';
  signal n_iter : unsigned(3 downto 0) := (others=>'0');
  signal k_len,f1,f2,in_idx,out_idx : unsigned(12 downto 0) := (others=>'0');
  signal ls,lp1,lp2,post : llr_t := (others=>'0');
begin
  dut: entity work.turbo_decoder_top
    port map(clk=>clk,rst=>rst,start=>start,n_iter=>n_iter,k_len=>k_len,f1=>f1,f2=>f2,
      in_valid=>in_valid,in_idx=>in_idx,l_sys_in=>ls,l_par1_in=>lp1,l_par2_in=>lp2,
      out_valid=>out_valid,out_idx=>out_idx,l_post=>post,done=>done);

  clk <= not clk after 5 ns;
  process
  begin
    rst<='1'; wait for 20 ns; rst<='0';
    n_iter<=to_unsigned(2,4); k_len<=to_unsigned(40,13); f1<=to_unsigned(3,13); f2<=to_unsigned(10,13);
    wait until rising_edge(clk);
    start<='1';
    for n in 0 to 39 loop
      wait until rising_edge(clk);
      start<='0'; in_valid<='1'; in_idx<=to_unsigned(n,13);
      ls<=to_signed((n mod 7)-3,8); lp1<=to_signed((n mod 5)-2,8); lp2<=to_signed((n mod 3)-1,8);
    end loop;
    wait until rising_edge(clk);
    in_valid<='0';
    wait for 2 us;
    assert false report "tb_turbo_top completed" severity failure;
  end process;
end;
