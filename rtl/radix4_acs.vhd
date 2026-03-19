library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

-- Radix-4 Add-Compare-Select Unit
-- Computes the next state metrics for an 8-state Radix-4 trellis stage
-- Utilizes modulo arithmetic normalization logic
entity radix4_acs is
  port (
    state_in  : in  state_metric_t;
    gamma_in  : in  metric_vec_t(0 to 15);
    mode_bwd  : in  std_logic; -- '0' = Forward (Alpha), '1' = Backward (Beta)
    state_out : out state_metric_t
  );
end entity;

architecture rtl of radix4_acs is

  type r4_path_t is record
    state_idx : natural;
    gamma_idx : natural;
  end record;
  type r4_path_array_t is array(0 to 3) of r4_path_t;
  type r4_trellis_t is array(0 to 7) of r4_path_array_t;

  -- 4-way modulo max function
  function mod_max4(a, b, c, d : metric_t) return metric_t is
  begin
    return mod_max(mod_max(a, b), mod_max(c, d));
  end function;

  -- Build the Radix-4 Trellis dynamically for synthesis constants
  function build_trellis(is_backward : boolean) return r4_trellis_t is
    variable t : r4_trellis_t;
    type idx_array_t is array(0 to 7) of natural;
    variable idx_count : idx_array_t := (others => 0);
    variable mid_s, nxt_s : natural;
    variable p0, p1 : std_logic;
    variable g_idx : natural;
    variable u0_bit, u1_bit : natural;
    variable p0_bit, p1_bit : natural;
  begin
    for start_s in 0 to 7 loop
      for u0_bit in 0 to 1 loop
        for u1_bit in 0 to 1 loop
          -- Determine bits
          if u0_bit = 1 then p0 := rsc_parity(start_s, '1'); mid_s := rsc_next_state(start_s, '1');
          else p0 := rsc_parity(start_s, '0'); mid_s := rsc_next_state(start_s, '0'); end if;

          if u1_bit = 1 then p1 := rsc_parity(mid_s, '1'); nxt_s := rsc_next_state(mid_s, '1');
          else p1 := rsc_parity(mid_s, '0'); nxt_s := rsc_next_state(mid_s, '0'); end if;

          if p0 = '1' then p0_bit := 1; else p0_bit := 0; end if;
          if p1 = '1' then p1_bit := 1; else p1_bit := 0; end if;

          g_idx := (u0_bit * 8) + (p0_bit * 4) + (u1_bit * 2) + p1_bit;

          if is_backward then
            -- For beta recursion, from state `start_s` we look at next state `nxt_s`
            t(start_s)(idx_count(start_s)).state_idx := nxt_s;
            t(start_s)(idx_count(start_s)).gamma_idx := g_idx;
            idx_count(start_s) := idx_count(start_s) + 1;
          else
            -- For alpha recursion, state `nxt_s` looks backward to `start_s`
            t(nxt_s)(idx_count(nxt_s)).state_idx := start_s;
            t(nxt_s)(idx_count(nxt_s)).gamma_idx := g_idx;
            idx_count(nxt_s) := idx_count(nxt_s) + 1;
          end if;
        end loop;
      end loop;
    end loop;
    return t;
  end function;

  constant C_FWD_TRELLIS : r4_trellis_t := build_trellis(false);
  constant C_BWD_TRELLIS : r4_trellis_t := build_trellis(true);

begin
  process(all)
    variable paths : r4_path_array_t;
    variable m0, m1, m2, m3 : metric_t;
  begin
    for target_s in 0 to 7 loop
      -- Multiplex forward/backward trellis based on mode_bwd
      if mode_bwd = '0' then
        paths := C_FWD_TRELLIS(target_s);
      else
        paths := C_BWD_TRELLIS(target_s);
      end if;

      -- Load metrics for the 4 converging paths
      m0 := mod_add(state_in(paths(0).state_idx), gamma_in(paths(0).gamma_idx));
      m1 := mod_add(state_in(paths(1).state_idx), gamma_in(paths(1).gamma_idx));
      m2 := mod_add(state_in(paths(2).state_idx), gamma_in(paths(2).gamma_idx));
      m3 := mod_add(state_in(paths(3).state_idx), gamma_in(paths(3).gamma_idx));

      -- Compare and select max
      state_out(target_s) <= mod_max4(m0, m1, m2, m3);
    end loop;
  end process;

end architecture;