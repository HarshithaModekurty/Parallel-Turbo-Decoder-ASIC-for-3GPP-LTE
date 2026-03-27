library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity turbo_decoder_top_parallel8_backup is
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

architecture rtl of turbo_decoder_top_parallel8_backup is
  constant C_CORES      : natural := C_PARALLEL;
  constant C_SEG_MAX    : natural := (G_K_MAX + C_CORES - 1) / C_CORES;
  constant C_PAIR_MAX   : natural := (C_SEG_MAX + 1) / 2;
  constant C_BRAM_BANKS : natural := 16;

  type chan_row_t is array (0 to C_CORES-1) of chan_llr_t;
  type ext_row_t  is array (0 to C_CORES-1) of ext_llr_t;
  type post_row_t is array (0 to C_CORES-1) of post_llr_t;
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

  function single_chan_lane(lane_i : natural; value_i : chan_llr_t) return chan_bus_t is
    variable ret : chan_bus_t := (others => '0');
  begin
    ret((lane_i+1)*chan_llr_t'length-1 downto lane_i*chan_llr_t'length) := resize(value_i, chan_llr_t'length);
    return ret;
  end function;

  constant C_ALL_LANES_WE : std_logic_vector(0 to C_CORES-1) := (others => '1');
  constant C_NO_LANES_WE  : std_logic_vector(0 to C_CORES-1) := (others => '0');

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
  signal issue_active : std_logic := '0';
  signal issue_pair_idx : integer range 0 to C_PAIR_MAX := 0;
  signal feed_pipe_valid : std_logic := '0';
  signal feed_pipe_pair_idx : integer range 0 to C_PAIR_MAX := 0;
  signal feed_even_valid_q, feed_odd_valid_q : std_logic := '0';
  signal feed_even_is_odd_q, feed_odd_is_odd_q : std_logic := '0';
  signal feed_perm_even_q, feed_perm_odd_q : unsigned(C_CORES*C_ROUTER_SEL_W-1 downto 0) := (others => '0');
  signal first_run1_pending : std_logic := '0';

  signal ser_issue_active : std_logic := '0';
  signal ser_issue_idx : integer range 0 to G_K_MAX := 0;
  signal ser_pipe_valid : std_logic := '0';
  signal ser_pipe_idx : integer range 0 to G_K_MAX := 0;
  signal ser_pipe_lane : integer range 0 to C_CORES-1 := 0;
  signal ser_pipe_is_odd : std_logic := '0';

  signal run1_d, run2_d : std_logic := '0';
  signal done_q, out_valid_q : std_logic := '0';
  signal out_idx_q : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal l_post_q : post_llr_t := (others => '0');

  signal qpp_even_row_idx, qpp_odd_row_idx : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal qpp_even_addr_vec, qpp_odd_addr_vec : unsigned(C_CORES*G_ADDR_W-1 downto 0) := (others => '0');
  signal qpp_even_addr_sorted, qpp_odd_addr_sorted : unsigned(C_CORES*G_ADDR_W-1 downto 0) := (others => '0');
  signal qpp_even_perm, qpp_odd_perm : unsigned(C_CORES*C_ROUTER_SEL_W-1 downto 0) := (others => '0');
  signal qpp_even_ctrl, qpp_odd_ctrl : std_logic_vector(C_BATCHER_CTRL_W-1 downto 0) := (others => '0');
  signal qpp_even_row_base, qpp_odd_row_base : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal qpp_even_row_ok, qpp_odd_row_ok : std_logic := '0';
  signal qpp_even_pair_addr, qpp_odd_pair_addr : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal issue_pair_addr_u : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal phase_rd0_addr_u : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal ser_pair_addr_u : unsigned(G_ADDR_W-1 downto 0) := (others => '0');

  signal load_even_en, load_odd_en : std_logic := '0';
  signal load_pair_addr : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal load_lane_we : std_logic_vector(0 to C_CORES-1) := (others => '0');
  signal load_sys_bus, load_par1_bus, load_par2_bus : chan_bus_t := (others => '0');

  signal sys_even_rd0_bus, sys_even_rd1_bus, sys_odd_rd0_bus, sys_odd_rd1_bus : chan_bus_t := (others => '0');
  signal par1_even_rd_bus, par1_odd_rd_bus, par2_even_rd_bus, par2_odd_rd_bus : chan_bus_t := (others => '0');
  signal ext_even_rd0_bus, ext_even_rd1_bus, ext_odd_rd0_bus, ext_odd_rd1_bus : ext_bus_t := (others => '0');
  signal final_even_rd_bus, final_odd_rd_bus : post_bus_t := (others => '0');

  signal sys_even_rd0_row, sys_even_rd1_row, sys_odd_rd0_row, sys_odd_rd1_row : chan_row_t := (others => (others => '0'));
  signal par1_even_rd_row, par1_odd_rd_row, par2_even_rd_row, par2_odd_rd_row : chan_row_t := (others => (others => '0'));
  signal ext_even_rd0_row, ext_even_rd1_row, ext_odd_rd0_row, ext_odd_rd1_row : ext_row_t := (others => (others => '0'));
  signal final_even_rd_row, final_odd_rd_row : post_row_t := (others => (others => '0'));

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

  signal ext_even_wr0_en, ext_even_wr1_en, ext_odd_wr0_en, ext_odd_wr1_en : std_logic := '0';
  signal final_even_wr0_en, final_even_wr1_en, final_odd_wr0_en, final_odd_wr1_en : std_logic := '0';
  signal ext_even_wr0_addr, ext_even_wr1_addr, ext_odd_wr0_addr, ext_odd_wr1_addr : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal final_even_wr0_addr, final_even_wr1_addr, final_odd_wr0_addr, final_odd_wr1_addr : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal ext_even_wr0_bus, ext_even_wr1_bus, ext_odd_wr0_bus, ext_odd_wr1_bus : ext_bus_t := (others => '0');
  signal final_even_wr0_bus, final_even_wr1_bus, final_odd_wr0_bus, final_odd_wr1_bus : post_bus_t := (others => '0');
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
        fetch_req_valid => open,
        fetch_req_pair_idx => open,
        fetch_rsp_valid => '0',
        out_valid => core_out_valid(i),
        out_pair_idx => core_out_pair_idx(i),
        ext_even => core_ext_even(i),
        ext_odd => core_ext_odd(i),
        post_even => core_post_even(i),
        post_odd => core_post_odd(i),
        done => core_done(i)
      );
  end generate;

  qpp_even_row_idx <= to_unsigned(issue_pair_idx * 2, G_ADDR_W);
  qpp_odd_row_idx <= to_unsigned(issue_pair_idx * 2 + 1, G_ADDR_W);
  issue_pair_addr_u <= to_unsigned(issue_pair_idx, G_ADDR_W);
  phase_rd0_addr_u <= issue_pair_addr_u when run1 = '1' else qpp_even_pair_addr;
  qpp_even_pair_addr <= shift_right(qpp_even_row_base, 1);
  qpp_odd_pair_addr <= shift_right(qpp_odd_row_base, 1);

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
      perm_out => qpp_even_perm,
      ctrl_out => qpp_even_ctrl
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
      perm_out => qpp_odd_perm,
      ctrl_out => qpp_odd_ctrl
    );

  sys_even_rd0_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => chan_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active,
      rd_addr => phase_rd0_addr_u,
      rd_data => sys_even_rd0_bus,
      wr0_en => load_even_en,
      wr0_addr => load_pair_addr,
      wr0_lane_we => load_lane_we,
      wr0_data => load_sys_bus,
      wr1_en => '0',
      wr1_addr => (others => '0'),
      wr1_lane_we => C_NO_LANES_WE,
      wr1_data => (others => '0')
    );

  sys_even_rd1_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => chan_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active and run2,
      rd_addr => qpp_odd_pair_addr,
      rd_data => sys_even_rd1_bus,
      wr0_en => load_even_en,
      wr0_addr => load_pair_addr,
      wr0_lane_we => load_lane_we,
      wr0_data => load_sys_bus,
      wr1_en => '0',
      wr1_addr => (others => '0'),
      wr1_lane_we => C_NO_LANES_WE,
      wr1_data => (others => '0')
    );

  sys_odd_rd0_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => chan_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active,
      rd_addr => phase_rd0_addr_u,
      rd_data => sys_odd_rd0_bus,
      wr0_en => load_odd_en,
      wr0_addr => load_pair_addr,
      wr0_lane_we => load_lane_we,
      wr0_data => load_sys_bus,
      wr1_en => '0',
      wr1_addr => (others => '0'),
      wr1_lane_we => C_NO_LANES_WE,
      wr1_data => (others => '0')
    );

  sys_odd_rd1_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => chan_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active and run2,
      rd_addr => qpp_odd_pair_addr,
      rd_data => sys_odd_rd1_bus,
      wr0_en => load_odd_en,
      wr0_addr => load_pair_addr,
      wr0_lane_we => load_lane_we,
      wr0_data => load_sys_bus,
      wr1_en => '0',
      wr1_addr => (others => '0'),
      wr1_lane_we => C_NO_LANES_WE,
      wr1_data => (others => '0')
    );

  par1_even_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => chan_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active and run1,
      rd_addr => issue_pair_addr_u,
      rd_data => par1_even_rd_bus,
      wr0_en => load_even_en,
      wr0_addr => load_pair_addr,
      wr0_lane_we => load_lane_we,
      wr0_data => load_par1_bus,
      wr1_en => '0',
      wr1_addr => (others => '0'),
      wr1_lane_we => C_NO_LANES_WE,
      wr1_data => (others => '0')
    );

  par1_odd_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => chan_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active and run1,
      rd_addr => issue_pair_addr_u,
      rd_data => par1_odd_rd_bus,
      wr0_en => load_odd_en,
      wr0_addr => load_pair_addr,
      wr0_lane_we => load_lane_we,
      wr0_data => load_par1_bus,
      wr1_en => '0',
      wr1_addr => (others => '0'),
      wr1_lane_we => C_NO_LANES_WE,
      wr1_data => (others => '0')
    );

  par2_even_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => chan_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active and run2,
      rd_addr => issue_pair_addr_u,
      rd_data => par2_even_rd_bus,
      wr0_en => load_even_en,
      wr0_addr => load_pair_addr,
      wr0_lane_we => load_lane_we,
      wr0_data => load_par2_bus,
      wr1_en => '0',
      wr1_addr => (others => '0'),
      wr1_lane_we => C_NO_LANES_WE,
      wr1_data => (others => '0')
    );

  par2_odd_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => chan_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active and run2,
      rd_addr => issue_pair_addr_u,
      rd_data => par2_odd_rd_bus,
      wr0_en => load_odd_en,
      wr0_addr => load_pair_addr,
      wr0_lane_we => load_lane_we,
      wr0_data => load_par2_bus,
      wr1_en => '0',
      wr1_addr => (others => '0'),
      wr1_lane_we => C_NO_LANES_WE,
      wr1_data => (others => '0')
    );

  ext_even_rd0_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => ext_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active,
      rd_addr => phase_rd0_addr_u,
      rd_data => ext_even_rd0_bus,
      wr0_en => ext_even_wr0_en,
      wr0_addr => ext_even_wr0_addr,
      wr0_lane_we => C_ALL_LANES_WE,
      wr0_data => ext_even_wr0_bus,
      wr1_en => ext_even_wr1_en,
      wr1_addr => ext_even_wr1_addr,
      wr1_lane_we => C_ALL_LANES_WE,
      wr1_data => ext_even_wr1_bus
    );

  ext_even_rd1_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => ext_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active and run2,
      rd_addr => qpp_odd_pair_addr,
      rd_data => ext_even_rd1_bus,
      wr0_en => ext_even_wr0_en,
      wr0_addr => ext_even_wr0_addr,
      wr0_lane_we => C_ALL_LANES_WE,
      wr0_data => ext_even_wr0_bus,
      wr1_en => ext_even_wr1_en,
      wr1_addr => ext_even_wr1_addr,
      wr1_lane_we => C_ALL_LANES_WE,
      wr1_data => ext_even_wr1_bus
    );

  ext_odd_rd0_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => ext_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active,
      rd_addr => phase_rd0_addr_u,
      rd_data => ext_odd_rd0_bus,
      wr0_en => ext_odd_wr0_en,
      wr0_addr => ext_odd_wr0_addr,
      wr0_lane_we => C_ALL_LANES_WE,
      wr0_data => ext_odd_wr0_bus,
      wr1_en => ext_odd_wr1_en,
      wr1_addr => ext_odd_wr1_addr,
      wr1_lane_we => C_ALL_LANES_WE,
      wr1_data => ext_odd_wr1_bus
    );

  ext_odd_rd1_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => ext_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => issue_active and run2,
      rd_addr => qpp_odd_pair_addr,
      rd_data => ext_odd_rd1_bus,
      wr0_en => ext_odd_wr0_en,
      wr0_addr => ext_odd_wr0_addr,
      wr0_lane_we => C_ALL_LANES_WE,
      wr0_data => ext_odd_wr0_bus,
      wr1_en => ext_odd_wr1_en,
      wr1_addr => ext_odd_wr1_addr,
      wr1_lane_we => C_ALL_LANES_WE,
      wr1_data => ext_odd_wr1_bus
    );

  final_even_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => post_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => ser_issue_active,
      rd_addr => ser_pair_addr_u,
      rd_data => final_even_rd_bus,
      wr0_en => final_even_wr0_en,
      wr0_addr => final_even_wr0_addr,
      wr0_lane_we => C_ALL_LANES_WE,
      wr0_data => final_even_wr0_bus,
      wr1_en => final_even_wr1_en,
      wr1_addr => final_even_wr1_addr,
      wr1_lane_we => C_ALL_LANES_WE,
      wr1_data => final_even_wr1_bus
    );

  final_odd_ram : entity work.multiport_row_bram
    generic map (
      G_ROWS => C_PAIR_MAX,
      G_ADDR_W => G_ADDR_W,
      G_BANKS => C_BRAM_BANKS,
      G_LANES => C_CORES,
      G_WORD_W => post_llr_t'length
    )
    port map (
      clk => clk,
      rd_en => ser_issue_active,
      rd_addr => ser_pair_addr_u,
      rd_data => final_odd_rd_bus,
      wr0_en => final_odd_wr0_en,
      wr0_addr => final_odd_wr0_addr,
      wr0_lane_we => C_ALL_LANES_WE,
      wr0_data => final_odd_wr0_bus,
      wr1_en => final_odd_wr1_en,
      wr1_addr => final_odd_wr1_addr,
      wr1_lane_we => C_ALL_LANES_WE,
      wr1_data => final_odd_wr1_bus
    );

  sys_even_rd0_row <= unpack_chan_row(sys_even_rd0_bus);
  sys_even_rd1_row <= unpack_chan_row(sys_even_rd1_bus);
  sys_odd_rd0_row <= unpack_chan_row(sys_odd_rd0_bus);
  sys_odd_rd1_row <= unpack_chan_row(sys_odd_rd1_bus);
  par1_even_rd_row <= unpack_chan_row(par1_even_rd_bus);
  par1_odd_rd_row <= unpack_chan_row(par1_odd_rd_bus);
  par2_even_rd_row <= unpack_chan_row(par2_even_rd_bus);
  par2_odd_rd_row <= unpack_chan_row(par2_odd_rd_bus);
  ext_even_rd0_row <= unpack_ext_row(ext_even_rd0_bus);
  ext_even_rd1_row <= unpack_ext_row(ext_even_rd1_bus);
  ext_odd_rd0_row <= unpack_ext_row(ext_odd_rd0_bus);
  ext_odd_rd1_row <= unpack_ext_row(ext_odd_rd1_bus);
  final_even_rd_row <= unpack_post_row(final_even_rd_bus);
  final_odd_rd_row <= unpack_post_row(final_odd_rd_bus);

  phase2_even_sys_sorted_row <= sys_odd_rd0_row when feed_even_is_odd_q = '1' and feed_even_valid_q = '1' else
                                sys_even_rd0_row when feed_even_valid_q = '1' else
                                (others => (others => '0'));
  phase2_even_apri_sorted_row <= ext_odd_rd0_row when feed_even_is_odd_q = '1' and feed_even_valid_q = '1' else
                                 ext_even_rd0_row when feed_even_valid_q = '1' else
                                 (others => (others => '0'));
  phase2_odd_sys_sorted_row <= sys_odd_rd1_row when feed_odd_is_odd_q = '1' and feed_odd_valid_q = '1' else
                               sys_even_rd1_row when feed_odd_valid_q = '1' else
                               (others => (others => '0'));
  phase2_odd_apri_sorted_row <= ext_odd_rd1_row when feed_odd_is_odd_q = '1' and feed_odd_valid_q = '1' else
                                ext_even_rd1_row when feed_odd_valid_q = '1' else
                                (others => (others => '0'));

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
      perm_in => feed_perm_even_q,
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
      perm_in => feed_perm_odd_q,
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
      perm_in => feed_perm_even_q,
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
      perm_in => feed_perm_odd_q,
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
    variable k_i, seg_i, lane_i, row_i, pair_i : integer;
    variable lane_we_v : std_logic_vector(0 to C_CORES-1);
  begin
    load_even_en <= '0';
    load_odd_en <= '0';
    load_pair_addr <= (others => '0');
    load_lane_we <= (others => '0');
    load_sys_bus <= (others => '0');
    load_par1_bus <= (others => '0');
    load_par2_bus <= (others => '0');

    k_i := to_integer(to_01(k_len, '0'));
    if in_valid = '1' and k_i > 0 and (k_i mod C_CORES) = 0 then
      seg_i := k_i / C_CORES;
      if seg_i > 0 then
        k_i := to_integer(to_01(in_idx, '0'));
        if k_i >= 0 and k_i < to_integer(to_01(k_len, '0')) then
          lane_i := k_i / seg_i;
          row_i := k_i mod seg_i;
          pair_i := row_i / 2;
          if lane_i >= 0 and lane_i < C_CORES and pair_i >= 0 and pair_i < C_PAIR_MAX then
            lane_we_v := (others => '0');
            lane_we_v(lane_i) := '1';
            load_pair_addr <= to_unsigned(pair_i, G_ADDR_W);
            load_lane_we <= lane_we_v;
            load_sys_bus <= single_chan_lane(lane_i, l_sys_in);
            load_par1_bus <= single_chan_lane(lane_i, l_par1_in);
            load_par2_bus <= single_chan_lane(lane_i, l_par2_in);
            if (row_i mod 2) = 0 then
              load_even_en <= '1';
            else
              load_odd_en <= '1';
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  process(all)
    variable pair_row_i : integer;
    variable row_base_i : integer;
  begin
    ext_even_wr0_en <= '0';
    ext_even_wr1_en <= '0';
    ext_odd_wr0_en <= '0';
    ext_odd_wr1_en <= '0';
    final_even_wr0_en <= '0';
    final_even_wr1_en <= '0';
    final_odd_wr0_en <= '0';
    final_odd_wr1_en <= '0';
    ext_even_wr0_addr <= (others => '0');
    ext_even_wr1_addr <= (others => '0');
    ext_odd_wr0_addr <= (others => '0');
    ext_odd_wr1_addr <= (others => '0');
    final_even_wr0_addr <= (others => '0');
    final_even_wr1_addr <= (others => '0');
    final_odd_wr0_addr <= (others => '0');
    final_odd_wr1_addr <= (others => '0');
    ext_even_wr0_bus <= (others => '0');
    ext_even_wr1_bus <= (others => '0');
    ext_odd_wr0_bus <= (others => '0');
    ext_odd_wr1_bus <= (others => '0');
    final_even_wr0_bus <= (others => '0');
    final_even_wr1_bus <= (others => '0');
    final_odd_wr0_bus <= (others => '0');
    final_odd_wr1_bus <= (others => '0');

    if core_out_valid(0) = '1' then
      pair_row_i := to_integer(to_01(core_out_pair_idx(0), '0'));
      if run1 = '1' then
        ext_even_wr0_en <= '1';
        ext_even_wr0_addr <= to_unsigned(pair_row_i, G_ADDR_W);
        ext_even_wr0_bus <= pack_ext_row(core_ext_even);
        ext_odd_wr0_en <= '1';
        ext_odd_wr0_addr <= to_unsigned(pair_row_i, G_ADDR_W);
        ext_odd_wr0_bus <= pack_ext_row(core_ext_odd);
        if last_half = '1' then
          final_even_wr0_en <= '1';
          final_even_wr0_addr <= to_unsigned(pair_row_i, G_ADDR_W);
          final_even_wr0_bus <= pack_post_row(core_post_even);
          final_odd_wr0_en <= '1';
          final_odd_wr0_addr <= to_unsigned(pair_row_i, G_ADDR_W);
          final_odd_wr0_bus <= pack_post_row(core_post_odd);
        end if;
      elsif run2 = '1' then
        if (pair_row_i * 2) < seg_bits then
          row_base_i := to_integer(wb_even_row_base);
          if (row_base_i / 2) < C_PAIR_MAX then
            if (row_base_i mod 2) = 0 then
              ext_even_wr0_en <= '1';
              ext_even_wr0_addr <= to_unsigned(row_base_i / 2, G_ADDR_W);
              ext_even_wr0_bus <= wb_ext_even_sorted_bus;
              if last_half = '1' then
                final_even_wr0_en <= '1';
                final_even_wr0_addr <= to_unsigned(row_base_i / 2, G_ADDR_W);
                final_even_wr0_bus <= wb_post_even_sorted_bus;
              end if;
            else
              ext_odd_wr0_en <= '1';
              ext_odd_wr0_addr <= to_unsigned(row_base_i / 2, G_ADDR_W);
              ext_odd_wr0_bus <= wb_ext_even_sorted_bus;
              if last_half = '1' then
                final_odd_wr0_en <= '1';
                final_odd_wr0_addr <= to_unsigned(row_base_i / 2, G_ADDR_W);
                final_odd_wr0_bus <= wb_post_even_sorted_bus;
              end if;
            end if;
          end if;
        end if;

        if (pair_row_i * 2 + 1) < seg_bits then
          row_base_i := to_integer(wb_odd_row_base);
          if (row_base_i / 2) < C_PAIR_MAX then
            if (row_base_i mod 2) = 0 then
              ext_even_wr1_en <= '1';
              ext_even_wr1_addr <= to_unsigned(row_base_i / 2, G_ADDR_W);
              ext_even_wr1_bus <= wb_ext_odd_sorted_bus;
              if last_half = '1' then
                final_even_wr1_en <= '1';
                final_even_wr1_addr <= to_unsigned(row_base_i / 2, G_ADDR_W);
                final_even_wr1_bus <= wb_post_odd_sorted_bus;
              end if;
            else
              ext_odd_wr1_en <= '1';
              ext_odd_wr1_addr <= to_unsigned(row_base_i / 2, G_ADDR_W);
              ext_odd_wr1_bus <= wb_ext_odd_sorted_bus;
              if last_half = '1' then
                final_odd_wr1_en <= '1';
                final_odd_wr1_addr <= to_unsigned(row_base_i / 2, G_ADDR_W);
                final_odd_wr1_bus <= wb_post_odd_sorted_bus;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  process(all)
    variable seg_i : integer;
    variable row_i : integer;
    variable pair_i : integer;
  begin
    ser_pair_addr_u <= (others => '0');
    seg_i := seg_bits;
    if ser_issue_active = '1' and seg_i > 0 then
      row_i := ser_issue_idx mod seg_i;
      pair_i := row_i / 2;
      ser_pair_addr_u <= to_unsigned(pair_i, G_ADDR_W);
    end if;
  end process;

  process(clk)
    variable k_i, seg_i, row_i, pair_row_i : integer;
    variable all_done : std_logic;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        frame_bits <= 0;
        seg_bits <= 0;
        pair_count <= 0;
        issue_active <= '0';
        issue_pair_idx <= 0;
        feed_pipe_valid <= '0';
        feed_pipe_pair_idx <= 0;
        feed_even_valid_q <= '0';
        feed_odd_valid_q <= '0';
        feed_even_is_odd_q <= '0';
        feed_odd_is_odd_q <= '0';
        feed_perm_even_q <= (others => '0');
        feed_perm_odd_q <= (others => '0');
        first_run1_pending <= '0';
        ser_issue_active <= '0';
        ser_issue_idx <= 0;
        ser_pipe_valid <= '0';
        ser_pipe_idx <= 0;
        ser_pipe_lane <= 0;
        ser_pipe_is_odd <= '0';
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

        if ser_pipe_valid = '1' then
          out_valid_q <= '1';
          out_idx_q <= to_unsigned(ser_pipe_idx, G_ADDR_W);
          if ser_pipe_is_odd = '1' then
            l_post_q <= final_odd_rd_row(ser_pipe_lane);
          else
            l_post_q <= final_even_rd_row(ser_pipe_lane);
          end if;
          if ser_pipe_idx = frame_bits - 1 then
            done_q <= '1';
          end if;
        end if;

        ser_pipe_valid <= '0';
        if ser_issue_active = '1' and seg_bits > 0 then
          ser_pipe_valid <= '1';
          ser_pipe_idx <= ser_issue_idx;
          seg_i := ser_issue_idx / seg_bits;
          row_i := ser_issue_idx mod seg_bits;
          ser_pipe_lane <= seg_i;
          ser_pipe_is_odd <= bool_to_sl((row_i mod 2) = 1);
          if ser_issue_idx = frame_bits - 1 then
            ser_issue_active <= '0';
          else
            ser_issue_idx <= ser_issue_idx + 1;
          end if;
        end if;

        if start = '1' then
          k_i := to_integer(k_len);
          assert k_i > 0 report "K must be non-zero" severity error;
          assert (k_i mod C_CORES) = 0 report "This paper-aligned top-level currently requires K divisible by 8" severity error;
          frame_bits <= k_i;
          seg_bits <= k_i / C_CORES;
          pair_count <= ((k_i / C_CORES) + 1) / 2;
          issue_active <= '0';
          issue_pair_idx <= 0;
          feed_pipe_valid <= '0';
          ser_issue_active <= '0';
          ser_issue_idx <= 0;
          ser_pipe_valid <= '0';
          first_run1_pending <= '1';
        end if;

        if (run1 = '1' and run1_d = '0') or (run2 = '1' and run2_d = '0') then
          issue_active <= '1';
          issue_pair_idx <= 0;
          feed_pipe_valid <= '0';
          for i in 0 to C_CORES-1 loop
            core_start(i) <= '1';
            core_seg_len(i) <= to_unsigned(seg_bits, G_ADDR_W);
          end loop;
        end if;

        if feed_pipe_valid = '1' then
          pair_row_i := feed_pipe_pair_idx;
          for i in 0 to C_CORES-1 loop
            core_in_valid(i) <= '1';
            core_in_pair_idx(i) <= to_unsigned(pair_row_i, G_ADDR_W);
            if run1 = '1' then
              core_sys_even(i) <= sys_even_rd0_row(i);
              core_sys_odd(i) <= sys_odd_rd0_row(i);
              core_par_even(i) <= par1_even_rd_row(i);
              core_par_odd(i) <= par1_odd_rd_row(i);
              if first_run1_pending = '1' then
                core_apri_even(i) <= (others => '0');
                core_apri_odd(i) <= (others => '0');
              else
                core_apri_even(i) <= ext_even_rd0_row(i);
                core_apri_odd(i) <= ext_odd_rd0_row(i);
              end if;
            else
              core_sys_even(i) <= phase2_sys_even_lane(i);
              core_sys_odd(i) <= phase2_sys_odd_lane(i);
              core_par_even(i) <= par2_even_rd_row(i);
              core_par_odd(i) <= par2_odd_rd_row(i);
              core_apri_even(i) <= phase2_apri_even_lane(i);
              core_apri_odd(i) <= phase2_apri_odd_lane(i);
              if feed_even_valid_q = '0' then
                core_sys_even(i) <= (others => '0');
                core_apri_even(i) <= (others => '0');
              end if;
              if feed_odd_valid_q = '0' then
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
        end if;

        feed_pipe_valid <= '0';
        if issue_active = '1' then
          pair_row_i := issue_pair_idx;
          feed_pipe_valid <= '1';
          feed_pipe_pair_idx <= pair_row_i;
          if run2 = '1' then
            feed_perm_even_q <= qpp_even_perm;
            feed_perm_odd_q <= qpp_odd_perm;
            feed_even_is_odd_q <= qpp_even_row_base(0);
            feed_odd_is_odd_q <= qpp_odd_row_base(0);
            if (pair_row_i * 2) < seg_bits then
              assert qpp_even_row_ok = '1' report "QPP even-row scheduler violated maximally-vectorizable property" severity error;
              perm_even_mem(pair_row_i) <= qpp_even_perm;
              row_base_even_mem(pair_row_i) <= qpp_even_row_base;
              feed_even_valid_q <= '1';
            else
              feed_even_valid_q <= '0';
            end if;
            if (pair_row_i * 2 + 1) < seg_bits then
              assert qpp_odd_row_ok = '1' report "QPP odd-row scheduler violated maximally-vectorizable property" severity error;
              perm_odd_mem(pair_row_i) <= qpp_odd_perm;
              row_base_odd_mem(pair_row_i) <= qpp_odd_row_base;
              feed_odd_valid_q <= '1';
            else
              feed_odd_valid_q <= '0';
            end if;
          else
            feed_even_valid_q <= '1';
            feed_odd_valid_q <= '1';
          end if;

          if issue_pair_idx = pair_count - 1 then
            issue_active <= '0';
          else
            issue_pair_idx <= issue_pair_idx + 1;
          end if;
        end if;

        for i in 1 to C_CORES-1 loop
          assert core_out_valid(i) = core_out_valid(0)
            report "SISO output-valid skew detected between parallel cores" severity error;
          if core_out_valid(i) = '1' then
            assert core_out_pair_idx(i) = core_out_pair_idx(0)
              report "SISO output index skew detected between parallel cores" severity error;
          end if;
        end loop;

        all_done := '1';
        for i in 0 to C_CORES-1 loop
          if core_done(i) = '0' then
            all_done := '0';
          end if;
        end loop;

        if run1 = '1' and all_done = '1' then
          phase1_done <= '1';
          first_run1_pending <= '0';
          if last_half = '1' then
            ser_issue_active <= '1';
            ser_issue_idx <= 0;
            ser_pipe_valid <= '0';
          end if;
        end if;

        if run2 = '1' and all_done = '1' then
          phase2_done <= '1';
          if last_half = '1' then
            ser_issue_active <= '1';
            ser_issue_idx <= 0;
            ser_pipe_valid <= '0';
          end if;
        end if;

        if ctrl_done = '1' and frame_bits = 0 then
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

