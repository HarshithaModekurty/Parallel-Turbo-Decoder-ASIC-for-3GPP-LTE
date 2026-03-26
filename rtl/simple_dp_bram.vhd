library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simple_dp_bram is
  generic (
    G_DEPTH  : natural := 3072;
    G_ADDR_W : natural := 13;
    G_DATA_W : natural := 8
  );
  port (
    clk     : in  std_logic;
    rd_en   : in  std_logic;
    rd_addr : in  unsigned(G_ADDR_W-1 downto 0);
    rd_data : out signed(G_DATA_W-1 downto 0);
    wr_en   : in  std_logic;
    wr_addr : in  unsigned(G_ADDR_W-1 downto 0);
    wr_data : in  signed(G_DATA_W-1 downto 0)
  );
end entity;

architecture rtl of simple_dp_bram is
  subtype addr_idx_t is integer range 0 to (2**G_ADDR_W)-1;
  type ram_t is array (0 to G_DEPTH-1) of signed(G_DATA_W-1 downto 0);
  signal mem  : ram_t := (others => (others => '0'));
  signal rd_q : signed(G_DATA_W-1 downto 0) := (others => '0');

  attribute ram_style : string;
  attribute ram_style of mem : signal is "block";
begin
  process(clk)
    variable rd_idx : addr_idx_t;
    variable wr_idx : addr_idx_t;
  begin
    if rising_edge(clk) then
      rd_idx := to_integer(rd_addr);
      wr_idx := to_integer(wr_addr);

      if wr_en = '1' and wr_idx >= 0 and wr_idx < G_DEPTH then
        mem(wr_idx) <= wr_data;
      end if;

      if rd_en = '1' and rd_idx >= 0 and rd_idx < G_DEPTH then
        rd_q <= mem(rd_idx);
      else
        rd_q <= (others => '0');
      end if;
    end if;
  end process;

  rd_data <= rd_q;
end architecture;
