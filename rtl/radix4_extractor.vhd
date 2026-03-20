library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity radix4_extractor is
  port (
    alpha_in   : in state_metric_t;
    beta_in    : in state_metric_t;
    gamma_in   : in gamma_vec_t;
    sys_even   : in chan_llr_t;
    sys_odd    : in chan_llr_t;
    apri_even  : in ext_llr_t;
    apri_odd   : in ext_llr_t;
    ext_even   : out ext_llr_t;
    ext_odd    : out ext_llr_t;
    post_even  : out post_llr_t;
    post_odd   : out post_llr_t
  );
end entity;

architecture rtl of radix4_extractor is
  type path_t is record
    start_idx : natural;
    gamma_idx : natural;
    end_idx   : natural;
    u0_bit    : natural;
    u1_bit    : natural;
  end record;
  type path_vec_t is array (0 to 31) of path_t;

  function build_paths return path_vec_t is
    variable t : path_vec_t;
    variable idx : natural := 0;
    variable nxt_s : natural;
    variable u0_sl, u1_sl : std_logic;
  begin
    for start_s in 0 to C_NUM_STATES-1 loop
      for u0 in 0 to 1 loop
        for u1 in 0 to 1 loop
          if u0 = 0 then u0_sl := '0'; else u0_sl := '1'; end if;
          if u1 = 0 then u1_sl := '0'; else u1_sl := '1'; end if;
          nxt_s := radix4_next_state(start_s, u0_sl, u1_sl);
          t(idx).start_idx := start_s;
          t(idx).gamma_idx := radix4_gamma_index(start_s, u0_sl, u1_sl);
          t(idx).end_idx := nxt_s;
          t(idx).u0_bit := u0;
          t(idx).u1_bit := u1;
          idx := idx + 1;
        end loop;
      end loop;
    end loop;
    return t;
  end function;

  constant C_PATHS : path_vec_t := build_paths;
begin
  process(all)
    variable metric_v : metric_t;
    variable max0_u0, max1_u0, max0_u1, max1_u1 : metric_t;
    variable init0_u0, init1_u0, init0_u1, init1_u1 : boolean;
    variable post0_v, post1_v : metric_t;
    variable ext0_v, ext1_v : metric_t;
  begin
    init0_u0 := true;
    init1_u0 := true;
    init0_u1 := true;
    init1_u1 := true;
    max0_u0 := (others => '0');
    max1_u0 := (others => '0');
    max0_u1 := (others => '0');
    max1_u1 := (others => '0');

    for i in 0 to 31 loop
      metric_v := mod_add(mod_add(alpha_in(C_PATHS(i).start_idx), gamma_in(C_PATHS(i).gamma_idx)), beta_in(C_PATHS(i).end_idx));
      if C_PATHS(i).u0_bit = 0 then
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

      if C_PATHS(i).u1_bit = 0 then
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
