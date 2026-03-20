library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity batcher_slave is
  generic (
    G_P       : natural := C_PARALLEL;
    G_DATA_W  : natural := ext_llr_t'length;
    G_SEL_W   : natural := C_ROUTER_SEL_W;
    G_REVERSE : boolean := false
  );
  port (
    perm_in  : in  unsigned(G_P*G_SEL_W-1 downto 0);
    data_in  : in  signed(G_P*G_DATA_W-1 downto 0);
    data_out : out signed(G_P*G_DATA_W-1 downto 0)
  );
end entity;

architecture rtl of batcher_slave is
begin
  process(all)
    type data_arr_t is array (natural range <>) of signed(G_DATA_W-1 downto 0);
    variable in_v  : data_arr_t(0 to G_P-1);
    variable out_v : data_arr_t(0 to G_P-1);
    variable perm_i : integer;
    variable d_tmp : signed(G_P*G_DATA_W-1 downto 0);
  begin
    for i in 0 to G_P-1 loop
      in_v(i) := data_in((i+1)*G_DATA_W-1 downto i*G_DATA_W);
      out_v(i) := (others => '0');
    end loop;

    if G_REVERSE then
      for slot in 0 to G_P-1 loop
        perm_i := to_integer(to_01(perm_in((slot+1)*G_SEL_W-1 downto slot*G_SEL_W), '0'));
        if perm_i >= 0 and perm_i < G_P then
          out_v(slot) := in_v(perm_i);
        end if;
      end loop;
    else
      for slot in 0 to G_P-1 loop
        perm_i := to_integer(to_01(perm_in((slot+1)*G_SEL_W-1 downto slot*G_SEL_W), '0'));
        if perm_i >= 0 and perm_i < G_P then
          out_v(perm_i) := in_v(slot);
        end if;
      end loop;
    end if;

    d_tmp := (others => '0');
    for i in 0 to G_P-1 loop
      d_tmp((i+1)*G_DATA_W-1 downto i*G_DATA_W) := out_v(i);
    end loop;
    data_out <= d_tmp;
  end process;
end architecture;
