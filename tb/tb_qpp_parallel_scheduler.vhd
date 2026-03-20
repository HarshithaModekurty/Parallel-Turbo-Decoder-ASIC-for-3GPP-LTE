library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_qpp_parallel_scheduler is
end entity;

architecture sim of tb_qpp_parallel_scheduler is
  signal row_idx, seg_len, k_len, f1, f2, row_base : unsigned(12 downto 0) := (others => '0');
  signal addr_vec : unsigned(8*13-1 downto 0) := (others => '0');
  signal row_ok : std_logic := '0';
begin
  dut: entity work.qpp_parallel_scheduler
    port map (
      row_idx=>row_idx, seg_len=>seg_len, k_len=>k_len, f1=>f1, f2=>f2,
      addr_vec=>addr_vec, row_base=>row_base, row_ok=>row_ok
    );

  process
    type int_arr_t is array (0 to 7) of integer;
    constant exp_addr : int_arr_t := (13, 18, 3, 8, 33, 38, 23, 28);
  begin
    row_idx <= to_unsigned(1, 13);
    seg_len <= to_unsigned(5, 13);
    k_len <= to_unsigned(40, 13);
    f1 <= to_unsigned(3, 13);
    f2 <= to_unsigned(10, 13);
    wait for 1 ns;

    assert row_ok='1' report "Expected row_ok=1" severity error;
    assert row_base=to_unsigned(3, 13) report "Expected row_base=3" severity error;
    for i in 0 to 7 loop
      assert to_integer(addr_vec((i+1)*13-1 downto i*13)) = exp_addr(i)
        report "Unexpected scheduled address at lane " & integer'image(i) severity error;
    end loop;

    report "tb_qpp_parallel_scheduler passed" severity note;
    finish;
  end process;
end architecture;
