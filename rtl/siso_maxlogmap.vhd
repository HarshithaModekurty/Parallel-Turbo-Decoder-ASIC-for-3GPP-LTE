library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity siso_maxlogmap is
  generic (
    G_SEG_MAX            : natural := 6144;
    G_ADDR_W             : natural := 13;
    G_USE_EXTERNAL_FETCH : boolean := false
  );
  port (
    clk, rst     : in std_logic;
    start        : in std_logic;
    seg_first    : in std_logic;
    seg_last     : in std_logic;
    seg_len      : in unsigned(G_ADDR_W-1 downto 0);
    in_valid     : in std_logic;
    in_pair_idx  : in unsigned(G_ADDR_W-1 downto 0);
    sys_even     : in chan_llr_t;
    sys_odd      : in chan_llr_t;
    par_even     : in chan_llr_t;
    par_odd      : in chan_llr_t;
    apri_even    : in ext_llr_t;
    apri_odd     : in ext_llr_t;
    fetch_req_valid    : out std_logic;
    fetch_req_pair_idx : out unsigned(G_ADDR_W-1 downto 0);
    fetch_rsp_valid    : in std_logic := '0';
    out_valid    : out std_logic;
    out_pair_idx : out unsigned(G_ADDR_W-1 downto 0);
    ext_even     : out ext_llr_t;
    ext_odd      : out ext_llr_t;
    post_even    : out post_llr_t;
    post_odd     : out post_llr_t;
    done         : out std_logic
  );
end entity;

