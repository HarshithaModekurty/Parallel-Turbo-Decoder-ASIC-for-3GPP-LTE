library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.turbo_pkg.all;

entity tb_radix4_extractor is
end entity;

architecture sim of tb_radix4_extractor is
  signal alpha_in, beta_in : state_metric_t := (others => (others => '0'));
  signal gamma_in : gamma_vec_t := (others => (others => '0'));
  signal sys_even, sys_odd : chan_llr_t := (others => '0');
  signal apri_even, apri_odd : ext_llr_t := (others => '0');
  signal ext_even, ext_odd : ext_llr_t := (others => '0');
  signal post_even, post_odd : post_llr_t := (others => '0');
begin
  dut: entity work.radix4_extractor
    port map (
      alpha_in=>alpha_in, beta_in=>beta_in, gamma_in=>gamma_in,
      sys_even=>sys_even, sys_odd=>sys_odd, apri_even=>apri_even, apri_odd=>apri_odd,
      ext_even=>ext_even, ext_odd=>ext_odd, post_even=>post_even, post_odd=>post_odd
    );

  process
  begin
    wait for 1 ns;
    assert ext_even = to_signed(0, ext_llr_t'length) report "ext_even expected 0" severity error;
    assert ext_odd = to_signed(0, ext_llr_t'length) report "ext_odd expected 0" severity error;
    assert post_even = to_signed(0, post_llr_t'length) report "post_even expected 0" severity error;
    assert post_odd = to_signed(0, post_llr_t'length) report "post_odd expected 0" severity error;
    report "tb_radix4_extractor passed" severity note;
    finish;
  end process;
end architecture;
