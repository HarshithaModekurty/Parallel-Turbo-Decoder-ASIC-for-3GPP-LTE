library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.turbo_pkg.all;

entity tb_folded_llr_ram is
end entity;

architecture sim of tb_folded_llr_ram is
  signal clk : std_logic := '0';
  signal wea, web : std_logic := '0';
  signal addra, addrb : unsigned(3 downto 0) := (others => '0');
  signal dina, dinb, douta, doutb : signed(8*ext_llr_t'length-1 downto 0) := (others => '0');
begin
  dut: entity work.folded_llr_ram
    generic map (G_ROWS=>16, G_ADDR_W=>4, G_LANES=>8, G_WORD_W=>ext_llr_t'length)
    port map (
      clk=>clk, wea=>wea, addra=>addra, dina=>dina, douta=>douta,
      web=>web, addrb=>addrb, dinb=>dinb, doutb=>doutb
    );

  clk <= not clk after 5 ns;

  process
  begin
    addra <= to_unsigned(3, 4);
    addrb <= to_unsigned(3, 4);
    for i in 0 to 7 loop
      dina((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= to_signed(i+1, ext_llr_t'length);
    end loop;
    wea <= '1';
    wait until rising_edge(clk);
    wea <= '0';

    wait until rising_edge(clk);
    wait for 1 ns;
    for i in 0 to 7 loop
      assert to_integer(doutb((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length)) = i+1
        report "Folded RAM readback mismatch at lane " & integer'image(i) severity error;
    end loop;

    report "tb_folded_llr_ram passed" severity note;
    finish;
  end process;
end architecture;