architecture rtl of siso_maxlogmap is
  constant C_PAIR_WIN : natural := C_WINDOW / 2;
  constant C_PAIR_MAX : natural := (G_SEG_MAX + 1) / 2;
  constant C_MAX_WIN  : natural := (G_SEG_MAX + C_WINDOW - 1) / C_WINDOW;

  subtype seg_bits_t is integer range 0 to G_SEG_MAX;
  subtype pair_idx_t is integer range 0 to C_PAIR_MAX;
  subtype pair_mem_idx_t is integer range 0 to C_PAIR_MAX-1;
  subtype win_idx_t is integer range 0 to C_MAX_WIN;
  subtype local_idx_t is integer range 0 to C_PAIR_WIN;

  type chan_mem_t is array (0 to C_PAIR_MAX-1) of chan_llr_t;
  type ext_mem_t is array (0 to C_PAIR_MAX-1) of ext_llr_t;
  type branch4_t is array (0 to 3) of metric_t;
  type branch_local_mem_t is array (0 to C_PAIR_WIN-1) of branch4_t;
  type gamma_local_mem_t is array (0 to C_PAIR_WIN-1) of gamma_vec_t;
  type alpha_local_mem_t is array (0 to C_PAIR_WIN-1) of state_metric_t;
  type chan_local_mem_t is array (0 to C_PAIR_WIN-1) of chan_llr_t;
  type ext_local_mem_t is array (0 to C_PAIR_WIN-1) of ext_llr_t;
  type bool_state_t is array (0 to C_NUM_STATES-1) of boolean;

  type llr_pair_t is record
    ext_even  : ext_llr_t;
    ext_odd   : ext_llr_t;
    post_even : post_llr_t;
    post_odd  : post_llr_t;
  end record;

  type state_t is (
    IDLE,
    LOAD,
    FWD_REQ,
    FWD_WAIT,
    FWD_STEP,
    DUMMY_REQ,
    DUMMY_WAIT,
    DUMMY_STEP,
    LOCAL_BWD,
    FINISH
  );

  function uniform_state return state_metric_t is
    variable ret : state_metric_t := (others => (others => '0'));
  begin
    return ret;
  end function;

  function terminated_state return state_metric_t is
    variable ret : state_metric_t := (others => C_METRIC_INIT_NEG);
  begin
    ret(0) := (others => '0');
    return ret;
  end function;

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

  function pair_gamma_from_branches(
    g0 : branch4_t;
    g1 : branch4_t
  ) return gamma_vec_t is
    variable ret : gamma_vec_t := (others => (others => '0'));
    variable idx : natural;
  begin
    for u0 in 0 to 1 loop
      for p0 in 0 to 1 loop
        for u1 in 0 to 1 loop
          for p1 in 0 to 1 loop
            idx := (u0 * 8) + (p0 * 4) + (u1 * 2) + p1;
            ret(idx) := mod_add(g0(u0 * 2 + p0), g1(u1 * 2 + p1));
          end loop;
        end loop;
      end loop;
    end loop;
    return ret;
  end function;

  function pair_gamma(
    sys_even_i  : chan_llr_t;
    sys_odd_i   : chan_llr_t;
    par_even_i  : chan_llr_t;
    par_odd_i   : chan_llr_t;
    apri_even_i : ext_llr_t;
    apri_odd_i  : ext_llr_t
  ) return gamma_vec_t is
  begin
    return pair_gamma_from_branches(
      branch_metrics(sys_even_i, par_even_i, apri_even_i),
      branch_metrics(sys_odd_i, par_odd_i, apri_odd_i)
    );
  end function;

  function acs_step(
    state_in    : state_metric_t;
    gamma_in    : gamma_vec_t;
    is_backward : boolean
  ) return state_metric_t is
    variable ret : state_metric_t := (others => (others => '0'));
    variable ret_set : bool_state_t := (others => false);
    variable m0, m1, m2, m3 : metric_t;
    variable u0_sl, u1_sl : std_logic;
    variable mid_s, end_s : natural;
    variable path_s : natural;
    variable path_g : natural;
  begin
    for s in 0 to C_NUM_STATES-1 loop
      m0 := C_METRIC_INIT_NEG;
      m1 := C_METRIC_INIT_NEG;
      m2 := C_METRIC_INIT_NEG;
      m3 := C_METRIC_INIT_NEG;
      for u0 in 0 to 1 loop
        for u1 in 0 to 1 loop
          if u0 = 0 then
            u0_sl := '0';
          else
            u0_sl := '1';
          end if;
          if u1 = 0 then
            u1_sl := '0';
          else
            u1_sl := '1';
          end if;
          mid_s := rsc_next_state(s, u0_sl);
          end_s := rsc_next_state(mid_s, u1_sl);
          if is_backward then
            path_s := end_s;
            path_g := radix4_gamma_index(s, u0_sl, u1_sl);
          else
            path_s := s;
            path_g := radix4_gamma_index(s, u0_sl, u1_sl);
          end if;

          case (u0 * 2 + u1) is
            when 0 => m0 := mod_add(state_in(path_s), gamma_in(path_g));
            when 1 => m1 := mod_add(state_in(path_s), gamma_in(path_g));
            when 2 => m2 := mod_add(state_in(path_s), gamma_in(path_g));
            when others => m3 := mod_add(state_in(path_s), gamma_in(path_g));
          end case;
        end loop;
      end loop;

      if is_backward then
        ret(s) := mod_max4(m0, m1, m2, m3);
      else
        ret(s) := C_METRIC_INIT_NEG;
      end if;
    end loop;

    if not is_backward then
      ret := (others => C_METRIC_INIT_NEG);
      ret_set := (others => false);
      for prev_s in 0 to C_NUM_STATES-1 loop
        for u0 in 0 to 1 loop
          for u1 in 0 to 1 loop
            if u0 = 0 then
              u0_sl := '0';
            else
              u0_sl := '1';
            end if;
            if u1 = 0 then
              u1_sl := '0';
            else
              u1_sl := '1';
            end if;
            mid_s := rsc_next_state(prev_s, u0_sl);
            end_s := rsc_next_state(mid_s, u1_sl);
            path_g := radix4_gamma_index(prev_s, u0_sl, u1_sl);
            if not ret_set(end_s) then
              ret(end_s) := mod_add(state_in(prev_s), gamma_in(path_g));
              ret_set(end_s) := true;
            else
              ret(end_s) := mod_max(ret(end_s), mod_add(state_in(prev_s), gamma_in(path_g)));
            end if;
          end loop;
        end loop;
      end loop;
    end if;

    return ret;
  end function;

  function extract_pair_precomp(
    alpha_in    : state_metric_t;
    beta_in     : state_metric_t;
    g0          : branch4_t;
    g1          : branch4_t;
    sys_even_i  : chan_llr_t;
    sys_odd_i   : chan_llr_t;
    apri_even_i : ext_llr_t;
    apri_odd_i  : ext_llr_t
  ) return llr_pair_t is
    variable ret : llr_pair_t;
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

    for start_s in 0 to C_NUM_STATES-1 loop
      for u in 0 to 1 loop
        if u = 0 then
          u_sl := '0';
        else
          u_sl := '1';
        end if;
        end_s := rsc_next_state(start_s, u_sl);
        if rsc_parity(start_s, u_sl) = '1' then
          p_bit := 1;
        else
          p_bit := 0;
        end if;
        idx := u * 2 + p_bit;
        metric_v := mod_add(g1(idx), beta_in(end_s));
        if not beta_mid_set(start_s) then
          beta_mid(start_s) := metric_v;
          beta_mid_set(start_s) := true;
        else
          beta_mid(start_s) := mod_max(beta_mid(start_s), metric_v);
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
    ext0_v := mod_sub(mod_sub(post0_v, resize_chan_to_metric(sys_even_i)), resize_ext_to_metric(apri_even_i));
    ext1_v := mod_sub(mod_sub(post1_v, resize_chan_to_metric(sys_odd_i)), resize_ext_to_metric(apri_odd_i));

    ret.post_even := metric_to_post_sat(post0_v);
    ret.post_odd := metric_to_post_sat(post1_v);
    ret.ext_even := scale_ext(ext0_v);
    ret.ext_odd := scale_ext(ext1_v);
    return ret;
  end function;

  function window_pairs_for(win_idx : natural; seg_bits_i : natural) return natural is
    variable start_bit : natural := win_idx * C_WINDOW;
    variable rem_bits  : natural := 0;
  begin
    if seg_bits_i <= start_bit then
      return 0;
    end if;
    rem_bits := seg_bits_i - start_bit;
    if rem_bits > C_WINDOW then
      rem_bits := C_WINDOW;
    end if;
    return (rem_bits + 1) / 2;
  end function;

  signal st : state_t := IDLE;
  signal pair_cnt : pair_idx_t := 0;
  signal seg_bits_i : seg_bits_t := 0;
  signal win_cnt : win_idx_t := 0;
  signal load_idx : pair_idx_t := 0;
  signal work_win_idx : win_idx_t := 0;
  signal work_local_idx : local_idx_t := 0;
  signal alpha_work : state_metric_t := (others => (others => '0'));
  signal beta_work : state_metric_t := (others => (others => '0'));
  signal next_alpha_seed_reg : state_metric_t := (others => (others => '0'));

  signal sys_even_mem, sys_odd_mem : chan_mem_t := (others => (others => '0'));
  signal par_even_mem, par_odd_mem : chan_mem_t := (others => (others => '0'));
  signal apri_even_mem, apri_odd_mem : ext_mem_t := (others => (others => '0'));

  signal alpha_local_mem : alpha_local_mem_t := (others => (others => (others => '0')));
  signal gamma_local_mem : gamma_local_mem_t := (others => (others => (others => '0')));
  signal g0_local_mem, g1_local_mem : branch_local_mem_t := (others => (others => (others => '0')));
  signal sys_even_local_mem, sys_odd_local_mem : chan_local_mem_t := (others => (others => '0'));
  signal apri_even_local_mem, apri_odd_local_mem : ext_local_mem_t := (others => (others => '0'));
  signal unused_in_pair_idx_q : unsigned(G_ADDR_W-1 downto 0) := (others => '0');

  signal fetch_req_valid_q : std_logic := '0';
  signal fetch_req_pair_idx_q : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal fetched_sys_even_q, fetched_sys_odd_q : chan_llr_t := (others => '0');
  signal fetched_par_even_q, fetched_par_odd_q : chan_llr_t := (others => '0');
  signal fetched_apri_even_q, fetched_apri_odd_q : ext_llr_t := (others => '0');

  signal out_valid_q, done_q : std_logic := '0';
  signal out_pair_idx_q : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal ext_even_q, ext_odd_q : ext_llr_t := (others => '0');
  signal post_even_q, post_odd_q : post_llr_t := (others => '0');

  attribute ram_style : string;
  attribute ram_style of sys_even_mem : signal is "block";
  attribute ram_style of sys_odd_mem : signal is "block";
  attribute ram_style of par_even_mem : signal is "block";
  attribute ram_style of par_odd_mem : signal is "block";
  attribute ram_style of apri_even_mem : signal is "block";
  attribute ram_style of apri_odd_mem : signal is "block";
  attribute keep : string;
  attribute keep of unused_in_pair_idx_q : signal is "true";
