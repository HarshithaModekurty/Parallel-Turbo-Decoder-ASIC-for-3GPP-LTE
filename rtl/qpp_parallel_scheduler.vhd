library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity qpp_parallel_scheduler is
  generic (
    G_P      : natural := C_PARALLEL;
    G_ADDR_W : natural := 13
  );
  port (
    row_idx  : in  unsigned(G_ADDR_W-1 downto 0);
    seg_len  : in  unsigned(G_ADDR_W-1 downto 0);
    k_len    : in  unsigned(G_ADDR_W-1 downto 0);
    f1       : in  unsigned(G_ADDR_W-1 downto 0);
    f2       : in  unsigned(G_ADDR_W-1 downto 0);
    addr_vec : out unsigned(G_P*G_ADDR_W-1 downto 0);
    row_base : out unsigned(G_ADDR_W-1 downto 0);
    row_ok   : out std_logic
  );
end entity;

architecture rtl of qpp_parallel_scheduler is
begin
  process(all)
    variable a_tmp : unsigned(G_P*G_ADDR_W-1 downto 0);
    variable row_v : integer := 0;
    variable ok_v : std_logic := '1';
    variable seg_i, row_i, k_i, f1_i, f2_i : integer;
    variable g_idx, addr_i : integer;
  begin
    a_tmp := (others => '0');
    row_v := 0;
    ok_v := '1';
    seg_i := to_integer(to_01(seg_len, '0'));
    row_i := to_integer(to_01(row_idx, '0'));
    k_i := to_integer(to_01(k_len, '0'));
    f1_i := to_integer(to_01(f1, '0'));
    f2_i := to_integer(to_01(f2, '0'));

    if seg_i = 0 or row_i >= seg_i then
      row_v := 0;
      ok_v := '0';
    else
      for lane in 0 to G_P-1 loop
        g_idx := row_i + lane * seg_i;
        if g_idx >= k_i then
          addr_i := 0;
          ok_v := '0';
        else
          addr_i := qpp_value(g_idx, k_i, f1_i, f2_i);
          if lane = 0 then
            row_v := addr_i mod seg_i;
          elsif (addr_i mod seg_i) /= row_v then
            ok_v := '0';
          end if;
        end if;
        a_tmp((lane+1)*G_ADDR_W-1 downto lane*G_ADDR_W) := to_unsigned(addr_i, G_ADDR_W);
      end loop;
    end if;

    addr_vec <= a_tmp;
    row_base <= to_unsigned(row_v, G_ADDR_W);
    row_ok <= ok_v;
  end process;
end architecture;
