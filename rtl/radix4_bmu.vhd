library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity radix4_bmu is
  port (
    sys_even  : in chan_llr_t;
    sys_odd   : in chan_llr_t;
    par_even  : in chan_llr_t;
    par_odd   : in chan_llr_t;
    apri_even : in ext_llr_t;
    apri_odd  : in ext_llr_t;
    gamma_out : out gamma_vec_t
  );
end entity;

architecture rtl of radix4_bmu is
  signal g0_u0_p0, g0_u0_p1, g0_u1_p0, g0_u1_p1 : metric_t;
  signal g1_u0_p0, g1_u0_p1, g1_u1_p0, g1_u1_p1 : metric_t;
begin
  bmu_even : entity work.branch_metric_unit
    port map (
      l_sys=>sys_even, l_par=>par_even, l_apri=>apri_even,
      gamma_u0_p0=>g0_u0_p0, gamma_u0_p1=>g0_u0_p1,
      gamma_u1_p0=>g0_u1_p0, gamma_u1_p1=>g0_u1_p1
    );

  bmu_odd : entity work.branch_metric_unit
    port map (
      l_sys=>sys_odd, l_par=>par_odd, l_apri=>apri_odd,
      gamma_u0_p0=>g1_u0_p0, gamma_u0_p1=>g1_u0_p1,
      gamma_u1_p0=>g1_u1_p0, gamma_u1_p1=>g1_u1_p1
    );

  process(all)
    variable g0_v, g1_v : gamma_vec_t;
    variable idx : natural;
    variable p0_sel, p1_sel : natural;
  begin
    g0_v(0) := g0_u0_p0;
    g0_v(1) := g0_u0_p1;
    g0_v(2) := g0_u1_p0;
    g0_v(3) := g0_u1_p1;
    g1_v(0) := g1_u0_p0;
    g1_v(1) := g1_u0_p1;
    g1_v(2) := g1_u1_p0;
    g1_v(3) := g1_u1_p1;

    for u0 in 0 to 1 loop
      for p0 in 0 to 1 loop
        for u1 in 0 to 1 loop
          for p1 in 0 to 1 loop
            idx := (u0 * 8) + (p0 * 4) + (u1 * 2) + p1;
            p0_sel := u0 * 2 + p0;
            p1_sel := u1 * 2 + p1;
            gamma_out(idx) <= mod_add(g0_v(p0_sel), g1_v(p1_sel));
          end loop;
        end loop;
      end loop;
    end loop;
  end process;
end architecture;
