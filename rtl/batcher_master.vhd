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
    perm_out    : out unsigned(G_P*G_SEL_W-1 downto 0);
    ctrl_out    : out std_logic_vector(C_BATCHER_CTRL_W-1 downto 0)
  );
end entity;

architecture rtl of batcher_master is
begin
  assert G_P = 8
    report "batcher_master is specialized for the paper's N=8 master Batcher network"
    severity failure;

  process(all)
    type int_arr_t is array (0 to 7) of integer;
    variable addr_v : int_arr_t;
    variable lane_v : int_arr_t;
    variable a_tmp  : unsigned(G_P*G_ADDR_W-1 downto 0);
    variable p_tmp  : unsigned(G_P*G_SEL_W-1 downto 0);
    variable c_tmp  : std_logic_vector(C_BATCHER_CTRL_W-1 downto 0);
    variable addr_t : integer;
    variable lane_t : integer;

    procedure compare_swap(
      constant left_idx  : in natural;
      constant right_idx : in natural;
      constant ctrl_idx  : in natural
    ) is
    begin
      if addr_v(left_idx) > addr_v(right_idx) then
        addr_t := addr_v(left_idx);
        addr_v(left_idx) := addr_v(right_idx);
        addr_v(right_idx) := addr_t;

        lane_t := lane_v(left_idx);
        lane_v(left_idx) := lane_v(right_idx);
        lane_v(right_idx) := lane_t;
        c_tmp(ctrl_idx) := '1';
      else
        c_tmp(ctrl_idx) := '0';
      end if;
    end procedure;
  begin
    for i in 0 to 7 loop
      addr_v(i) := to_integer(to_01(addr_in((i+1)*G_ADDR_W-1 downto i*G_ADDR_W), '0'));
      lane_v(i) := i;
    end loop;

    c_tmp := (others => '0');

    compare_swap(0, 1, 0);
    compare_swap(2, 3, 1);
    compare_swap(4, 5, 2);
    compare_swap(6, 7, 3);

    compare_swap(0, 2, 4);
    compare_swap(1, 3, 5);
    compare_swap(4, 6, 6);
    compare_swap(5, 7, 7);

    compare_swap(1, 2, 8);
    compare_swap(5, 6, 9);

    compare_swap(0, 4, 10);
    compare_swap(1, 5, 11);
    compare_swap(2, 6, 12);
    compare_swap(3, 7, 13);

    compare_swap(2, 4, 14);
    compare_swap(3, 5, 15);

    compare_swap(1, 2, 16);
    compare_swap(3, 4, 17);
    compare_swap(5, 6, 18);

    a_tmp := (others => '0');
    p_tmp := (others => '0');
    for i in 0 to 7 loop
      a_tmp((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) := to_unsigned(addr_v(i), G_ADDR_W);
      p_tmp((i+1)*G_SEL_W-1 downto i*G_SEL_W) := to_unsigned(lane_v(i), G_SEL_W);
    end loop;

    addr_sorted <= a_tmp;
    perm_out <= p_tmp;
    ctrl_out <= c_tmp;
  end process;
end architecture;
