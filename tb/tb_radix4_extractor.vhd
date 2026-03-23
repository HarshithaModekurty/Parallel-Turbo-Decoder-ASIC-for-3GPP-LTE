library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.turbo_pkg.all;

entity tb_radix4_extractor is
end entity;

architecture sim of tb_radix4_extractor is
  signal alpha_in, beta_in : state_metric_t := (others => (others => '0'));
  signal sys_even, sys_odd : chan_llr_t := (others => '0');
  signal par_even, par_odd : chan_llr_t := (others => '0');
  signal apri_even, apri_odd : ext_llr_t := (others => '0');
  signal ext_even, ext_odd : ext_llr_t := (others => '0');
  signal post_even, post_odd : post_llr_t := (others => '0');
begin
  dut: entity work.radix4_extractor
    port map (
      alpha_in=>alpha_in, beta_in=>beta_in,
      sys_even=>sys_even, sys_odd=>sys_odd,
      par_even=>par_even, par_odd=>par_odd,
      apri_even=>apri_even, apri_odd=>apri_odd,
      ext_even=>ext_even, ext_odd=>ext_odd, post_even=>post_even, post_odd=>post_odd
    );

  process
  begin
    wait for 1 ns;
    assert ext_even = to_signed(0, ext_llr_t'length) report "ext_even expected 0" severity error;
    assert ext_odd = to_signed(0, ext_llr_t'length) report "ext_odd expected 0" severity error;
    assert post_even = to_signed(0, post_llr_t'length) report "post_even expected 0" severity error;
    assert post_odd = to_signed(0, post_llr_t'length) report "post_odd expected 0" severity error;

    alpha_in(0) <= to_signed(0, metric_t'length);
    alpha_in(1) <= to_signed(-8, metric_t'length);
    alpha_in(2) <= to_signed(-16, metric_t'length);
    alpha_in(3) <= to_signed(-24, metric_t'length);
    alpha_in(4) <= to_signed(-32, metric_t'length);
    alpha_in(5) <= to_signed(-40, metric_t'length);
    alpha_in(6) <= to_signed(-48, metric_t'length);
    alpha_in(7) <= to_signed(-56, metric_t'length);

    beta_in(0) <= to_signed(0, metric_t'length);
    beta_in(1) <= to_signed(-4, metric_t'length);
    beta_in(2) <= to_signed(-12, metric_t'length);
    beta_in(3) <= to_signed(-20, metric_t'length);
    beta_in(4) <= to_signed(-28, metric_t'length);
    beta_in(5) <= to_signed(-36, metric_t'length);
    beta_in(6) <= to_signed(-44, metric_t'length);
    beta_in(7) <= to_signed(-52, metric_t'length);

    sys_even <= to_signed(7, chan_llr_t'length);
    sys_odd <= to_signed(-5, chan_llr_t'length);
    par_even <= to_signed(3, chan_llr_t'length);
    par_odd <= to_signed(-2, chan_llr_t'length);
    apri_even <= to_signed(4, ext_llr_t'length);
    apri_odd <= to_signed(-6, ext_llr_t'length);
    wait for 1 ns;

    assert ext_even = to_signed(-17, ext_llr_t'length) report "ext_even nonzero case mismatch" severity error;
    assert ext_odd = to_signed(2, ext_llr_t'length) report "ext_odd nonzero case mismatch" severity error;
    assert post_even = to_signed(-13, post_llr_t'length) report "post_even nonzero case mismatch" severity error;
    assert post_odd = to_signed(-8, post_llr_t'length) report "post_odd nonzero case mismatch" severity error;

    report "tb_radix4_extractor passed" severity note;
    finish;
  end process;
end architecture;
