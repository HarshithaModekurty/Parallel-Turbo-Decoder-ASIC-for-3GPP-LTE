library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity radix4_extractor is
  port (
    alpha_in   : in state_metric_t;
    beta_in    : in state_metric_t;
    sys_even   : in chan_llr_t;
    sys_odd    : in chan_llr_t;
    par_even   : in chan_llr_t;
    par_odd    : in chan_llr_t;
    apri_even  : in ext_llr_t;
    apri_odd   : in ext_llr_t;
    ext_even   : out ext_llr_t;
    ext_odd    : out ext_llr_t;
    post_even  : out post_llr_t;
    post_odd   : out post_llr_t
  );
end entity;

architecture rtl of radix4_extractor is
  type branch4_t is array (0 to 3) of metric_t;
  type bool_state_t is array (0 to C_NUM_STATES-1) of boolean;

  function branch_metrics(
    l_sys  : chan_llr_t;
    l_par  : chan_llr_t;
    l_apri : ext_llr_t
  ) return branch4_t is
    variable ret : branch4_t := (others => (others => '0'));
    variable s_sys, s_par, s_ap : metric_t;
  begin
    s_sys := resize_chan_to_metric(l_sys);
    s_par := resize_chan_to_metric(l_par);
    s_ap := resize_ext_to_metric(l_apri);
    ret(0) := shift_right(mod_add(mod_add(s_sys, s_ap), s_par), 1);
    ret(1) := shift_right(mod_add(mod_add(s_sys, s_ap), -s_par), 1);
    ret(2) := shift_right(mod_add(mod_add(-s_sys, -s_ap), s_par), 1);
    ret(3) := shift_right(mod_add(mod_add(-s_sys, -s_ap), -s_par), 1);
    return ret;
  end function;
begin
  process(all)
    variable g0, g1 : branch4_t;
    variable alpha_mid, beta_mid : state_metric_t := (others => C_METRIC_INIT_NEG);
    variable alpha_mid_set, beta_mid_set : bool_state_t := (others => false);
    variable metric_v, post0_v, post1_v, ext0_v, ext1_v : metric_t;
    variable max0_u0, max1_u0, max0_u1, max1_u1 : metric_t := (others => '0');
    variable init0_u0, init1_u0, init0_u1, init1_u1 : boolean := true;
    variable u_sl : std_logic;
    variable mid_s, end_s : natural;
    variable p_bit : natural;
    variable idx : natural;
  begin
    alpha_mid := (others => C_METRIC_INIT_NEG);
    beta_mid := (others => C_METRIC_INIT_NEG);
    alpha_mid_set := (others => false);
    beta_mid_set := (others => false);
    max0_u0 := (others => '0');
    max1_u0 := (others => '0');
    max0_u1 := (others => '0');
    max1_u1 := (others => '0');
    init0_u0 := true;
    init1_u0 := true;
    init0_u1 := true;
    init1_u1 := true;

    g0 := branch_metrics(sys_even, par_even, apri_even);
    g1 := branch_metrics(sys_odd, par_odd, apri_odd);

    for start_s in 0 to C_NUM_STATES-1 loop
      for u in 0 to 1 loop
        if u = 0 then
          u_sl := '0';
        else
          u_sl := '1';
        end if;
        mid_s := rsc_next_state(start_s, u_sl);
        if rsc_parity(start_s, u_sl) = '1' then
          p_bit := 1;
        else
          p_bit := 0;
        end if;
        idx := u * 2 + p_bit;
        metric_v := mod_add(alpha_in(start_s), g0(idx));
        if not alpha_mid_set(mid_s) then
          alpha_mid(mid_s) := metric_v;
          alpha_mid_set(mid_s) := true;
        else
          alpha_mid(mid_s) := mod_max(alpha_mid(mid_s), metric_v);
        end if;
      end loop;
    end loop;

    for mid_idx in 0 to C_NUM_STATES-1 loop
      for u in 0 to 1 loop
        if u = 0 then
          u_sl := '0';
        else
          u_sl := '1';
        end if;
        end_s := rsc_next_state(mid_idx, u_sl);
        if rsc_parity(mid_idx, u_sl) = '1' then
          p_bit := 1;
        else
          p_bit := 0;
        end if;
        idx := u * 2 + p_bit;
        metric_v := mod_add(g1(idx), beta_in(end_s));
        if not beta_mid_set(mid_idx) then
          beta_mid(mid_idx) := metric_v;
          beta_mid_set(mid_idx) := true;
        else
          beta_mid(mid_idx) := mod_max(beta_mid(mid_idx), metric_v);
        end if;
      end loop;
    end loop;

    for start_s in 0 to C_NUM_STATES-1 loop
      for u in 0 to 1 loop
        if u = 0 then
          u_sl := '0';
        else
          u_sl := '1';
        end if;
        mid_s := rsc_next_state(start_s, u_sl);
        if rsc_parity(start_s, u_sl) = '1' then
          p_bit := 1;
        else
          p_bit := 0;
        end if;
        idx := u * 2 + p_bit;
        metric_v := mod_add(mod_add(alpha_in(start_s), g0(idx)), beta_mid(mid_s));
        if u = 0 then
          if init0_u0 then
            max0_u0 := metric_v;
            init0_u0 := false;
          else
            max0_u0 := mod_max(max0_u0, metric_v);
          end if;
        else
          if init1_u0 then
            max1_u0 := metric_v;
            init1_u0 := false;
          else
            max1_u0 := mod_max(max1_u0, metric_v);
          end if;
        end if;
      end loop;
    end loop;

    for mid_idx in 0 to C_NUM_STATES-1 loop
      for u in 0 to 1 loop
        if u = 0 then
          u_sl := '0';
        else
          u_sl := '1';
        end if;
        end_s := rsc_next_state(mid_idx, u_sl);
        if rsc_parity(mid_idx, u_sl) = '1' then
          p_bit := 1;
        else
          p_bit := 0;
        end if;
        idx := u * 2 + p_bit;
        metric_v := mod_add(mod_add(alpha_mid(mid_idx), g1(idx)), beta_in(end_s));
        if u = 0 then
          if init0_u1 then
            max0_u1 := metric_v;
            init0_u1 := false;
          else
            max0_u1 := mod_max(max0_u1, metric_v);
          end if;
        else
          if init1_u1 then
            max1_u1 := metric_v;
            init1_u1 := false;
          else
            max1_u1 := mod_max(max1_u1, metric_v);
          end if;
        end if;
      end loop;
    end loop;

    post0_v := mod_sub(max1_u0, max0_u0);
    post1_v := mod_sub(max1_u1, max0_u1);
    ext0_v := mod_sub(mod_sub(post0_v, resize_chan_to_metric(sys_even)), resize_ext_to_metric(apri_even));
    ext1_v := mod_sub(mod_sub(post1_v, resize_chan_to_metric(sys_odd)), resize_ext_to_metric(apri_odd));

    post_even <= metric_to_post_sat(post0_v);
    post_odd <= metric_to_post_sat(post1_v);
    ext_even <= scale_ext(ext0_v);
    ext_odd <= scale_ext(ext1_v);
  end process;
end architecture;
