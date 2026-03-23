library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity folded_llr_ram is
  generic (
    G_ROWS   : natural := 384;
    G_ADDR_W : natural := 9;
    G_LANES  : natural := C_PARALLEL;
    G_WORD_W : natural := ext_llr_t'length
  );
  port (
    clk   : in  std_logic;
    wea   : in  std_logic;
    addra : in  unsigned(G_ADDR_W-1 downto 0);
    dina  : in  signed(G_LANES*G_WORD_W-1 downto 0);
    douta : out signed(G_LANES*G_WORD_W-1 downto 0);
    web   : in  std_logic;
    addrb : in  unsigned(G_ADDR_W-1 downto 0);
    dinb  : in  signed(G_LANES*G_WORD_W-1 downto 0);
    doutb : out signed(G_LANES*G_WORD_W-1 downto 0)
  );
end entity;

architecture rtl of folded_llr_ram is
  subtype word_t is signed(G_LANES*G_WORD_W-1 downto 0);
  type ram_t is array (0 to G_ROWS-1) of word_t;
  signal mem : ram_t := (others => (others => '0'));
  signal qa, qb : word_t := (others => '0');
  attribute ram_style : string;
  attribute ram_style of mem : signal is "block";
begin
  process(clk)
    variable a_i, b_i : integer;
  begin
    if rising_edge(clk) then
      a_i := to_integer(addra);
      b_i := to_integer(addrb);

      if wea = '1' and a_i >= 0 and a_i < G_ROWS then
        mem(a_i) <= dina;
      end if;
      if web = '1' and b_i >= 0 and b_i < G_ROWS then
        mem(b_i) <= dinb;
      end if;

      if a_i >= 0 and a_i < G_ROWS then
        qa <= mem(a_i);
      else
        qa <= (others => '0');
      end if;

      if b_i >= 0 and b_i < G_ROWS then
        qb <= mem(b_i);
      else
        qb <= (others => '0');
      end if;
    end if;
  end process;

  douta <= qa;
  doutb <= qb;
end architecture;
