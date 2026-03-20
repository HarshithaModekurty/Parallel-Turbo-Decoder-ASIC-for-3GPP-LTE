library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity branch_metric_unit is
  port (
    l_sys  : in chan_llr_t;
    l_par  : in chan_llr_t;
    l_apri : in ext_llr_t;
    gamma_u0_p0 : out metric_t;
    gamma_u0_p1 : out metric_t;
    gamma_u1_p0 : out metric_t;
    gamma_u1_p1 : out metric_t
  );
end entity;

architecture rtl of branch_metric_unit is
  signal s_sys, s_par : metric_t;
  signal s_ap : metric_t;
begin
  s_sys <= resize_chan_to_metric(l_sys);
  s_par <= resize_chan_to_metric(l_par);
  s_ap  <= resize_ext_to_metric(l_apri);

  gamma_u0_p0 <= shift_right(mod_add(mod_add(s_sys, s_ap), s_par), 1);
  gamma_u0_p1 <= shift_right(mod_add(mod_add(s_sys, s_ap), -s_par), 1);
  gamma_u1_p0 <= shift_right(mod_add(mod_add(-s_sys, -s_ap), s_par), 1);
  gamma_u1_p1 <= shift_right(mod_add(mod_add(-s_sys, -s_ap), -s_par), 1);
end architecture;
