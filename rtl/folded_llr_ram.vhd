library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity folded_llr_ram is
  generic (
    G_BANKS  : natural := 8;
    G_ADDR_W : natural := 13
  );
  port (
    clk      : in  std_logic;
    we       : in  std_logic_vector(G_BANKS-1 downto 0);
    wr_addr  : in  unsigned(G_BANKS*G_ADDR_W-1 downto 0);
    wr_data  : in  signed(G_BANKS*ext_llr_t'length-1 downto 0);
    rd_addr  : in  unsigned(G_BANKS*G_ADDR_W-1 downto 0);
    rd_data  : out signed(G_BANKS*ext_llr_t'length-1 downto 0)
  );
end entity;

architecture rtl of folded_llr_ram is
  type mem_arr_t is array (0 to 2**(G_ADDR_W)/G_BANKS - 1) of ext_llr_t;
  type mem_bank_arr_t is array (0 to G_BANKS-1) of mem_arr_t;
  
  signal mem_banks : mem_bank_arr_t;
begin

  gen_banks: for i in 0 to G_BANKS-1 generate
    process(clk)
      variable wa, ra : integer;
    begin
      if rising_edge(clk) then
        wa := to_integer(wr_addr((i+1)*G_ADDR_W-1 downto i*G_ADDR_W)) / G_BANKS;
        if we(i) = '1' then
          mem_banks(i)(wa) <= wr_data((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length);
        end if;
        
        ra := to_integer(rd_addr((i+1)*G_ADDR_W-1 downto i*G_ADDR_W)) / G_BANKS;
        rd_data((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= mem_banks(i)(ra);
      end if;
    end process;
  end generate;

end architecture;