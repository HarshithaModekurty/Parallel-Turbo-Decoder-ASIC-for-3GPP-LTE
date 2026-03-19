library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity batcher_router is
  generic (
    G_P      : natural := 8;
    G_ADDR_W : natural := 13;
    G_DATA_W : natural := 6
  );
  port (
    addr_in  : in  unsigned(G_P*G_ADDR_W-1 downto 0);
    data_in  : in  signed(G_P*G_DATA_W-1 downto 0);
    sel_in   : in  unsigned(G_P*4-1 downto 0);
    addr_out : out unsigned(G_P*G_ADDR_W-1 downto 0);
    data_out : out signed(G_P*G_DATA_W-1 downto 0)
  );
end entity;

architecture rtl of batcher_router is
  type index_array is array (0 to G_P-1) of integer range 0 to G_P-1;
begin
  process(all)
    variable master_idx : index_array;
    variable a_tmp : unsigned(G_P*G_ADDR_W-1 downto 0);
    variable d_tmp : signed(G_P*G_DATA_W-1 downto 0);
    variable s : integer;
  begin
    for i in 0 to G_P-1 loop
      s := to_integer(sel_in((i+1)*4-1 downto i*4));
      if s < G_P then
        master_idx(i) := s;
      else
        master_idx(i) := 0;
      end if;
    end loop;

    a_tmp := (others=>'0');
    d_tmp := (others=>'0');
    for i in 0 to G_P-1 loop
      s := master_idx(i);
      if s < G_P then
        a_tmp((s+1)*G_ADDR_W-1 downto s*G_ADDR_W) := addr_in((i+1)*G_ADDR_W-1 downto i*G_ADDR_W);
        d_tmp((s+1)*G_DATA_W-1 downto s*G_DATA_W) := data_in((i+1)*G_DATA_W-1 downto i*G_DATA_W);
      end if;
    end loop;

    addr_out <= a_tmp;
    data_out <= d_tmp;
  end process;
end architecture;
