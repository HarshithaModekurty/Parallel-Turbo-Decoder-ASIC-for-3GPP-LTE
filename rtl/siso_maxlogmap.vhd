library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity siso_maxlogmap is
  generic (
    G_SEG_MAX : natural := 6144;
    G_ADDR_W  : natural := 13
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
  constant C_PAIR_WIN  : natural := C_WINDOW / 2;
  constant C_PAIR_MAX  : natural := (G_SEG_MAX + 1) / 2;
  constant C_MAX_WIN   : natural := (G_SEG_MAX + C_WINDOW - 1) / C_WINDOW;
  constant C_ALPHA_SEED_W : natural := C_NUM_STATES * metric_t'length;
  function clog2(n : natural) return natural is
    variable ret_v : natural := 0;
    variable val_v : natural := 1;
  begin
    while val_v < n loop
      val_v := val_v * 2;
      ret_v := ret_v + 1;
    end loop;
    return ret_v;
  end function;
  constant C_ALPHA_ADDR_W : natural := clog2(C_MAX_WIN);
  subtype seg_bits_t is integer range 0 to G_SEG_MAX;
  subtype pair_idx_t is integer range 0 to C_PAIR_MAX;
  subtype pair_mem_idx_t is integer range 0 to C_PAIR_MAX-1;
  subtype win_idx_t is integer range 0 to C_MAX_WIN;
  subtype alpha_seed_idx_t is integer range 0 to C_MAX_WIN-1;
  subtype local_idx_t is integer range 0 to C_PAIR_WIN;

  type chan_mem_t is array (0 to C_PAIR_MAX-1) of chan_llr_t;
  type ext_mem_t is array (0 to C_PAIR_MAX-1) of ext_llr_t;
  subtype alpha_seed_word_t is signed(C_ALPHA_SEED_W-1 downto 0);
  type alpha_seed_mem_t is array (0 to C_MAX_WIN-1) of alpha_seed_word_t;
  type gamma_local_mem_t is array (0 to C_PAIR_WIN-1) of gamma_vec_t;
  type alpha_local_mem_t is array (0 to C_PAIR_WIN-1) of state_metric_t;
  type chan_local_mem_t is array (0 to C_PAIR_WIN-1) of chan_llr_t;
  type ext_local_mem_t is array (0 to C_PAIR_WIN-1) of ext_llr_t;
  type branch4_t is array (0 to 3) of metric_t;
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
    DUMMY_FWD,
    FWD_SEEDS,
    PREP_WINDOW,
    DUMMY_BWD,
    LOAD_ALPHA_WAIT,
    LOAD_ALPHA,
    LOCAL_FWD,
    LOCAL_BWD,
    FINISH
  );

  function pack_state_metric(v : state_metric_t) return alpha_seed_word_t is
    variable ret : alpha_seed_word_t := (others => '0');
  begin
    for i in 0 to C_NUM_STATES-1 loop
      ret((i + 1) * metric_t'length - 1 downto i * metric_t'length) := v(i);
    end loop;
    return ret;
  end function;

  function unpack_state_metric(v : alpha_seed_word_t) return state_metric_t is
    variable ret : state_metric_t := (others => (others => '0'));
  begin
    for i in 0 to C_NUM_STATES-1 loop
      ret(i) := v((i + 1) * metric_t'length - 1 downto i * metric_t'length);
    end loop;
    return ret;
  end function;

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

  function pair_gamma(
    sys_even_i  : chan_llr_t;
    sys_odd_i   : chan_llr_t;
    par_even_i  : chan_llr_t;
    par_odd_i   : chan_llr_t;
    apri_even_i : ext_llr_t;
    apri_odd_i  : ext_llr_t
  ) return gamma_vec_t is
    variable ret : gamma_vec_t := (others => (others => '0'));
    variable g0, g1 : branch4_t;
    variable idx : natural;
  begin
    g0 := branch_metrics(sys_even_i, par_even_i, apri_even_i);
    g1 := branch_metrics(sys_odd_i, par_odd_i, apri_odd_i);
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

  function extract_pair(
    alpha_in    : state_metric_t;
    beta_in     : state_metric_t;
    sys_even_i  : chan_llr_t;
    sys_odd_i   : chan_llr_t;
    par_even_i  : chan_llr_t;
    par_odd_i   : chan_llr_t;
    apri_even_i : ext_llr_t;
    apri_odd_i  : ext_llr_t
  ) return llr_pair_t is
    variable ret : llr_pair_t;
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
    g0 := branch_metrics(sys_even_i, par_even_i, apri_even_i);
    g1 := branch_metrics(sys_odd_i, par_odd_i, apri_odd_i);

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
  signal beta_seed_reg : state_metric_t := (others => (others => '0'));
  signal alpha_seed_rd_en   : std_logic := '0';
  signal alpha_seed_rd_addr : unsigned(C_ALPHA_ADDR_W-1 downto 0) := (others => '0');
  signal alpha_seed_rd_data : alpha_seed_word_t := (others => '0');
  signal alpha_seed_wr_en   : std_logic := '0';
  signal alpha_seed_wr_addr : unsigned(C_ALPHA_ADDR_W-1 downto 0) := (others => '0');
  signal alpha_seed_wr_data : alpha_seed_word_t := (others => '0');

  signal sys_even_mem, sys_odd_mem : chan_mem_t := (others => (others => '0'));
  signal par_even_mem, par_odd_mem : chan_mem_t := (others => (others => '0'));
  signal apri_even_mem, apri_odd_mem : ext_mem_t := (others => (others => '0'));

  signal gamma_local_mem : gamma_local_mem_t := (others => (others => (others => '0')));
  signal alpha_local_mem : alpha_local_mem_t := (others => (others => (others => '0')));
  signal sys_even_local_mem, sys_odd_local_mem : chan_local_mem_t := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of sys_even_mem : signal is "block";
  attribute ram_style of sys_odd_mem : signal is "block";
  attribute ram_style of par_even_mem : signal is "block";
  attribute ram_style of par_odd_mem : signal is "block";
  attribute ram_style of apri_even_mem : signal is "block";
  attribute ram_style of apri_odd_mem : signal is "block";
  signal par_even_local_mem, par_odd_local_mem : chan_local_mem_t := (others => (others => '0'));
  signal apri_even_local_mem, apri_odd_local_mem : ext_local_mem_t := (others => (others => '0'));

  signal out_valid_q, done_q : std_logic := '0';
  signal out_pair_idx_q : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal ext_even_q, ext_odd_q : ext_llr_t := (others => '0');
  signal post_even_q, post_odd_q : post_llr_t := (others => '0');
