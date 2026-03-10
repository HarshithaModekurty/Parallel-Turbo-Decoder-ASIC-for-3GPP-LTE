library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package turbo_pkg is
  constant C_NUM_STATES : natural := 8;
  constant C_TRELLIS_TAIL : natural := 3;

  subtype llr_t is signed(7 downto 0);
  subtype metric_t is signed(11 downto 0);

  type llr_vec_t is array (natural range <>) of llr_t;
  type metric_vec_t is array (natural range <>) of metric_t;
  type state_metric_t is array (0 to C_NUM_STATES-1) of metric_t;

  function sat_add(a, b : metric_t) return metric_t;
  function max2(a, b : metric_t) return metric_t;
  function max8(v : state_metric_t) return metric_t;
  function resize_llr_to_metric(v : llr_t) return metric_t;
  function metric_to_llr_sat(v : metric_t) return llr_t;

  -- LTE constituent code (8-state RSC, feedback 13, feedforward 15 in octal)
  function rsc_next_state(cur_state : natural; u : std_logic) return natural;
  function rsc_parity(cur_state : natural; u : std_logic) return std_logic;
end package;

package body turbo_pkg is
  function sat_add(a, b : metric_t) return metric_t is
    variable ext : signed(metric_t'length downto 0);
    variable res : metric_t;
  begin
    ext := resize(a, ext'length) + resize(b, ext'length);
    if ext(ext'high) /= ext(ext'high-1) then
      if ext(ext'high) = '0' then
        res := (res'high => '0', others => '1');
      else
        res := (res'high => '1', others => '0');
      end if;
    else
      res := ext(res'range);
    end if;
    return res;
  end function;

  function max2(a, b : metric_t) return metric_t is
  begin
    if a > b then
      return a;
    else
      return b;
    end if;
  end function;

  function max8(v : state_metric_t) return metric_t is
    variable m : metric_t := v(0);
  begin
    for i in 1 to C_NUM_STATES-1 loop
      m := max2(m, v(i));
    end loop;
    return m;
  end function;

  function resize_llr_to_metric(v : llr_t) return metric_t is
  begin
    return resize(v, metric_t'length);
  end function;

  function metric_to_llr_sat(v : metric_t) return llr_t is
    constant C_LLR_MAX : integer := 2**(llr_t'length-1)-1;
    constant C_LLR_MIN : integer := -2**(llr_t'length-1);
    variable i : integer;
  begin
    i := to_integer(v);
    if i > C_LLR_MAX then
      return to_signed(C_LLR_MAX, llr_t'length);
    elsif i < C_LLR_MIN then
      return to_signed(C_LLR_MIN, llr_t'length);
    else
      return to_signed(i, llr_t'length);
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
