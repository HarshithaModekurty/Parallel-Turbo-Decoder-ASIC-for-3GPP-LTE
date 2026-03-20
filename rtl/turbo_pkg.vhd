library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package turbo_pkg is
  constant C_NUM_STATES   : natural := 8;
  constant C_PARALLEL     : natural := 8;
  constant C_WINDOW       : natural := 30;
  constant C_TRELLIS_TAIL : natural := 3;
  constant C_ROUTER_SEL_W : natural := 3;

  subtype chan_llr_t is signed(4 downto 0);
  subtype llr_t is chan_llr_t;
  subtype ext_llr_t is signed(5 downto 0);
  subtype post_llr_t is signed(6 downto 0);
  subtype metric_t is signed(9 downto 0);

  constant C_CHAN_LLR_MIN : integer := -16;
  constant C_CHAN_LLR_MAX : integer := 15;
  constant C_EXT_LLR_MIN  : integer := -32;
  constant C_EXT_LLR_MAX  : integer := 31;
  constant C_POST_LLR_MIN : integer := -64;
  constant C_POST_LLR_MAX : integer := 63;
  constant C_METRIC_INIT_NEG : metric_t := to_signed(-256, metric_t'length);

  type chan_llr_vec_t is array (natural range <>) of chan_llr_t;
  type ext_llr_vec_t is array (natural range <>) of ext_llr_t;
  type post_llr_vec_t is array (natural range <>) of post_llr_t;
  type metric_vec_t is array (natural range <>) of metric_t;
  type state_metric_t is array (0 to C_NUM_STATES-1) of metric_t;
  type gamma_vec_t is array (0 to 15) of metric_t;

  function sat_chan(i : integer) return chan_llr_t;
  function sat_ext(i : integer) return ext_llr_t;
  function sat_post(i : integer) return post_llr_t;

  function resize_chan_to_metric(v : chan_llr_t) return metric_t;
  function resize_ext_to_metric(v : ext_llr_t) return metric_t;
  function metric_to_ext_sat(v : metric_t) return ext_llr_t;
  function metric_to_post_sat(v : metric_t) return post_llr_t;
  function scale_ext(v : metric_t) return ext_llr_t;

  function mod_add(a, b : metric_t) return metric_t;
  function mod_sub(a, b : metric_t) return metric_t;
  function mod_max(a, b : metric_t) return metric_t;
  function mod_max4(a, b, c, d : metric_t) return metric_t;

  function max2(a, b : metric_t) return metric_t;
  function max8(v : state_metric_t) return metric_t;

  function rsc_next_state(cur_state : natural; u : std_logic) return natural;
  function rsc_parity(cur_state : natural; u : std_logic) return std_logic;
  function radix4_next_state(cur_state : natural; u0, u1 : std_logic) return natural;
  function radix4_gamma_index(cur_state : natural; u0, u1 : std_logic) return natural;
  function qpp_value(idx_i, k_i, f1_i, f2_i : natural) return natural;
end package;

package body turbo_pkg is
  function sat_chan(i : integer) return chan_llr_t is
  begin
    if i > C_CHAN_LLR_MAX then
      return to_signed(C_CHAN_LLR_MAX, chan_llr_t'length);
    elsif i < C_CHAN_LLR_MIN then
      return to_signed(C_CHAN_LLR_MIN, chan_llr_t'length);
    else
      return to_signed(i, chan_llr_t'length);
    end if;
  end function;

  function sat_ext(i : integer) return ext_llr_t is
  begin
    if i > C_EXT_LLR_MAX then
      return to_signed(C_EXT_LLR_MAX, ext_llr_t'length);
    elsif i < C_EXT_LLR_MIN then
      return to_signed(C_EXT_LLR_MIN, ext_llr_t'length);
    else
      return to_signed(i, ext_llr_t'length);
    end if;
  end function;

  function sat_post(i : integer) return post_llr_t is
  begin
    if i > C_POST_LLR_MAX then
      return to_signed(C_POST_LLR_MAX, post_llr_t'length);
    elsif i < C_POST_LLR_MIN then
      return to_signed(C_POST_LLR_MIN, post_llr_t'length);
    else
      return to_signed(i, post_llr_t'length);
    end if;
  end function;

  function resize_chan_to_metric(v : chan_llr_t) return metric_t is
  begin
    return resize(v, metric_t'length);
  end function;

  function resize_ext_to_metric(v : ext_llr_t) return metric_t is
  begin
    return resize(v, metric_t'length);
  end function;

  function metric_to_ext_sat(v : metric_t) return ext_llr_t is
  begin
    return sat_ext(to_integer(v));
  end function;

  function metric_to_post_sat(v : metric_t) return post_llr_t is
  begin
    return sat_post(to_integer(v));
  end function;

  function scale_ext(v : metric_t) return ext_llr_t is
    variable wide_v : signed(metric_t'length+4 downto 0);
    variable scaled : signed(metric_t'length+4 downto 0);
  begin
    wide_v := resize(v, wide_v'length);
    scaled := shift_left(wide_v, 3) + shift_left(wide_v, 1) + wide_v;
    scaled := shift_right(scaled, 4);
    return sat_ext(to_integer(scaled));
  end function;

  function mod_add(a, b : metric_t) return metric_t is
  begin
    return a + b;
  end function;

  function mod_sub(a, b : metric_t) return metric_t is
  begin
    return a - b;
  end function;

  function mod_max(a, b : metric_t) return metric_t is
    variable diff : metric_t;
  begin
    diff := a - b;
    if diff(diff'high) = '0' then
      return a;
    else
      return b;
    end if;
  end function;

  function mod_max4(a, b, c, d : metric_t) return metric_t is
  begin
    return mod_max(mod_max(a, b), mod_max(c, d));
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

  function rsc_next_state(cur_state : natural; u : std_logic) return natural is
    variable s0, s1, s2, fb : std_logic;
    variable ns : unsigned(2 downto 0);
  begin
    if (cur_state mod 2) = 1 then s0 := '1'; else s0 := '0'; end if;
    if ((cur_state / 2) mod 2) = 1 then s1 := '1'; else s1 := '0'; end if;
    if ((cur_state / 4) mod 2) = 1 then s2 := '1'; else s2 := '0'; end if;
    fb := u xor s0 xor s2;
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
    return fb xor s1 xor s2;
  end function;

  function radix4_next_state(cur_state : natural; u0, u1 : std_logic) return natural is
    variable mid_s : natural;
  begin
    mid_s := rsc_next_state(cur_state, u0);
    return rsc_next_state(mid_s, u1);
  end function;

  function radix4_gamma_index(cur_state : natural; u0, u1 : std_logic) return natural is
    variable mid_s : natural;
    variable p0, p1 : std_logic;
    variable u0_bit, u1_bit : natural := 0;
    variable p0_bit, p1_bit : natural := 0;
  begin
    mid_s := rsc_next_state(cur_state, u0);
    p0 := rsc_parity(cur_state, u0);
    p1 := rsc_parity(mid_s, u1);

    if u0 = '1' then u0_bit := 1; end if;
    if u1 = '1' then u1_bit := 1; end if;
    if p0 = '1' then p0_bit := 1; end if;
    if p1 = '1' then p1_bit := 1; end if;

    return (u0_bit * 8) + (p0_bit * 4) + (u1_bit * 2) + p1_bit;
  end function;

  function qpp_value(idx_i, k_i, f1_i, f2_i : natural) return natural is
    function mod_mult(a_i, b_i, mod_i : natural) return natural is
      constant C_MAX_BITS : natural := 16;
      variable a_v : natural := 0;
      variable b_v : natural := b_i;
      variable acc_v : natural := 0;
    begin
      if mod_i = 0 then
        return 0;
      end if;

      a_v := a_i mod mod_i;
      for bit_idx in 0 to C_MAX_BITS-1 loop
        exit when b_v = 0;
        if (b_v mod 2) = 1 then
          acc_v := acc_v + a_v;
          if acc_v >= mod_i then
            acc_v := acc_v - mod_i;
          end if;
        end if;

        b_v := b_v / 2;
        if b_v > 0 then
          a_v := a_v + a_v;
          if a_v >= mod_i then
            a_v := a_v - mod_i;
          end if;
        end if;
      end loop;

      return acc_v;
    end function;

    variable term1_v : natural := 0;
    variable term2_v : natural := 0;
    variable idx_sq_v : natural := 0;
    variable sum_v : natural := 0;
  begin
    if k_i = 0 then
      return 0;
    end if;

    term1_v := mod_mult(f1_i, idx_i, k_i);
    idx_sq_v := mod_mult(idx_i, idx_i, k_i);
    term2_v := mod_mult(f2_i, idx_sq_v, k_i);
    sum_v := term1_v + term2_v;
    if sum_v >= k_i then
      sum_v := sum_v - k_i;
    end if;
    return sum_v;
  end function;
end package body;