begin
  process(clk)
    variable global_pair_i : pair_idx_t;
    variable win_pair_cnt_v : pair_idx_t;
    variable next_win_pair_cnt_v : pair_idx_t;
    variable load_pair_i : pair_idx_t;
    variable alpha_next_v, beta_next_v : state_metric_t;
    variable gamma_v : gamma_vec_t;
    variable g0_v, g1_v : branch4_t;
    variable llr_v : llr_pair_t;
    variable seg_bits_v : seg_bits_t;
    variable start_seed_v, end_seed_v, uniform_v, term_v : state_metric_t;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= IDLE;
        pair_cnt <= 0;
        seg_bits_i <= 0;
        win_cnt <= 0;
        load_idx <= 0;
        work_win_idx <= 0;
        work_local_idx <= 0;
        alpha_work <= uniform_state;
        beta_work <= uniform_state;
        next_alpha_seed_reg <= uniform_state;
        fetched_sys_even_q <= (others => '0');
        fetched_sys_odd_q <= (others => '0');
        fetched_par_even_q <= (others => '0');
        fetched_par_odd_q <= (others => '0');
        fetched_apri_even_q <= (others => '0');
        fetched_apri_odd_q <= (others => '0');
        unused_in_pair_idx_q <= (others => '0');
        fetch_req_valid_q <= '0';
        fetch_req_pair_idx_q <= (others => '0');
        out_valid_q <= '0';
        done_q <= '0';
        out_pair_idx_q <= (others => '0');
        ext_even_q <= (others => '0');
        ext_odd_q <= (others => '0');
        post_even_q <= (others => '0');
        post_odd_q <= (others => '0');
      else
        out_valid_q <= '0';
        done_q <= '0';
        fetch_req_valid_q <= '0';
        if G_USE_EXTERNAL_FETCH then
          unused_in_pair_idx_q <= in_pair_idx;
        end if;

        uniform_v := uniform_state;
        term_v := terminated_state;
        if seg_first = '1' then
          start_seed_v := term_v;
        else
          start_seed_v := uniform_v;
        end if;
        if seg_last = '1' then
          end_seed_v := term_v;
        else
          end_seed_v := uniform_v;
        end if;

        case st is
          when IDLE =>
            if start = '1' then
              if to_integer(seg_len) > G_SEG_MAX then
                seg_bits_v := G_SEG_MAX;
              else
                seg_bits_v := to_integer(seg_len);
              end if;
              if seg_bits_v <= 0 then
                done_q <= '1';
              else
                seg_bits_i <= seg_bits_v;
                pair_cnt <= (seg_bits_v + 1) / 2;
                win_cnt <= (seg_bits_v + C_WINDOW - 1) / C_WINDOW;
                load_idx <= 0;
                work_win_idx <= 0;
                work_local_idx <= 0;
                alpha_work <= start_seed_v;
                next_alpha_seed_reg <= start_seed_v;
                if G_USE_EXTERNAL_FETCH then
                  st <= FWD_REQ;
                else
                  st <= LOAD;
                end if;
              end if;
            end if;

          when LOAD =>
            if in_valid = '1' then
              if to_integer(in_pair_idx) < pair_cnt then
                load_pair_i := to_integer(in_pair_idx);
                sys_even_mem(load_pair_i) <= sys_even;
                sys_odd_mem(load_pair_i) <= sys_odd;
                par_even_mem(load_pair_i) <= par_even;
                par_odd_mem(load_pair_i) <= par_odd;
                apri_even_mem(load_pair_i) <= apri_even;
                apri_odd_mem(load_pair_i) <= apri_odd;
              end if;

              if load_idx = pair_cnt - 1 then
                work_win_idx <= 0;
                work_local_idx <= 0;
                alpha_work <= start_seed_v;
                next_alpha_seed_reg <= start_seed_v;
                st <= FWD_REQ;
              else
                load_idx <= load_idx + 1;
              end if;
            end if;

          when FWD_REQ =>
            global_pair_i := work_win_idx * C_PAIR_WIN + work_local_idx;
            if G_USE_EXTERNAL_FETCH then
              fetch_req_valid_q <= '1';
              fetch_req_pair_idx_q <= to_unsigned(global_pair_i, G_ADDR_W);
              st <= FWD_WAIT;
            else
              fetched_sys_even_q <= sys_even_mem(global_pair_i);
              fetched_sys_odd_q <= sys_odd_mem(global_pair_i);
              fetched_par_even_q <= par_even_mem(global_pair_i);
              fetched_par_odd_q <= par_odd_mem(global_pair_i);
              fetched_apri_even_q <= apri_even_mem(global_pair_i);
              fetched_apri_odd_q <= apri_odd_mem(global_pair_i);
              st <= FWD_STEP;
            end if;

          when FWD_WAIT =>
            if fetch_rsp_valid = '1' then
              fetched_sys_even_q <= sys_even;
              fetched_sys_odd_q <= sys_odd;
              fetched_par_even_q <= par_even;
              fetched_par_odd_q <= par_odd;
              fetched_apri_even_q <= apri_even;
              fetched_apri_odd_q <= apri_odd;
              st <= FWD_STEP;
            end if;

          when FWD_STEP =>
            win_pair_cnt_v := window_pairs_for(work_win_idx, seg_bits_i);
            g0_v := branch_metrics(fetched_sys_even_q, fetched_par_even_q, fetched_apri_even_q);
            g1_v := branch_metrics(fetched_sys_odd_q, fetched_par_odd_q, fetched_apri_odd_q);
            gamma_v := pair_gamma_from_branches(g0_v, g1_v);

            alpha_local_mem(work_local_idx) <= alpha_work;
            gamma_local_mem(work_local_idx) <= gamma_v;
            g0_local_mem(work_local_idx) <= g0_v;
            g1_local_mem(work_local_idx) <= g1_v;
            sys_even_local_mem(work_local_idx) <= fetched_sys_even_q;
            sys_odd_local_mem(work_local_idx) <= fetched_sys_odd_q;
            apri_even_local_mem(work_local_idx) <= fetched_apri_even_q;
            apri_odd_local_mem(work_local_idx) <= fetched_apri_odd_q;

            alpha_next_v := acs_step(alpha_work, gamma_v, false);
            alpha_work <= alpha_next_v;

            if work_local_idx = win_pair_cnt_v - 1 then
              next_alpha_seed_reg <= alpha_next_v;
              if work_win_idx = win_cnt - 1 then
                beta_work <= end_seed_v;
                work_local_idx <= win_pair_cnt_v - 1;
                st <= LOCAL_BWD;
              else
                next_win_pair_cnt_v := window_pairs_for(work_win_idx + 1, seg_bits_i);
                beta_work <= uniform_v;
                work_local_idx <= next_win_pair_cnt_v - 1;
                st <= DUMMY_REQ;
              end if;
            else
              work_local_idx <= work_local_idx + 1;
              st <= FWD_REQ;
            end if;

          when DUMMY_REQ =>
            global_pair_i := (work_win_idx + 1) * C_PAIR_WIN + work_local_idx;
            if G_USE_EXTERNAL_FETCH then
              fetch_req_valid_q <= '1';
              fetch_req_pair_idx_q <= to_unsigned(global_pair_i, G_ADDR_W);
              st <= DUMMY_WAIT;
            else
              fetched_sys_even_q <= sys_even_mem(global_pair_i);
              fetched_sys_odd_q <= sys_odd_mem(global_pair_i);
              fetched_par_even_q <= par_even_mem(global_pair_i);
              fetched_par_odd_q <= par_odd_mem(global_pair_i);
              fetched_apri_even_q <= apri_even_mem(global_pair_i);
              fetched_apri_odd_q <= apri_odd_mem(global_pair_i);
              st <= DUMMY_STEP;
            end if;

          when DUMMY_WAIT =>
            if fetch_rsp_valid = '1' then
              fetched_sys_even_q <= sys_even;
              fetched_sys_odd_q <= sys_odd;
              fetched_par_even_q <= par_even;
              fetched_par_odd_q <= par_odd;
              fetched_apri_even_q <= apri_even;
              fetched_apri_odd_q <= apri_odd;
              st <= DUMMY_STEP;
            end if;

          when DUMMY_STEP =>
            g0_v := branch_metrics(fetched_sys_even_q, fetched_par_even_q, fetched_apri_even_q);
            g1_v := branch_metrics(fetched_sys_odd_q, fetched_par_odd_q, fetched_apri_odd_q);
            gamma_v := pair_gamma_from_branches(g0_v, g1_v);
            beta_next_v := acs_step(beta_work, gamma_v, true);
            beta_work <= beta_next_v;

            if work_local_idx = 0 then
              win_pair_cnt_v := window_pairs_for(work_win_idx, seg_bits_i);
              beta_work <= beta_next_v;
              work_local_idx <= win_pair_cnt_v - 1;
              st <= LOCAL_BWD;
            else
              work_local_idx <= work_local_idx - 1;
              st <= DUMMY_REQ;
            end if;

          when LOCAL_BWD =>
            global_pair_i := work_win_idx * C_PAIR_WIN + work_local_idx;
            llr_v := extract_pair_precomp(
              alpha_local_mem(work_local_idx),
              beta_work,
              g0_local_mem(work_local_idx),
              g1_local_mem(work_local_idx),
              sys_even_local_mem(work_local_idx),
              sys_odd_local_mem(work_local_idx),
              apri_even_local_mem(work_local_idx),
              apri_odd_local_mem(work_local_idx)
            );
            out_valid_q <= '1';
            out_pair_idx_q <= to_unsigned(global_pair_i, G_ADDR_W);
            ext_even_q <= llr_v.ext_even;
            ext_odd_q <= llr_v.ext_odd;
            post_even_q <= llr_v.post_even;
            post_odd_q <= llr_v.post_odd;

            beta_next_v := acs_step(beta_work, gamma_local_mem(work_local_idx), true);
            beta_work <= beta_next_v;
            if work_local_idx = 0 then
              if work_win_idx = win_cnt - 1 then
                st <= FINISH;
              else
                work_win_idx <= work_win_idx + 1;
                work_local_idx <= 0;
                alpha_work <= next_alpha_seed_reg;
                st <= FWD_REQ;
              end if;
            else
              work_local_idx <= work_local_idx - 1;
            end if;

          when FINISH =>
            done_q <= '1';
            st <= IDLE;

          when others =>
            st <= IDLE;
        end case;
      end if;
    end if;
  end process;

  fetch_req_valid <= fetch_req_valid_q;
  fetch_req_pair_idx <= fetch_req_pair_idx_q;
  out_valid <= out_valid_q;
  out_pair_idx <= out_pair_idx_q;
  ext_even <= ext_even_q;
  ext_odd <= ext_odd_q;
  post_even <= post_even_q;
  post_odd <= post_odd_q;
  done <= done_q;
end architecture;
