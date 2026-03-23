library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity radix4_acs is
  port (
    state_in  : in  state_metric_t;
    gamma_in  : in  gamma_vec_t;
    mode_bwd  : in  std_logic;
    state_out : out state_metric_t
  );
end entity;

architecture rtl of radix4_acs is
  type path_t is record
    state_idx : natural;
    gamma_idx : natural;
  end record;
  type path_vec_t is array (0 to 3) of path_t;
  type trellis_t is array (0 to C_NUM_STATES-1) of path_vec_t;

  function build_trellis(is_backward : boolean) return trellis_t is
    variable t : trellis_t;
    type cnt_arr_t is array (0 to C_NUM_STATES-1) of natural;
    variable cnt : cnt_arr_t := (others => 0);
    variable mid_s, nxt_s : natural;
    variable g_idx : natural;
    variable u0_sl, u1_sl : std_logic;
  begin
    for start_s in 0 to C_NUM_STATES-1 loop
      for u0 in 0 to 1 loop
        for u1 in 0 to 1 loop
          if u0 = 0 then u0_sl := '0'; else u0_sl := '1'; end if;
          if u1 = 0 then u1_sl := '0'; else u1_sl := '1'; end if;
          mid_s := rsc_next_state(start_s, u0_sl);
          nxt_s := rsc_next_state(mid_s, u1_sl);
          g_idx := radix4_gamma_index(start_s, u0_sl, u1_sl);
          if is_backward then
            t(start_s)(cnt(start_s)).state_idx := nxt_s;
            t(start_s)(cnt(start_s)).gamma_idx := g_idx;
            cnt(start_s) := cnt(start_s) + 1;
          else
            t(nxt_s)(cnt(nxt_s)).state_idx := start_s;
            t(nxt_s)(cnt(nxt_s)).gamma_idx := g_idx;
            cnt(nxt_s) := cnt(nxt_s) + 1;
          end if;
        end loop;
      end loop;
    end loop;
    return t;
  end function;

  constant C_FWD_TRELLIS : trellis_t := build_trellis(false);
  constant C_BWD_TRELLIS : trellis_t := build_trellis(true);
begin
  process(all)
    variable paths : path_vec_t;
    variable m0, m1, m2, m3 : metric_t;
  begin
    for s in 0 to C_NUM_STATES-1 loop
      if mode_bwd = '1' then
        paths := C_BWD_TRELLIS(s);
      else
        paths := C_FWD_TRELLIS(s);
      end if;

      m0 := mod_add(state_in(paths(0).state_idx), gamma_in(paths(0).gamma_idx));
      m1 := mod_add(state_in(paths(1).state_idx), gamma_in(paths(1).gamma_idx));
      m2 := mod_add(state_in(paths(2).state_idx), gamma_in(paths(2).gamma_idx));
      m3 := mod_add(state_in(paths(3).state_idx), gamma_in(paths(3).gamma_idx));
      state_out(s) <= mod_max4(m0, m1, m2, m3);
    end loop;
  end process;
end architecture;
