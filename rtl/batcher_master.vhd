library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity batcher_master is
  generic (
    G_P      : natural := C_PARALLEL;
    G_ADDR_W : natural := 13;
    G_SEL_W  : natural := C_ROUTER_SEL_W
  );
  port (
    addr_in     : in  unsigned(G_P*G_ADDR_W-1 downto 0);
    addr_sorted : out unsigned(G_P*G_ADDR_W-1 downto 0);
    perm_out    : out unsigned(G_P*G_SEL_W-1 downto 0)
  );
end entity;

architecture rtl of batcher_master is
begin
  process(all)
    type int_arr_t is array (natural range <>) of integer;
    type bool_arr_t is array (natural range <>) of boolean;
    variable addr_v : int_arr_t(0 to G_P-1);
    variable perm_v : int_arr_t(0 to G_P-1);
    variable used_v : bool_arr_t(0 to G_P-1);
    variable a_tmp  : unsigned(G_P*G_ADDR_W-1 downto 0);
    variable p_tmp  : unsigned(G_P*G_SEL_W-1 downto 0);
    variable min_idx : integer := 0;
    variable min_val : integer := 0;
  begin
    for i in 0 to G_P-1 loop
      addr_v(i) := to_integer(to_01(addr_in((i+1)*G_ADDR_W-1 downto i*G_ADDR_W), '0'));
      perm_v(i) := i;
      used_v(i) := false;
    end loop;

    a_tmp := (others => '0');
    p_tmp := (others => '0');
    for out_i in 0 to G_P-1 loop
      min_idx := -1;
      min_val := 0;
      for cand_i in 0 to G_P-1 loop
        if not used_v(cand_i) then
          if (min_idx = -1) or (addr_v(cand_i) < min_val) then
            min_idx := cand_i;
            min_val := addr_v(cand_i);
          end if;
        end if;
      end loop;

      if min_idx >= 0 then
        used_v(min_idx) := true;
        a_tmp((out_i+1)*G_ADDR_W-1 downto out_i*G_ADDR_W) := to_unsigned(addr_v(min_idx), G_ADDR_W);
        p_tmp((out_i+1)*G_SEL_W-1 downto out_i*G_SEL_W) := to_unsigned(perm_v(min_idx), G_SEL_W);
      end if;
    end loop;

    addr_sorted <= a_tmp;
    perm_out <= p_tmp;
  end process;
end architecture;
