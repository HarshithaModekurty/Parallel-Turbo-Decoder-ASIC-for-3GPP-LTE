library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.turbo_pkg.all;

entity tb_radix4_acs is
end entity;

architecture sim of tb_radix4_acs is
  signal state_in, state_out : state_metric_t := (others => (others => '0'));
  signal gamma_in : gamma_vec_t := (others => (others => '0'));
  signal mode_bwd : std_logic := '0';
begin
  dut: entity work.radix4_acs
    port map (state_in=>state_in, gamma_in=>gamma_in, mode_bwd=>mode_bwd, state_out=>state_out);

  process
  begin
    wait for 1 ns;
    for s in 0 to C_NUM_STATES-1 loop
      assert state_out(s) = to_signed(0, metric_t'length)
        report "Forward ACS zero-case mismatch at state " & integer'image(s) severity error;
    end loop;

    mode_bwd <= '1';
    wait for 1 ns;
    for s in 0 to C_NUM_STATES-1 loop
      assert state_out(s) = to_signed(0, metric_t'length)
        report "Backward ACS zero-case mismatch at state " & integer'image(s) severity error;
    end loop;

    report "tb_radix4_acs passed" severity note;
    finish;
  end process;
end architecture;
