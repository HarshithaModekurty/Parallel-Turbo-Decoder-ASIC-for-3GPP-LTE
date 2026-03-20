library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity turbo_decoder_top is
  generic (
    G_K_MAX  : natural := 6144;
    G_ADDR_W : natural := 13
  );
  port (
    clk, rst : in std_logic;
    start : in std_logic;
    n_half_iter : in unsigned(4 downto 0);
    k_len  : in unsigned(G_ADDR_W-1 downto 0);
    f1, f2 : in unsigned(G_ADDR_W-1 downto 0);
    in_valid : in std_logic;
    in_idx : in unsigned(G_ADDR_W-1 downto 0);
    l_sys_in, l_par1_in, l_par2_in : in chan_llr_t;
    out_valid : out std_logic;
    out_idx   : out unsigned(G_ADDR_W-1 downto 0);
    l_post    : out post_llr_t;
    done      : out std_logic
  );
end entity;

architecture rtl of turbo_decoder_top is
  constant C_CORES   : natural := C_PARALLEL;
  constant C_SEG_MAX : natural := (G_K_MAX + C_CORES - 1) / C_CORES;
  constant C_PAIR_MAX : natural := (C_SEG_MAX + 1) / 2;

  type chan_row_t is array (0 to C_CORES-1) of chan_llr_t;
  type ext_row_t  is array (0 to C_CORES-1) of ext_llr_t;
  type post_row_t is array (0 to C_CORES-1) of post_llr_t;
  type chan_mem_t is array (0 to C_PAIR_MAX-1) of chan_row_t;
  type ext_mem_t  is array (0 to C_PAIR_MAX-1) of ext_row_t;
  type post_mem_t is array (0 to C_PAIR_MAX-1) of post_row_t;
  type addr_arr_t is array (0 to C_CORES-1) of unsigned(G_ADDR_W-1 downto 0);
  type perm_mem_t is array (0 to C_PAIR_MAX-1) of unsigned(C_CORES*C_ROUTER_SEL_W-1 downto 0);
  type rowbase_mem_t is array (0 to C_PAIR_MAX-1) of unsigned(G_ADDR_W-1 downto 0);

  subtype chan_bus_t is signed(C_CORES*chan_llr_t'length-1 downto 0);
  subtype ext_bus_t  is signed(C_CORES*ext_llr_t'length-1 downto 0);
  subtype post_bus_t is signed(C_CORES*post_llr_t'length-1 downto 0);

  function pack_chan_row(v : chan_row_t) return chan_bus_t is
    variable ret : chan_bus_t := (others => '0');
  begin
    for i in 0 to C_CORES-1 loop
      ret((i+1)*chan_llr_t'length-1 downto i*chan_llr_t'length) := resize(v(i), chan_llr_t'length);
    end loop;
    return ret;
  end function;

  function pack_ext_row(v : ext_row_t) return ext_bus_t is
    variable ret : ext_bus_t := (others => '0');
  begin
    for i in 0 to C_CORES-1 loop
      ret((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) := resize(v(i), ext_llr_t'length);
    end loop;
    return ret;
  end function;

  function pack_post_row(v : post_row_t) return post_bus_t is
    variable ret : post_bus_t := (others => '0');
  begin
    for i in 0 to C_CORES-1 loop
      ret((i+1)*post_llr_t'length-1 downto i*post_llr_t'length) := resize(v(i), post_llr_t'length);
    end loop;
    return ret;
  end function;

  function unpack_chan_row(v : chan_bus_t) return chan_row_t is
    variable ret : chan_row_t := (others => (others => '0'));
  begin
    for i in 0 to C_CORES-1 loop
      ret(i) := v((i+1)*chan_llr_t'length-1 downto i*chan_llr_t'length);
    end loop;
    return ret;
  end function;

  function unpack_ext_row(v : ext_bus_t) return ext_row_t is
    variable ret : ext_row_t := (others => (others => '0'));
  begin
    for i in 0 to C_CORES-1 loop
      ret(i) := v((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length);
    end loop;
    return ret;
  end function;

  function unpack_post_row(v : post_bus_t) return post_row_t is
    variable ret : post_row_t := (others => (others => '0'));
  begin
    for i in 0 to C_CORES-1 loop
      ret(i) := v((i+1)*post_llr_t'length-1 downto i*post_llr_t'length);
    end loop;
    return ret;
  end function;

  function bool_to_sl(v : boolean) return std_logic is
  begin
    if v then
      return '1';
    else
      return '0';
    end if;
  end function;

  signal sys_even_mem, sys_odd_mem : chan_mem_t := (others => (others => (others => '0')));
  signal par1_even_mem, par1_odd_mem : chan_mem_t := (others => (others => (others => '0')));
  signal par2_even_mem, par2_odd_mem : chan_mem_t := (others => (others => (others => '0')));
  signal ext_even_mem, ext_odd_mem : ext_mem_t := (others => (others => (others => '0')));
  signal final_even_mem, final_odd_mem : post_mem_t := (others => (others => (others => '0')));
  signal perm_even_mem, perm_odd_mem : perm_mem_t := (others => (others => '0'));
  signal row_base_even_mem, row_base_odd_mem : rowbase_mem_t := (others => (others => '0'));

  signal run1, run2, ctrl_done, last_half : std_logic := '0';
  signal phase1_done, phase2_done : std_logic := '0';

  signal core_start : std_logic_vector(0 to C_CORES-1) := (others => '0');
  signal core_in_valid : std_logic_vector(0 to C_CORES-1) := (others => '0');
  signal core_out_valid : std_logic_vector(0 to C_CORES-1) := (others => '0');
  signal core_done : std_logic_vector(0 to C_CORES-1) := (others => '0');
  signal core_seg_len : addr_arr_t := (others => (others => '0'));
  signal core_in_pair_idx : addr_arr_t := (others => (others => '0'));
  signal core_out_pair_idx : addr_arr_t := (others => (others => '0'));
  signal core_sys_even, core_sys_odd, core_par_even, core_par_odd : chan_row_t := (others => (others => '0'));
  signal core_apri_even, core_apri_odd : ext_row_t := (others => (others => '0'));
  signal core_ext_even, core_ext_odd : ext_row_t := (others => (others => '0'));
  signal core_post_even, core_post_odd : post_row_t := (others => (others => '0'));

  signal frame_bits : integer range 0 to G_K_MAX := 0;
  signal seg_bits : integer range 0 to C_SEG_MAX := 0;
  signal pair_count : integer range 0 to C_PAIR_MAX := 0;
  signal feed_active : std_logic := '0';
  signal feed_pair_idx : integer range 0 to C_PAIR_MAX := 0;
  signal serializer_active : std_logic := '0';
  signal serializer_idx : integer range 0 to G_K_MAX := 0;
  signal run1_d, run2_d : std_logic := '0';
  signal done_q, out_valid_q : std_logic := '0';
  signal out_idx_q : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal l_post_q : post_llr_t := (others => '0');

  signal qpp_even_row_idx, qpp_odd_row_idx : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal qpp_even_addr_vec, qpp_odd_addr_vec : unsigned(C_CORES*G_ADDR_W-1 downto 0) := (others => '0');
  signal qpp_even_addr_sorted, qpp_odd_addr_sorted : unsigned(C_CORES*G_ADDR_W-1 downto 0) := (others => '0');
  signal qpp_even_perm, qpp_odd_perm : unsigned(C_CORES*C_ROUTER_SEL_W-1 downto 0) := (others => '0');
  signal qpp_even_row_base, qpp_odd_row_base : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal qpp_even_row_ok, qpp_odd_row_ok : std_logic := '0';

  signal phase2_even_sys_sorted_row, phase2_odd_sys_sorted_row : chan_row_t := (others => (others => '0'));
  signal phase2_even_apri_sorted_row, phase2_odd_apri_sorted_row : ext_row_t := (others => (others => '0'));
  signal phase2_even_sys_sorted_bus, phase2_odd_sys_sorted_bus : chan_bus_t := (others => '0');
  signal phase2_even_apri_sorted_bus, phase2_odd_apri_sorted_bus : ext_bus_t := (others => '0');
  signal phase2_even_sys_lane_bus, phase2_odd_sys_lane_bus : chan_bus_t := (others => '0');
  signal phase2_even_apri_lane_bus, phase2_odd_apri_lane_bus : ext_bus_t := (others => '0');
  signal phase2_sys_even_lane, phase2_sys_odd_lane : chan_row_t := (others => (others => '0'));
  signal phase2_apri_even_lane, phase2_apri_odd_lane : ext_row_t := (others => (others => '0'));

  signal wb_pair_idx_i : integer range 0 to C_PAIR_MAX-1 := 0;
  signal wb_even_perm, wb_odd_perm : unsigned(C_CORES*C_ROUTER_SEL_W-1 downto 0) := (others => '0');
  signal wb_even_row_base, wb_odd_row_base : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal wb_ext_even_dest_bus, wb_ext_odd_dest_bus : ext_bus_t := (others => '0');
  signal wb_post_even_dest_bus, wb_post_odd_dest_bus : post_bus_t := (others => '0');
  signal wb_ext_even_sorted_bus, wb_ext_odd_sorted_bus : ext_bus_t := (others => '0');
  signal wb_post_even_sorted_bus, wb_post_odd_sorted_bus : post_bus_t := (others => '0');
  signal wb_ext_even_sorted_row, wb_ext_odd_sorted_row : ext_row_t := (others => (others => '0'));
  signal wb_post_even_sorted_row, wb_post_odd_sorted_row : post_row_t := (others => (others => '0'));
begin
  ctrl : entity work.turbo_iteration_ctrl
    port map (
      clk => clk,
      rst => rst,
      start => start,
      n_half_iter => n_half_iter,
      siso_done_1 => phase1_done,
      siso_done_2 => phase2_done,
      run_siso_1 => run1,
      run_siso_2 => run2,
      deint_phase => open,
      last_half => last_half,
      done => ctrl_done
    );

  gen_siso : for i in 0 to C_CORES-1 generate
    siso_i : entity work.siso_maxlogmap
      generic map (
        G_SEG_MAX => C_SEG_MAX,
        G_ADDR_W => G_ADDR_W
      )
      port map (
        clk => clk,
        rst => rst,
        start => core_start(i),
        seg_first => bool_to_sl(i = 0),
        seg_last => bool_to_sl(i = C_CORES-1),
        seg_len => core_seg_len(i),
        in_valid => core_in_valid(i),
        in_pair_idx => core_in_pair_idx(i),
        sys_even => core_sys_even(i),
        sys_odd => core_sys_odd(i),
        par_even => core_par_even(i),
        par_odd => core_par_odd(i),
        apri_even => core_apri_even(i),
        apri_odd => core_apri_odd(i),
        out_valid => core_out_valid(i),
        out_pair_idx => core_out_pair_idx(i),
        ext_even => core_ext_even(i),
        ext_odd => core_ext_odd(i),
        post_even => core_post_even(i),
        post_odd => core_post_odd(i),
        done => core_done(i)
      );
  end generate;

  qpp_even_row_idx <= to_unsigned(feed_pair_idx * 2, G_ADDR_W);
  qpp_odd_row_idx <= to_unsigned(feed_pair_idx * 2 + 1, G_ADDR_W);

  qpp_even_sched : entity work.qpp_parallel_scheduler
    generic map (
      G_P => C_CORES,
      G_ADDR_W => G_ADDR_W
    )
    port map (
      row_idx => qpp_even_row_idx,
      seg_len => to_unsigned(seg_bits, G_ADDR_W),
      k_len => k_len,
      f1 => f1,
      f2 => f2,
      addr_vec => qpp_even_addr_vec,
      row_base => qpp_even_row_base,
      row_ok => qpp_even_row_ok
    );

  qpp_odd_sched : entity work.qpp_parallel_scheduler
    generic map (
      G_P => C_CORES,
      G_ADDR_W => G_ADDR_W
    )
    port map (
      row_idx => qpp_odd_row_idx,
      seg_len => to_unsigned(seg_bits, G_ADDR_W),
      k_len => k_len,
      f1 => f1,
      f2 => f2,
      addr_vec => qpp_odd_addr_vec,
      row_base => qpp_odd_row_base,
      row_ok => qpp_odd_row_ok
    );

  batch_even_master : entity work.batcher_master
    generic map (
      G_P => C_CORES,
      G_ADDR_W => G_ADDR_W,
      G_SEL_W => C_ROUTER_SEL_W
    )
    port map (
      addr_in => qpp_even_addr_vec,
      addr_sorted => qpp_even_addr_sorted,
      perm_out => qpp_even_perm
    );

  batch_odd_master : entity work.batcher_master
    generic map (
      G_P => C_CORES,
      G_ADDR_W => G_ADDR_W,
      G_SEL_W => C_ROUTER_SEL_W
    )
    port map (
      addr_in => qpp_odd_addr_vec,
      addr_sorted => qpp_odd_addr_sorted,
      perm_out => qpp_odd_perm
    );

  phase2_even_sys_sorted_bus <= pack_chan_row(phase2_even_sys_sorted_row);
  phase2_odd_sys_sorted_bus <= pack_chan_row(phase2_odd_sys_sorted_row);
  phase2_even_apri_sorted_bus <= pack_ext_row(phase2_even_apri_sorted_row);
  phase2_odd_apri_sorted_bus <= pack_ext_row(phase2_odd_apri_sorted_row);

  batch_even_sys_slave : entity work.batcher_slave
    generic map (
      G_P => C_CORES,
      G_DATA_W => chan_llr_t'length,
      G_SEL_W => C_ROUTER_SEL_W,
      G_REVERSE => false
    )
    port map (
      perm_in => qpp_even_perm,
      data_in => phase2_even_sys_sorted_bus,
      data_out => phase2_even_sys_lane_bus
    );

  batch_odd_sys_slave : entity work.batcher_slave
    generic map (
      G_P => C_CORES,
      G_DATA_W => chan_llr_t'length,
      G_SEL_W => C_ROUTER_SEL_W,
      G_REVERSE => false
    )
    port map (
      perm_in => qpp_odd_perm,
      data_in => phase2_odd_sys_sorted_bus,
      data_out => phase2_odd_sys_lane_bus
    );

  batch_even_apri_slave : entity work.batcher_slave
    generic map (
      G_P => C_CORES,
      G_DATA_W => ext_llr_t'length,
      G_SEL_W => C_ROUTER_SEL_W,
      G_REVERSE => false
    )
    port map (
      perm_in => qpp_even_perm,
      data_in => phase2_even_apri_sorted_bus,
      data_out => phase2_even_apri_lane_bus
    );

  batch_odd_apri_slave : entity work.batcher_slave
    generic map (
      G_P => C_CORES,
      G_DATA_W => ext_llr_t'length,
      G_SEL_W => C_ROUTER_SEL_W,
      G_REVERSE => false
    )
    port map (
      perm_in => qpp_odd_perm,
      data_in => phase2_odd_apri_sorted_bus,
      data_out => phase2_odd_apri_lane_bus
    );

  phase2_sys_even_lane <= unpack_chan_row(phase2_even_sys_lane_bus);
  phase2_sys_odd_lane <= unpack_chan_row(phase2_odd_sys_lane_bus);
  phase2_apri_even_lane <= unpack_ext_row(phase2_even_apri_lane_bus);
  phase2_apri_odd_lane <= unpack_ext_row(phase2_odd_apri_lane_bus);

  wb_pair_idx_i <= to_integer(to_01(core_out_pair_idx(0), '0')) when to_integer(to_01(core_out_pair_idx(0), '0')) < C_PAIR_MAX else 0;
  wb_even_perm <= perm_even_mem(wb_pair_idx_i);
  wb_odd_perm <= perm_odd_mem(wb_pair_idx_i);
  wb_even_row_base <= row_base_even_mem(wb_pair_idx_i);
  wb_odd_row_base <= row_base_odd_mem(wb_pair_idx_i);
  wb_ext_even_dest_bus <= pack_ext_row(core_ext_even);
  wb_ext_odd_dest_bus <= pack_ext_row(core_ext_odd);
  wb_post_even_dest_bus <= pack_post_row(core_post_even);
  wb_post_odd_dest_bus <= pack_post_row(core_post_odd);

  batch_even_ext_unslave : entity work.batcher_slave
    generic map (
      G_P => C_CORES,
      G_DATA_W => ext_llr_t'length,
      G_SEL_W => C_ROUTER_SEL_W,
      G_REVERSE => true
    )
    port map (
      perm_in => wb_even_perm,
      data_in => wb_ext_even_dest_bus,
      data_out => wb_ext_even_sorted_bus
    );

  batch_odd_ext_unslave : entity work.batcher_slave
    generic map (
      G_P => C_CORES,
      G_DATA_W => ext_llr_t'length,
      G_SEL_W => C_ROUTER_SEL_W,
      G_REVERSE => true
    )
    port map (
      perm_in => wb_odd_perm,
      data_in => wb_ext_odd_dest_bus,
      data_out => wb_ext_odd_sorted_bus
    );

  batch_even_post_unslave : entity work.batcher_slave
    generic map (
      G_P => C_CORES,
      G_DATA_W => post_llr_t'length,
      G_SEL_W => C_ROUTER_SEL_W,
      G_REVERSE => true
    )
    port map (
      perm_in => wb_even_perm,
      data_in => wb_post_even_dest_bus,
      data_out => wb_post_even_sorted_bus
    );

  batch_odd_post_unslave : entity work.batcher_slave
    generic map (
      G_P => C_CORES,
      G_DATA_W => post_llr_t'length,
      G_SEL_W => C_ROUTER_SEL_W,
      G_REVERSE => true
    )
    port map (
      perm_in => wb_odd_perm,
      data_in => wb_post_odd_dest_bus,
      data_out => wb_post_odd_sorted_bus
    );

  wb_ext_even_sorted_row <= unpack_ext_row(wb_ext_even_sorted_bus);
  wb_ext_odd_sorted_row <= unpack_ext_row(wb_ext_odd_sorted_bus);
  wb_post_even_sorted_row <= unpack_post_row(wb_post_even_sorted_bus);
  wb_post_odd_sorted_row <= unpack_post_row(wb_post_odd_sorted_bus);

  process(all)
    variable src_row_i : integer;
    variable row_base_i : integer;
    variable sys_row_v : chan_row_t;
    variable apri_row_v : ext_row_t;
  begin
    sys_row_v := (others => (others => '0'));
    apri_row_v := (others => (others => '0'));
    phase2_even_sys_sorted_row <= (others => (others => '0'));
    phase2_even_apri_sorted_row <= (others => (others => '0'));
    phase2_odd_sys_sorted_row <= (others => (others => '0'));
    phase2_odd_apri_sorted_row <= (others => (others => '0'));

    if run2 = '1' and feed_active = '1' then
      if (feed_pair_idx * 2) < seg_bits and qpp_even_row_ok = '1' then
        row_base_i := to_integer(qpp_even_row_base);
        src_row_i := row_base_i / 2;
        if src_row_i >= 0 and src_row_i < C_PAIR_MAX then
          if (row_base_i mod 2) = 0 then
            sys_row_v := sys_even_mem(src_row_i);
            apri_row_v := ext_even_mem(src_row_i);
          else
            sys_row_v := sys_odd_mem(src_row_i);
            apri_row_v := ext_odd_mem(src_row_i);
          end if;
          phase2_even_sys_sorted_row <= sys_row_v;
          phase2_even_apri_sorted_row <= apri_row_v;
        end if;
      end if;

      if (feed_pair_idx * 2 + 1) < seg_bits and qpp_odd_row_ok = '1' then
        row_base_i := to_integer(qpp_odd_row_base);
        src_row_i := row_base_i / 2;
        if src_row_i >= 0 and src_row_i < C_PAIR_MAX then
          if (row_base_i mod 2) = 0 then
            sys_row_v := sys_even_mem(src_row_i);
            apri_row_v := ext_even_mem(src_row_i);
          else
            sys_row_v := sys_odd_mem(src_row_i);
            apri_row_v := ext_odd_mem(src_row_i);
          end if;
          phase2_odd_sys_sorted_row <= sys_row_v;
          phase2_odd_apri_sorted_row <= apri_row_v;
        end if;
      end if;
    end if;
  end process;

  process(clk)
    variable k_i, seg_i, row_i, pair_row_i, row_base_i : integer;
    variable all_done : std_logic;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        frame_bits <= 0;
        seg_bits <= 0;
        pair_count <= 0;
        feed_active <= '0';
        feed_pair_idx <= 0;
        serializer_active <= '0';
        serializer_idx <= 0;
        phase1_done <= '0';
        phase2_done <= '0';
        core_start <= (others => '0');
        core_in_valid <= (others => '0');
        run1_d <= '0';
        run2_d <= '0';
        done_q <= '0';
        out_valid_q <= '0';
        out_idx_q <= (others => '0');
        l_post_q <= (others => '0');
      else
        core_start <= (others => '0');
        core_in_valid <= (others => '0');
        phase1_done <= '0';
        phase2_done <= '0';
        done_q <= '0';
        out_valid_q <= '0';
        out_idx_q <= (others => '0');
        l_post_q <= (others => '0');

        if in_valid = '1' then
          k_i := to_integer(in_idx);
          if to_integer(k_len) > 0 and (to_integer(k_len) mod C_CORES) = 0 then
            seg_i := to_integer(k_len) / C_CORES;
            if seg_i > 0 and k_i >= 0 and k_i < to_integer(k_len) then
              row_i := k_i mod seg_i;
              pair_row_i := row_i / 2;
              seg_i := k_i / (to_integer(k_len) / C_CORES);
              if pair_row_i >= 0 and pair_row_i < C_PAIR_MAX and seg_i >= 0 and seg_i < C_CORES then
                if (row_i mod 2) = 0 then
                  sys_even_mem(pair_row_i)(seg_i) <= l_sys_in;
                  par1_even_mem(pair_row_i)(seg_i) <= l_par1_in;
                  par2_even_mem(pair_row_i)(seg_i) <= l_par2_in;
                else
                  sys_odd_mem(pair_row_i)(seg_i) <= l_sys_in;
                  par1_odd_mem(pair_row_i)(seg_i) <= l_par1_in;
                  par2_odd_mem(pair_row_i)(seg_i) <= l_par2_in;
                end if;
              end if;
            end if;
          end if;
        end if;

        if start = '1' then
          k_i := to_integer(k_len);
          assert k_i > 0 report "K must be non-zero" severity error;
          assert (k_i mod C_CORES) = 0 report "This paper-aligned top-level currently requires K divisible by 8" severity error;
          frame_bits <= k_i;
          seg_bits <= k_i / C_CORES;
          pair_count <= ((k_i / C_CORES) + 1) / 2;
          feed_active <= '0';
          feed_pair_idx <= 0;
          serializer_active <= '0';
          serializer_idx <= 0;
          for pr in 0 to C_PAIR_MAX-1 loop
            ext_even_mem(pr) <= (others => (others => '0'));
            ext_odd_mem(pr) <= (others => (others => '0'));
            final_even_mem(pr) <= (others => (others => '0'));
            final_odd_mem(pr) <= (others => (others => '0'));
            perm_even_mem(pr) <= (others => '0');
            perm_odd_mem(pr) <= (others => '0');
            row_base_even_mem(pr) <= (others => '0');
            row_base_odd_mem(pr) <= (others => '0');
          end loop;
        end if;

        if (run1 = '1' and run1_d = '0') or (run2 = '1' and run2_d = '0') then
          feed_active <= '1';
          feed_pair_idx <= 0;
          for i in 0 to C_CORES-1 loop
            core_start(i) <= '1';
            core_seg_len(i) <= to_unsigned(seg_bits, G_ADDR_W);
          end loop;
        end if;

        if feed_active = '1' then
          pair_row_i := feed_pair_idx;
          if run2 = '1' then
            if (pair_row_i * 2) < seg_bits then
              assert qpp_even_row_ok = '1' report "QPP even-row scheduler violated maximally-vectorizable property" severity error;
              perm_even_mem(pair_row_i) <= qpp_even_perm;
              row_base_even_mem(pair_row_i) <= qpp_even_row_base;
            end if;
            if (pair_row_i * 2 + 1) < seg_bits then
              assert qpp_odd_row_ok = '1' report "QPP odd-row scheduler violated maximally-vectorizable property" severity error;
              perm_odd_mem(pair_row_i) <= qpp_odd_perm;
              row_base_odd_mem(pair_row_i) <= qpp_odd_row_base;
            end if;
          end if;

          for i in 0 to C_CORES-1 loop
            core_in_valid(i) <= '1';
            core_in_pair_idx(i) <= to_unsigned(pair_row_i, G_ADDR_W);
            if run1 = '1' then
              core_sys_even(i) <= sys_even_mem(pair_row_i)(i);
              core_sys_odd(i) <= sys_odd_mem(pair_row_i)(i);
              core_par_even(i) <= par1_even_mem(pair_row_i)(i);
              core_par_odd(i) <= par1_odd_mem(pair_row_i)(i);
              core_apri_even(i) <= ext_even_mem(pair_row_i)(i);
              core_apri_odd(i) <= ext_odd_mem(pair_row_i)(i);
            else
              core_sys_even(i) <= phase2_sys_even_lane(i);
              core_sys_odd(i) <= phase2_sys_odd_lane(i);
              core_par_even(i) <= par2_even_mem(pair_row_i)(i);
              core_par_odd(i) <= par2_odd_mem(pair_row_i)(i);
              core_apri_even(i) <= phase2_apri_even_lane(i);
              core_apri_odd(i) <= phase2_apri_odd_lane(i);
              if (pair_row_i * 2) >= seg_bits then
                core_sys_even(i) <= (others => '0');
                core_apri_even(i) <= (others => '0');
              end if;
              if (pair_row_i * 2 + 1) >= seg_bits then
                core_sys_odd(i) <= (others => '0');
                core_apri_odd(i) <= (others => '0');
              end if;
            end if;

            if (pair_row_i * 2) >= seg_bits then
              core_sys_even(i) <= (others => '0');
              core_par_even(i) <= (others => '0');
              core_apri_even(i) <= (others => '0');
            end if;
            if (pair_row_i * 2 + 1) >= seg_bits then
              core_sys_odd(i) <= (others => '0');
              core_par_odd(i) <= (others => '0');
              core_apri_odd(i) <= (others => '0');
            end if;
          end loop;

          if feed_pair_idx = pair_count - 1 then
            feed_active <= '0';
          else
            feed_pair_idx <= feed_pair_idx + 1;
          end if;
        end if;

        if core_out_valid(0) = '1' then
          pair_row_i := to_integer(core_out_pair_idx(0));
          if run1 = '1' then
            ext_even_mem(pair_row_i) <= core_ext_even;
            ext_odd_mem(pair_row_i) <= core_ext_odd;
            if last_half = '1' then
              final_even_mem(pair_row_i) <= core_post_even;
              final_odd_mem(pair_row_i) <= core_post_odd;
            end if;
          else
            if (pair_row_i * 2) < seg_bits then
              row_base_i := to_integer(wb_even_row_base);
              if (row_base_i / 2) < C_PAIR_MAX then
                if (row_base_i mod 2) = 0 then
                  ext_even_mem(row_base_i / 2) <= wb_ext_even_sorted_row;
                  if last_half = '1' then
                    final_even_mem(row_base_i / 2) <= wb_post_even_sorted_row;
                  end if;
                else
                  ext_odd_mem(row_base_i / 2) <= wb_ext_even_sorted_row;
                  if last_half = '1' then
                    final_odd_mem(row_base_i / 2) <= wb_post_even_sorted_row;
                  end if;
                end if;
              end if;
            end if;

            if (pair_row_i * 2 + 1) < seg_bits then
              row_base_i := to_integer(wb_odd_row_base);
              if (row_base_i / 2) < C_PAIR_MAX then
                if (row_base_i mod 2) = 0 then
                  ext_even_mem(row_base_i / 2) <= wb_ext_odd_sorted_row;
                  if last_half = '1' then
                    final_even_mem(row_base_i / 2) <= wb_post_odd_sorted_row;
                  end if;
                else
                  ext_odd_mem(row_base_i / 2) <= wb_ext_odd_sorted_row;
                  if last_half = '1' then
                    final_odd_mem(row_base_i / 2) <= wb_post_odd_sorted_row;
                  end if;
                end if;
              end if;
            end if;
          end if;
        end if;

        all_done := '1';
        for i in 0 to C_CORES-1 loop
          if core_done(i) = '0' then
            all_done := '0';
          end if;
        end loop;

        if run1 = '1' and all_done = '1' then
          phase1_done <= '1';
          if last_half = '1' then
            serializer_active <= '1';
            serializer_idx <= 0;
          end if;
        end if;

        if run2 = '1' and all_done = '1' then
          phase2_done <= '1';
          if last_half = '1' then
            serializer_active <= '1';
            serializer_idx <= 0;
          end if;
        end if;

        if serializer_active = '1' then
          seg_i := serializer_idx / seg_bits;
          row_i := serializer_idx mod seg_bits;
          pair_row_i := row_i / 2;
          out_valid_q <= '1';
          out_idx_q <= to_unsigned(serializer_idx, G_ADDR_W);
          if (row_i mod 2) = 0 then
            l_post_q <= final_even_mem(pair_row_i)(seg_i);
          else
            l_post_q <= final_odd_mem(pair_row_i)(seg_i);
          end if;

          if serializer_idx = frame_bits - 1 then
            serializer_active <= '0';
            done_q <= '1';
          else
            serializer_idx <= serializer_idx + 1;
          end if;
        elsif ctrl_done = '1' and frame_bits = 0 then
          done_q <= '1';
        end if;

        run1_d <= run1;
        run2_d <= run2;
      end if;
    end if;
  end process;

  out_valid <= out_valid_q;
  out_idx <= out_idx_q;
  l_post <= l_post_q;
  done <= done_q;
end architecture;
