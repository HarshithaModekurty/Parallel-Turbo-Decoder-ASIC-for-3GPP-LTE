library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity llr_ram is
  generic (
    G_DEPTH : natural := 6144;
    G_ADDR_W : natural := 13
  );
  port (
    clk : in std_logic;
    we  : in std_logic;
    waddr : in unsigned(G_ADDR_W-1 downto 0);
    wdata : in llr_t;
    raddr : in unsigned(G_ADDR_W-1 downto 0);
    rdata : out llr_t
  );
end entity;

architecture rtl of llr_ram is
  type ram_t is array (0 to G_DEPTH-1) of llr_t;
  signal mem : ram_t := (others => (others => '0'));
  signal r_q : llr_t := (others => '0');
begin
  process(clk)
    variable w_i, r_i : integer;
  begin
    if rising_edge(clk) then
      if we='1' then
        if not is_x(std_logic_vector(waddr)) then
          w_i := to_integer(waddr);
          if w_i >= 0 and w_i < G_DEPTH then
            mem(w_i) <= wdata;
          end if;
        end if;
      end if;

      if not is_x(std_logic_vector(raddr)) then
        r_i := to_integer(raddr);
        if r_i >= 0 and r_i < G_DEPTH then
          r_q <= mem(r_i);
        else
          r_q <= (others => '0');
        end if;
      else
        r_q <= (others => '0');
      end if;
    end if;
  end process;
  rdata <= r_q;
end architecture;
