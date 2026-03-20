library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity batcher_router is
  generic (
    G_P       : natural := C_PARALLEL;
    G_ADDR_W  : natural := 13;
    G_DATA_W  : natural := ext_llr_t'length;
    G_SEL_W   : natural := C_ROUTER_SEL_W
  );
  port (
    addr_in     : in  unsigned(G_P*G_ADDR_W-1 downto 0);
    data_in     : in  signed(G_P*G_DATA_W-1 downto 0);
    addr_sorted : out unsigned(G_P*G_ADDR_W-1 downto 0);
    perm_out    : out unsigned(G_P*G_SEL_W-1 downto 0);
    data_out    : out signed(G_P*G_DATA_W-1 downto 0)
  );
end entity;

architecture rtl of batcher_router is
begin
  master_u : entity work.batcher_master
    generic map (
      G_P => G_P,
      G_ADDR_W => G_ADDR_W,
      G_SEL_W => G_SEL_W
    )
    port map (
      addr_in => addr_in,
      addr_sorted => addr_sorted,
      perm_out => perm_out
    );

  slave_u : entity work.batcher_slave
    generic map (
      G_P => G_P,
      G_DATA_W => G_DATA_W,
      G_SEL_W => G_SEL_W,
      G_REVERSE => false
    )
    port map (
      perm_in => perm_out,
      data_in => data_in,
      data_out => data_out
    );
end architecture;
