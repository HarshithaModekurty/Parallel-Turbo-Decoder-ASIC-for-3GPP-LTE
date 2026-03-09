library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity qpp_interleaver is
  generic (
    G_K_MAX : natural := 6144;
    G_ADDR_W : natural := 13
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;
    valid : in  std_logic;
    k_len : in  unsigned(G_ADDR_W-1 downto 0);
    f1    : in  unsigned(G_ADDR_W-1 downto 0);
    f2    : in  unsigned(G_ADDR_W-1 downto 0);
    idx_i : in  unsigned(G_ADDR_W-1 downto 0);
    idx_o : out unsigned(G_ADDR_W-1 downto 0);
    idx_valid : out std_logic
  );
end entity;

architecture rtl of qpp_interleaver is
  signal v_q : std_logic;
  signal idx_q : unsigned(G_ADDR_W-1 downto 0);
begin
  process(clk)
    variable k_i : integer;
    variable x, a1, a2 : integer;
    variable m : integer;
  begin
    if rising_edge(clk) then
      if rst='1' then
        v_q <= '0';
        idx_q <= (others=>'0');
      else
        if start='1' and valid='1' then
          k_i := to_integer(k_len);
          x := to_integer(idx_i);
          a1 := to_integer(f1) * x;
          a2 := to_integer(f2) * x * x;
          if k_i = 0 then
            m := 0;
          else
            m := (a1 + a2) mod k_i;
          end if;
          idx_q <= to_unsigned(m, G_ADDR_W);
          v_q <= '1';
        else
          v_q <= '0';
        end if;
      end if;
    end if;
  end process;

  idx_o <= idx_q;
  idx_valid <= v_q;
end architecture;
