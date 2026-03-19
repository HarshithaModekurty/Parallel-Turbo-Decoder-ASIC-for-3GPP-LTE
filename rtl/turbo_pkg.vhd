library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package turbo_pkg is
  constant C_NUM_STATES : natural := 8;
  constant C_TRELLIS_TAIL : natural := 3;

  subtype llr_t is signed(4 downto 0);      -- 5-bit input LLRs
  subtype ext_llr_t is signed(5 downto 0);  -- 6-bit Ext LLRs
  subtype metric_t is signed(9 downto 0);   -- 10-bit metrics

  type llr_vec_t is array (natural range <>) of llr_t;
  type ext_llr_vec_t is array (natural range <>) of ext_llr_t;
  type metric_vec_t is array (natural range <>) of metric_t;
  type state_metric_t is array (0 to C_NUM_STATES-1) of metric_t;

  -- Modulo arithmetic for state-metric wrap-around handling without normalization
  function mod_add(a, b : metric_t) return metric_t;
  function mod_max(a, b : metric_t) return metric_t;

  -- LTE constituent code (8-state RSC, feedback 13, feedforward 15 in octal)
  function rsc_next_state(cur_state : natural; u : std_logic) return natural;
  function rsc_parity(cur_state : natural; u : std_logic) return std_logic;
end package;

package body turbo_pkg is
  -- Two's complement modulo addition
  function mod_add(a, b : metric_t) return metric_t is
  begin
    return a + b; -- Wrap-around is standard VHDL behavior for signed
  end function;

  -- Two's complement modulo max: compares based on the sign of the difference
  function mod_max(a, b : metric_t) return metric_t is
    variable diff : metric_t;
  begin
    diff := a - b;
    -- If difference is positive or zero (sign bit = '0'), a >= b in modulo space
    if diff(diff'high) = '0' then
      return a;
    else
      return b;
    end if;
  end function;

  function rsc_next_state(cur_state : natural; u : std_logic) return natural is
    variable s0, s1, s2, fb : std_logic;
    variable ns : unsigned(2 downto 0);
  begin
    if (cur_state mod 2) = 1 then s0 := '1'; else s0 := '0'; end if;
    if ((cur_state / 2) mod 2) = 1 then s1 := '1'; else s1 := '0'; end if;
    if ((cur_state / 4) mod 2) = 1 then s2 := '1'; else s2 := '0'; end if;
    fb := u xor s0 xor s2; -- feedback polynomial 13(oct)=1+D^2+D^3
    ns(2) := fb;
    ns(1) := s2;
    ns(0) := s1;
    return to_integer(ns);
  end function;

  function rsc_parity(cur_state : natural; u : std_logic) return std_logic is
    variable s0, s1, s2, fb : std_logic;
  begin
    if (cur_state mod 2) = 1 then s0 := '1'; else s0 := '0'; end if;
    if ((cur_state / 2) mod 2) = 1 then s1 := '1'; else s1 := '0'; end if;
    if ((cur_state / 4) mod 2) = 1 then s2 := '1'; else s2 := '0'; end if;
    fb := u xor s0 xor s2;
    return fb xor s1 xor s2; -- feedforward polynomial 15(oct)=1+D+D^2+D^3
  end function;
end package body;
