library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.turbo_pkg.all;

entity tb_batcher_router is
end entity;

architecture sim of tb_batcher_router is
  signal addr_in, addr_sorted : unsigned(8*13-1 downto 0) := (others => '0');
  signal perm_out : unsigned(8*C_ROUTER_SEL_W-1 downto 0) := (others => '0');
  signal ctrl_out : std_logic_vector(C_BATCHER_CTRL_W-1 downto 0) := (others => '0');
  signal data_in, data_out : signed(8*ext_llr_t'length-1 downto 0) := (others => '0');
  signal data_sorted, data_fwd, data_rev : signed(8*ext_llr_t'length-1 downto 0) := (others => '0');
begin
  dut: entity work.batcher_router
    generic map (G_P=>8, G_ADDR_W=>13, G_DATA_W=>ext_llr_t'length, G_SEL_W=>C_ROUTER_SEL_W)
    port map (
      addr_in=>addr_in,
      data_in=>data_in,
      addr_sorted=>addr_sorted,
      perm_out=>perm_out,
      ctrl_out=>ctrl_out,
      data_out=>data_out
    );

  slave_fwd: entity work.batcher_slave
    generic map (G_P=>8, G_DATA_W=>ext_llr_t'length, G_SEL_W=>C_ROUTER_SEL_W, G_REVERSE=>false)
    port map (
      perm_in=>perm_out,
      data_in=>data_sorted,
      data_out=>data_fwd
    );

  slave_rev: entity work.batcher_slave
    generic map (G_P=>8, G_DATA_W=>ext_llr_t'length, G_SEL_W=>C_ROUTER_SEL_W, G_REVERSE=>true)
    port map (
      perm_in=>perm_out,
      data_in=>data_fwd,
      data_out=>data_rev
    );

  process
    type int_arr_t is array (0 to 7) of integer;
    constant addr_unsorted : int_arr_t := (6, 31, 36, 21, 26, 11, 16, 1);
    constant addr_sorted_exp : int_arr_t := (1, 6, 11, 16, 21, 26, 31, 36);
    constant perm_exp : int_arr_t := (7, 0, 5, 6, 3, 4, 1, 2);
    constant data_lane_exp : int_arr_t := (2, 7, 8, 5, 6, 3, 4, 1);
    constant data_sorted_exp : int_arr_t := (8, 1, 6, 7, 4, 5, 2, 3);
  begin
    for i in 0 to 7 loop
      addr_in((i+1)*13-1 downto i*13) <= to_unsigned(addr_unsorted(i), 13);
      data_in((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= to_signed(i+1, ext_llr_t'length);
      data_sorted((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= to_signed(data_sorted_exp(i), ext_llr_t'length);
    end loop;
    wait for 1 ns;

    for i in 0 to 7 loop
      assert to_integer(addr_sorted((i+1)*13-1 downto i*13)) = addr_sorted_exp(i)
        report "Sorted address mismatch at position " & integer'image(i) severity error;
      assert to_integer(perm_out((i+1)*C_ROUTER_SEL_W-1 downto i*C_ROUTER_SEL_W)) = perm_exp(i)
        report "Permutation mismatch at slot " & integer'image(i) severity error;
      assert to_integer(data_out((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length)) = data_lane_exp(i)
        report "Permuted data mismatch at lane " & integer'image(i) severity error;
      assert to_integer(data_fwd((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length)) = i + 1
        report "Forward slave mismatch at lane " & integer'image(i) severity error;
      assert to_integer(data_rev((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length)) = data_sorted_exp(i)
        report "Reverse slave mismatch at slot " & integer'image(i) severity error;
    end loop;

    report "tb_batcher_router passed" severity note;
    finish;
  end process;
end architecture;