begin
  alpha_seed_ram : entity work.simple_dp_bram
    generic map (
      G_DEPTH  => C_MAX_WIN,
      G_ADDR_W => C_ALPHA_ADDR_W,
      G_DATA_W => C_ALPHA_SEED_W
    )
    port map (
      clk     => clk,
      rd_en   => alpha_seed_rd_en,
      rd_addr => alpha_seed_rd_addr,
      rd_data => alpha_seed_rd_data,
      wr_en   => alpha_seed_wr_en,
      wr_addr => alpha_seed_wr_addr,
      wr_data => alpha_seed_wr_data
    );

  process(clk)
    variable global_pair_i : pair_idx_t;
    variable win_pair_cnt_v : pair_idx_t;
    variable next_pair_i : pair_idx_t;
    variable load_pair_i : pair_idx_t;
    variable alpha_next_v, beta_next_v : state_metric_t;
    variable gamma_v : gamma_vec_t;
    variable llr_v : llr_pair_t;
    variable seg_bits_v : seg_bits_t;
    variable frame_read_valid_v : boolean;
    variable frame_read_idx_v : pair_mem_idx_t;
    variable frame_sys_even_v, frame_sys_odd_v : chan_llr_t;
    variable frame_par_even_v, frame_par_odd_v : chan_llr_t;
    variable frame_apri_even_v, frame_apri_odd_v : ext_llr_t;
    variable uniform_v, term_v, start_seed_v, end_seed_v : state_metric_t;
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
        beta_seed_reg <= uniform_state;
        alpha_seed_rd_en <= '0';
        alpha_seed_rd_addr <= (others => '0');
        alpha_seed_wr_en <= '0';
        alpha_seed_wr_addr <= (others => '0');
        alpha_seed_wr_data <= (others => '0');
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
        alpha_seed_rd_en <= '0';
        alpha_seed_wr_en <= '0';
        uniform_v := uniform_state;
        term_v := terminated_state;
        frame_read_valid_v := false;
        frame_read_idx_v := 0;
        frame_sys_even_v := (others => '0');
        frame_sys_odd_v := (others => '0');
        frame_par_even_v := (others => '0');
        frame_par_odd_v := (others => '0');
        frame_apri_even_v := (others => '0');
        frame_apri_odd_v := (others => '0');
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
          when DUMMY_FWD =>
            if window_pairs_for(0, seg_bits_i) > 0 then
              frame_read_valid_v := true;
              frame_read_idx_v := work_local_idx;
            end if;

          when FWD_SEEDS =>
            frame_read_valid_v := true;
            frame_read_idx_v := work_win_idx * C_PAIR_WIN + work_local_idx;

          when DUMMY_BWD =>
            frame_read_valid_v := true;
            frame_read_idx_v := (work_win_idx + 1) * C_PAIR_WIN + work_local_idx;

          when LOCAL_FWD =>
            frame_read_valid_v := true;
            frame_read_idx_v := work_win_idx * C_PAIR_WIN + work_local_idx;

          when others =>
            null;
        end case;

        if frame_read_valid_v then
          frame_sys_even_v := sys_even_mem(frame_read_idx_v);
          frame_sys_odd_v := sys_odd_mem(frame_read_idx_v);
          frame_par_even_v := par_even_mem(frame_read_idx_v);
          frame_par_odd_v := par_odd_mem(frame_read_idx_v);
          frame_apri_even_v := apri_even_mem(frame_read_idx_v);
          frame_apri_odd_v := apri_odd_mem(frame_read_idx_v);
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
                st <= LOAD;
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
                work_local_idx <= 0;
                alpha_work <= start_seed_v;
                st <= DUMMY_FWD;
              else
                load_idx <= load_idx + 1;
              end if;
            end if;

          when DUMMY_FWD =>
            win_pair_cnt_v := window_pairs_for(0, seg_bits_i);
            if win_pair_cnt_v = 0 then
              done_q <= '1';
              st <= IDLE;
            else
              gamma_v := pair_gamma(
                frame_sys_even_v, frame_sys_odd_v,
                frame_par_even_v, frame_par_odd_v,
                frame_apri_even_v, frame_apri_odd_v
              );
              alpha_next_v := acs_step(alpha_work, gamma_v, false);
              alpha_work <= alpha_next_v;
              if work_local_idx = win_pair_cnt_v - 1 then
                alpha_seed_wr_en <= '1';
                alpha_seed_wr_addr <= to_unsigned(0, C_ALPHA_ADDR_W);
                alpha_seed_wr_data <= pack_state_metric(start_seed_v);
                alpha_work <= start_seed_v;
                work_win_idx <= 0;
                work_local_idx <= 0;
                st <= FWD_SEEDS;
              else
                work_local_idx <= work_local_idx + 1;
              end if;
            end if;

          when FWD_SEEDS =>
            win_pair_cnt_v := window_pairs_for(work_win_idx, seg_bits_i);
            global_pair_i := work_win_idx * C_PAIR_WIN + work_local_idx;
            gamma_v := pair_gamma(
              frame_sys_even_v, frame_sys_odd_v,
              frame_par_even_v, frame_par_odd_v,
              frame_apri_even_v, frame_apri_odd_v
            );
            alpha_next_v := acs_step(alpha_work, gamma_v, false);
            alpha_work <= alpha_next_v;
            if work_local_idx = win_pair_cnt_v - 1 then
              if work_win_idx + 1 < win_cnt then
                alpha_seed_wr_en <= '1';
                alpha_seed_wr_addr <= to_unsigned(work_win_idx + 1, C_ALPHA_ADDR_W);
                alpha_seed_wr_data <= pack_state_metric(alpha_next_v);
                work_win_idx <= work_win_idx + 1;
                work_local_idx <= 0;
              else
                work_win_idx <= win_cnt - 1;
                work_local_idx <= 0;
                st <= PREP_WINDOW;
              end if;
            else
              work_local_idx <= work_local_idx + 1;
            end if;

          when PREP_WINDOW =>
            if work_win_idx < win_cnt - 1 then
              work_local_idx <= window_pairs_for(work_win_idx + 1, seg_bits_i) - 1;
              beta_work <= uniform_v;
              st <= DUMMY_BWD;
            else
              beta_seed_reg <= end_seed_v;
              work_local_idx <= 0;
              alpha_seed_rd_en <= '1';
              alpha_seed_rd_addr <= to_unsigned(work_win_idx, C_ALPHA_ADDR_W);
              st <= LOAD_ALPHA_WAIT;
            end if;

          when DUMMY_BWD =>
            next_pair_i := (work_win_idx + 1) * C_PAIR_WIN + work_local_idx;
            gamma_v := pair_gamma(
              frame_sys_even_v, frame_sys_odd_v,
              frame_par_even_v, frame_par_odd_v,
              frame_apri_even_v, frame_apri_odd_v
            );
            beta_next_v := acs_step(beta_work, gamma_v, true);
            beta_work <= beta_next_v;
            if work_local_idx = 0 then
              beta_seed_reg <= beta_next_v;
              work_local_idx <= 0;
              alpha_seed_rd_en <= '1';
              alpha_seed_rd_addr <= to_unsigned(work_win_idx, C_ALPHA_ADDR_W);
              st <= LOAD_ALPHA_WAIT;
            else
              work_local_idx <= work_local_idx - 1;
            end if;

          when LOAD_ALPHA_WAIT =>
            st <= LOAD_ALPHA;

          when LOAD_ALPHA =>
            alpha_work <= unpack_state_metric(alpha_seed_rd_data);
            st <= LOCAL_FWD;

          when LOCAL_FWD =>
            win_pair_cnt_v := window_pairs_for(work_win_idx, seg_bits_i);
            global_pair_i := work_win_idx * C_PAIR_WIN + work_local_idx;
            gamma_v := pair_gamma(
              frame_sys_even_v, frame_sys_odd_v,
              frame_par_even_v, frame_par_odd_v,
              frame_apri_even_v, frame_apri_odd_v
            );
            alpha_local_mem(work_local_idx) <= alpha_work;
            gamma_local_mem(work_local_idx) <= gamma_v;
            sys_even_local_mem(work_local_idx) <= frame_sys_even_v;
            sys_odd_local_mem(work_local_idx) <= frame_sys_odd_v;
            par_even_local_mem(work_local_idx) <= frame_par_even_v;
            par_odd_local_mem(work_local_idx) <= frame_par_odd_v;
            apri_even_local_mem(work_local_idx) <= frame_apri_even_v;
            apri_odd_local_mem(work_local_idx) <= frame_apri_odd_v;
            alpha_next_v := acs_step(alpha_work, gamma_v, false);
            alpha_work <= alpha_next_v;
            if work_local_idx = win_pair_cnt_v - 1 then
              beta_work <= beta_seed_reg;
              work_local_idx <= win_pair_cnt_v - 1;
              st <= LOCAL_BWD;
            else
              work_local_idx <= work_local_idx + 1;
            end if;

          when LOCAL_BWD =>
            global_pair_i := work_win_idx * C_PAIR_WIN + work_local_idx;
            llr_v := extract_pair(
              alpha_local_mem(work_local_idx),
              beta_work,
              sys_even_local_mem(work_local_idx),
              sys_odd_local_mem(work_local_idx),
              par_even_local_mem(work_local_idx),
              par_odd_local_mem(work_local_idx),
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
              if work_win_idx = 0 then
                st <= FINISH;
              else
                work_win_idx <= work_win_idx - 1;
                st <= PREP_WINDOW;
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

  out_valid <= out_valid_q;
  out_pair_idx <= out_pair_idx_q;
  ext_even <= ext_even_q;
  ext_odd <= ext_odd_q;
  post_even <= post_even_q;
  post_odd <= post_odd_q;
  done <= done_q;
end architecture;

