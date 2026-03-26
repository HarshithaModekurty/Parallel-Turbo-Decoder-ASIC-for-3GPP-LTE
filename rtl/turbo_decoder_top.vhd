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
  constant C_PAIR_MAX : natural := (G_K_MAX + 1) / 2;

  constant C_CH_SYS_NAT_E  : natural := 0;
  constant C_CH_SYS_NAT_O  : natural := 1;
  constant C_CH_PAR1_NAT_E : natural := 2;
  constant C_CH_PAR1_NAT_O : natural := 3;
  constant C_CH_SYS_INT_E  : natural := 4;
  constant C_CH_SYS_INT_O  : natural := 5;
  constant C_CH_PAR2_INT_E : natural := 6;
  constant C_CH_PAR2_INT_O : natural := 7;

  constant C_EXT_NAT_E : natural := 0;
  constant C_EXT_NAT_O : natural := 1;
  constant C_EXT_INT_E : natural := 2;
  constant C_EXT_INT_O : natural := 3;

  constant C_POST_INT_E   : natural := 0;
  constant C_POST_INT_O   : natural := 1;
  constant C_FINAL_NAT_E  : natural := 2;
  constant C_FINAL_NAT_O  : natural := 3;

  type chan_sig_arr_t is array (0 to 7) of chan_llr_t;
  type ext_sig_arr_t  is array (0 to 3) of ext_llr_t;
  type post_sig_arr_t is array (0 to 3) of post_llr_t;
  type chan_sl_arr_t  is array (0 to 7) of std_logic;
  type ext_sl_arr_t   is array (0 to 3) of std_logic;
  type post_sl_arr_t  is array (0 to 3) of std_logic;
  type chan_addr_arr_t is array (0 to 7) of unsigned(G_ADDR_W-1 downto 0);
  type ext_addr_arr_t  is array (0 to 3) of unsigned(G_ADDR_W-1 downto 0);
  type post_addr_arr_t is array (0 to 3) of unsigned(G_ADDR_W-1 downto 0);
  subtype coeff_idx_t is integer range 0 to (2**G_ADDR_W)-1;
  subtype frame_idx_t is integer range 0 to G_K_MAX;
  subtype pair_idx_t is integer range 0 to C_PAIR_MAX;
  subtype half_iter_t is integer range 0 to 31;
  subtype frame_acc_t is integer range 0 to 2 * G_K_MAX;

  type state_t is (
    ST_IDLE,
    ST_BUILD_SYS_INT,
    ST_START_RUN,
    ST_FEED_RUN,
    ST_WAIT_RUN,
    ST_EXT_NAT_TO_INT,
    ST_EXT_INT_TO_NAT,
    ST_FINAL_INT_TO_NAT,
    ST_SERIALIZE,
    ST_FINISH
  );

  signal st : state_t := ST_IDLE;

  signal chan_rd_en   : chan_sl_arr_t := (others => '0');
  signal chan_rd_addr : chan_addr_arr_t := (others => (others => '0'));
  signal chan_rd_data : chan_sig_arr_t := (others => (others => '0'));
  signal chan_wr_en   : chan_sl_arr_t := (others => '0');
  signal chan_wr_addr : chan_addr_arr_t := (others => (others => '0'));
  signal chan_wr_data : chan_sig_arr_t := (others => (others => '0'));

  signal ext_rd_en   : ext_sl_arr_t := (others => '0');
  signal ext_rd_addr : ext_addr_arr_t := (others => (others => '0'));
  signal ext_rd_data : ext_sig_arr_t := (others => (others => '0'));
  signal ext_wr_en   : ext_sl_arr_t := (others => '0');
  signal ext_wr_addr : ext_addr_arr_t := (others => (others => '0'));
  signal ext_wr_data : ext_sig_arr_t := (others => (others => '0'));

  signal post_rd_en   : post_sl_arr_t := (others => '0');
  signal post_rd_addr : post_addr_arr_t := (others => (others => '0'));
  signal post_rd_data : post_sig_arr_t := (others => (others => '0'));
  signal post_wr_en   : post_sl_arr_t := (others => '0');
  signal post_wr_addr : post_addr_arr_t := (others => (others => '0'));
  signal post_wr_data : post_sig_arr_t := (others => (others => '0'));

  signal frame_bits_i : frame_idx_t := 0;
  signal pair_count_i : pair_idx_t := 0;
  signal half_total_i : half_iter_t := 0;
  signal half_idx_i   : half_iter_t := 0;
  signal f1_i         : frame_idx_t := 0;
  signal f2_i         : frame_idx_t := 0;

  signal run_active    : std_logic := '0';
  signal curr_run_is_int : std_logic := '0';
  signal curr_run_last : std_logic := '0';

  signal feed_issue_idx  : pair_idx_t := 0;
  signal feed_req_valid  : std_logic := '0';
  signal feed_req_pair   : pair_idx_t := 0;
  signal feed_pipe_valid : std_logic := '0';
  signal feed_pipe_pair  : pair_idx_t := 0;

  signal perm_issue_idx     : frame_idx_t := 0;
  signal perm_req_valid     : std_logic := '0';
  signal perm_req_src_odd   : std_logic := '0';
  signal perm_req_dst_odd   : std_logic := '0';
  signal perm_req_dst_pair  : pair_idx_t := 0;
  signal perm_pipe_valid    : std_logic := '0';
  signal perm_pipe_src_odd  : std_logic := '0';
  signal perm_pipe_dst_odd  : std_logic := '0';
  signal perm_pipe_dst_pair : pair_idx_t := 0;
  signal qpp_curr_i         : frame_idx_t := 0;
  signal qpp_delta_i        : frame_idx_t := 0;
  signal qpp_step_i         : frame_idx_t := 0;

  signal ser_issue_idx   : frame_idx_t := 0;
  signal ser_req_valid   : std_logic := '0';
  signal ser_req_idx     : frame_idx_t := 0;
  signal ser_req_is_odd  : std_logic := '0';
  signal ser_pipe_valid  : std_logic := '0';
  signal ser_pipe_idx    : frame_idx_t := 0;
  signal ser_pipe_is_odd : std_logic := '0';

  signal siso_start_q    : std_logic := '0';
  signal siso_in_valid_q : std_logic := '0';
  signal siso_in_pair_idx_q : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal siso_sys_even_q : chan_llr_t := (others => '0');
  signal siso_sys_odd_q  : chan_llr_t := (others => '0');
  signal siso_par_even_q : chan_llr_t := (others => '0');
  signal siso_par_odd_q  : chan_llr_t := (others => '0');
  signal siso_apri_even_q : ext_llr_t := (others => '0');
  signal siso_apri_odd_q  : ext_llr_t := (others => '0');
  signal siso_seg_len_q   : unsigned(G_ADDR_W-1 downto 0) := (others => '0');

  signal siso_out_valid  : std_logic := '0';
  signal siso_out_pair_idx : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal siso_ext_even   : ext_llr_t := (others => '0');
  signal siso_ext_odd    : ext_llr_t := (others => '0');
  signal siso_post_even  : post_llr_t := (others => '0');
  signal siso_post_odd   : post_llr_t := (others => '0');
  signal siso_done       : std_logic := '0';

  signal out_valid_q : std_logic := '0';
  signal out_idx_q   : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal l_post_q    : post_llr_t := (others => '0');
  signal done_q      : std_logic := '0';

  function to_addr(i : integer) return unsigned is
  begin
    return to_unsigned(i, G_ADDR_W);
  end function;

  function is_odd_sl(i : integer) return std_logic is
  begin
    if (i mod 2) = 0 then
      return '0';
    else
      return '1';
    end if;
  end function;

  function qpp_add_mod(
    a_i   : frame_idx_t;
    b_i   : frame_idx_t;
    mod_i : frame_idx_t
  ) return frame_idx_t is
    variable sum_v : frame_acc_t := 0;
  begin
    if mod_i = 0 then
      return 0;
    end if;

    sum_v := a_i + b_i;
    if sum_v >= mod_i then
      sum_v := sum_v - mod_i;
    end if;
    return sum_v;
  end function;

  function qpp_double_mod(
    a_i   : frame_idx_t;
    mod_i : frame_idx_t
  ) return frame_idx_t is
    variable dbl_v : frame_acc_t := 0;
  begin
    if mod_i = 0 then
      return 0;
    end if;

    dbl_v := a_i + a_i;
    if dbl_v >= mod_i then
      dbl_v := dbl_v - mod_i;
    end if;
    return dbl_v;
  end function;
begin
  gen_chan_ram : for i in 0 to 7 generate
    ram_i : entity work.simple_dp_bram
      generic map (
        G_DEPTH => C_PAIR_MAX,
        G_ADDR_W => G_ADDR_W,
        G_DATA_W => chan_llr_t'length
      )
      port map (
        clk => clk,
        rd_en => chan_rd_en(i),
        rd_addr => chan_rd_addr(i),
        rd_data => chan_rd_data(i),
        wr_en => chan_wr_en(i),
        wr_addr => chan_wr_addr(i),
        wr_data => chan_wr_data(i)
      );
  end generate;

  gen_ext_ram : for i in 0 to 3 generate
    ram_i : entity work.simple_dp_bram
      generic map (
        G_DEPTH => C_PAIR_MAX,
        G_ADDR_W => G_ADDR_W,
        G_DATA_W => ext_llr_t'length
      )
      port map (
        clk => clk,
        rd_en => ext_rd_en(i),
        rd_addr => ext_rd_addr(i),
        rd_data => ext_rd_data(i),
        wr_en => ext_wr_en(i),
        wr_addr => ext_wr_addr(i),
        wr_data => ext_wr_data(i)
      );
  end generate;

  gen_post_ram : for i in 0 to 3 generate
    ram_i : entity work.simple_dp_bram
      generic map (
        G_DEPTH => C_PAIR_MAX,
        G_ADDR_W => G_ADDR_W,
        G_DATA_W => post_llr_t'length
      )
      port map (
        clk => clk,
        rd_en => post_rd_en(i),
        rd_addr => post_rd_addr(i),
        rd_data => post_rd_data(i),
        wr_en => post_wr_en(i),
        wr_addr => post_wr_addr(i),
        wr_data => post_wr_data(i)
      );
  end generate;

  siso_u : entity work.siso_maxlogmap
    generic map (
      G_SEG_MAX => G_K_MAX,
      G_ADDR_W => G_ADDR_W
    )
    port map (
      clk => clk,
      rst => rst,
      start => siso_start_q,
      seg_first => '1',
      seg_last => '1',
      seg_len => siso_seg_len_q,
      in_valid => siso_in_valid_q,
      in_pair_idx => siso_in_pair_idx_q,
      sys_even => siso_sys_even_q,
      sys_odd => siso_sys_odd_q,
      par_even => siso_par_even_q,
      par_odd => siso_par_odd_q,
      apri_even => siso_apri_even_q,
      apri_odd => siso_apri_odd_q,
      out_valid => siso_out_valid,
      out_pair_idx => siso_out_pair_idx,
      ext_even => siso_ext_even,
      ext_odd => siso_ext_odd,
      post_even => siso_post_even,
      post_odd => siso_post_odd,
      done => siso_done
    );

  process(clk)
    variable bit_idx_v       : coeff_idx_t;
    variable pair_idx_v      : pair_idx_t;
    variable nat_idx_v       : frame_idx_t;
    variable nat_pair_v      : pair_idx_t;
    variable dst_pair_v      : pair_idx_t;
    variable frame_bits_v    : frame_idx_t;
    variable half_total_v    : half_iter_t;
    variable f1_coeff_v      : frame_idx_t;
    variable f2_coeff_v      : frame_idx_t;
    variable pair_out_v      : pair_idx_t;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= ST_IDLE;
        frame_bits_i <= 0;
        pair_count_i <= 0;
        half_total_i <= 0;
        half_idx_i <= 0;
        f1_i <= 0;
        f2_i <= 0;
        run_active <= '0';
        curr_run_is_int <= '0';
        curr_run_last <= '0';
        feed_issue_idx <= 0;
        feed_req_valid <= '0';
        feed_req_pair <= 0;
        feed_pipe_valid <= '0';
        feed_pipe_pair <= 0;
        perm_issue_idx <= 0;
        perm_req_valid <= '0';
        perm_req_src_odd <= '0';
        perm_req_dst_odd <= '0';
        perm_req_dst_pair <= 0;
        perm_pipe_valid <= '0';
        perm_pipe_src_odd <= '0';
        perm_pipe_dst_odd <= '0';
        perm_pipe_dst_pair <= 0;
        qpp_curr_i <= 0;
        qpp_delta_i <= 0;
        qpp_step_i <= 0;
        ser_issue_idx <= 0;
        ser_req_valid <= '0';
        ser_req_idx <= 0;
        ser_req_is_odd <= '0';
        ser_pipe_valid <= '0';
        ser_pipe_idx <= 0;
        ser_pipe_is_odd <= '0';
        siso_start_q <= '0';
        siso_in_valid_q <= '0';
        siso_in_pair_idx_q <= (others => '0');
        siso_sys_even_q <= (others => '0');
        siso_sys_odd_q <= (others => '0');
        siso_par_even_q <= (others => '0');
        siso_par_odd_q <= (others => '0');
        siso_apri_even_q <= (others => '0');
        siso_apri_odd_q <= (others => '0');
        siso_seg_len_q <= (others => '0');
        out_valid_q <= '0';
        out_idx_q <= (others => '0');
        l_post_q <= (others => '0');
        done_q <= '0';
        chan_rd_en <= (others => '0');
        chan_wr_en <= (others => '0');
        ext_rd_en <= (others => '0');
        ext_wr_en <= (others => '0');
        post_rd_en <= (others => '0');
        post_wr_en <= (others => '0');
      else
        siso_start_q <= '0';
        siso_in_valid_q <= '0';
        out_valid_q <= '0';
        done_q <= '0';
        chan_rd_en <= (others => '0');
        chan_wr_en <= (others => '0');
        ext_rd_en <= (others => '0');
        ext_wr_en <= (others => '0');
        post_rd_en <= (others => '0');
        post_wr_en <= (others => '0');

        if run_active = '1' and siso_out_valid = '1' then
          pair_out_v := to_integer(siso_out_pair_idx);
          if pair_out_v >= 0 and pair_out_v < pair_count_i then
            if curr_run_is_int = '1' then
              ext_wr_en(C_EXT_INT_E) <= '1';
              ext_wr_addr(C_EXT_INT_E) <= to_addr(pair_out_v);
              ext_wr_data(C_EXT_INT_E) <= siso_ext_even;
              ext_wr_en(C_EXT_INT_O) <= '1';
              ext_wr_addr(C_EXT_INT_O) <= to_addr(pair_out_v);
              ext_wr_data(C_EXT_INT_O) <= siso_ext_odd;
              post_wr_en(C_POST_INT_E) <= '1';
              post_wr_addr(C_POST_INT_E) <= to_addr(pair_out_v);
              post_wr_data(C_POST_INT_E) <= siso_post_even;
              post_wr_en(C_POST_INT_O) <= '1';
              post_wr_addr(C_POST_INT_O) <= to_addr(pair_out_v);
              post_wr_data(C_POST_INT_O) <= siso_post_odd;
            else
              ext_wr_en(C_EXT_NAT_E) <= '1';
              ext_wr_addr(C_EXT_NAT_E) <= to_addr(pair_out_v);
              ext_wr_data(C_EXT_NAT_E) <= siso_ext_even;
              ext_wr_en(C_EXT_NAT_O) <= '1';
              ext_wr_addr(C_EXT_NAT_O) <= to_addr(pair_out_v);
              ext_wr_data(C_EXT_NAT_O) <= siso_ext_odd;
              if curr_run_last = '1' then
                post_wr_en(C_FINAL_NAT_E) <= '1';
                post_wr_addr(C_FINAL_NAT_E) <= to_addr(pair_out_v);
                post_wr_data(C_FINAL_NAT_E) <= siso_post_even;
                post_wr_en(C_FINAL_NAT_O) <= '1';
                post_wr_addr(C_FINAL_NAT_O) <= to_addr(pair_out_v);
                post_wr_data(C_FINAL_NAT_O) <= siso_post_odd;
              end if;
            end if;
          end if;
        end if;

        case st is
          when ST_IDLE =>
            if in_valid = '1' then
              bit_idx_v := to_integer(in_idx);
              if bit_idx_v >= 0 and bit_idx_v < G_K_MAX then
                pair_idx_v := bit_idx_v / 2;
                if (bit_idx_v mod 2) = 0 then
                  chan_wr_en(C_CH_SYS_NAT_E) <= '1';
                  chan_wr_addr(C_CH_SYS_NAT_E) <= to_addr(pair_idx_v);
                  chan_wr_data(C_CH_SYS_NAT_E) <= l_sys_in;
                  chan_wr_en(C_CH_PAR1_NAT_E) <= '1';
                  chan_wr_addr(C_CH_PAR1_NAT_E) <= to_addr(pair_idx_v);
                  chan_wr_data(C_CH_PAR1_NAT_E) <= l_par1_in;
                  chan_wr_en(C_CH_PAR2_INT_E) <= '1';
                  chan_wr_addr(C_CH_PAR2_INT_E) <= to_addr(pair_idx_v);
                  chan_wr_data(C_CH_PAR2_INT_E) <= l_par2_in;
                  ext_wr_en(C_EXT_NAT_E) <= '1';
                  ext_wr_addr(C_EXT_NAT_E) <= to_addr(pair_idx_v);
                  ext_wr_data(C_EXT_NAT_E) <= (others => '0');
                  ext_wr_en(C_EXT_INT_E) <= '1';
                  ext_wr_addr(C_EXT_INT_E) <= to_addr(pair_idx_v);
                  ext_wr_data(C_EXT_INT_E) <= (others => '0');
                  post_wr_en(C_POST_INT_E) <= '1';
                  post_wr_addr(C_POST_INT_E) <= to_addr(pair_idx_v);
                  post_wr_data(C_POST_INT_E) <= (others => '0');
                  post_wr_en(C_FINAL_NAT_E) <= '1';
                  post_wr_addr(C_FINAL_NAT_E) <= to_addr(pair_idx_v);
                  post_wr_data(C_FINAL_NAT_E) <= (others => '0');
                else
                  chan_wr_en(C_CH_SYS_NAT_O) <= '1';
                  chan_wr_addr(C_CH_SYS_NAT_O) <= to_addr(pair_idx_v);
                  chan_wr_data(C_CH_SYS_NAT_O) <= l_sys_in;
                  chan_wr_en(C_CH_PAR1_NAT_O) <= '1';
                  chan_wr_addr(C_CH_PAR1_NAT_O) <= to_addr(pair_idx_v);
                  chan_wr_data(C_CH_PAR1_NAT_O) <= l_par1_in;
                  chan_wr_en(C_CH_PAR2_INT_O) <= '1';
                  chan_wr_addr(C_CH_PAR2_INT_O) <= to_addr(pair_idx_v);
                  chan_wr_data(C_CH_PAR2_INT_O) <= l_par2_in;
                  ext_wr_en(C_EXT_NAT_O) <= '1';
                  ext_wr_addr(C_EXT_NAT_O) <= to_addr(pair_idx_v);
                  ext_wr_data(C_EXT_NAT_O) <= (others => '0');
                  ext_wr_en(C_EXT_INT_O) <= '1';
                  ext_wr_addr(C_EXT_INT_O) <= to_addr(pair_idx_v);
                  ext_wr_data(C_EXT_INT_O) <= (others => '0');
                  post_wr_en(C_POST_INT_O) <= '1';
                  post_wr_addr(C_POST_INT_O) <= to_addr(pair_idx_v);
                  post_wr_data(C_POST_INT_O) <= (others => '0');
                  post_wr_en(C_FINAL_NAT_O) <= '1';
                  post_wr_addr(C_FINAL_NAT_O) <= to_addr(pair_idx_v);
                  post_wr_data(C_FINAL_NAT_O) <= (others => '0');
                end if;
              end if;
            end if;

            if start = '1' then
              if to_integer(k_len) > G_K_MAX then
                frame_bits_v := G_K_MAX;
              else
                frame_bits_v := to_integer(k_len);
              end if;
              half_total_v := to_integer(n_half_iter);
              f1_coeff_v := to_integer(f1);
              f2_coeff_v := to_integer(f2);
              frame_bits_i <= frame_bits_v;
              pair_count_i <= (frame_bits_v + 1) / 2;
              half_total_i <= half_total_v;
              half_idx_i <= 0;
              f1_i <= f1_coeff_v;
              f2_i <= f2_coeff_v;
              siso_seg_len_q <= k_len;
              perm_issue_idx <= 0;
              perm_req_valid <= '0';
              perm_req_src_odd <= '0';
              perm_req_dst_odd <= '0';
              perm_req_dst_pair <= 0;
              perm_pipe_valid <= '0';
              perm_pipe_src_odd <= '0';
              perm_pipe_dst_odd <= '0';
              perm_pipe_dst_pair <= 0;
              qpp_curr_i <= 0;
              qpp_delta_i <= qpp_add_mod(f1_coeff_v, f2_coeff_v, frame_bits_v);
              qpp_step_i <= qpp_double_mod(f2_coeff_v, frame_bits_v);
              ser_issue_idx <= 0;
              ser_req_valid <= '0';
              ser_req_idx <= 0;
              ser_req_is_odd <= '0';
              ser_pipe_valid <= '0';
              if frame_bits_v <= 0 or half_total_v <= 0 then
                st <= ST_FINISH;
              else
                st <= ST_BUILD_SYS_INT;
              end if;
            end if;

          when ST_BUILD_SYS_INT =>
            if perm_pipe_valid = '1' then
              if perm_pipe_dst_odd = '1' then
                chan_wr_en(C_CH_SYS_INT_O) <= '1';
                chan_wr_addr(C_CH_SYS_INT_O) <= to_addr(perm_pipe_dst_pair);
                if perm_pipe_src_odd = '1' then
                  chan_wr_data(C_CH_SYS_INT_O) <= chan_rd_data(C_CH_SYS_NAT_O);
                else
                  chan_wr_data(C_CH_SYS_INT_O) <= chan_rd_data(C_CH_SYS_NAT_E);
                end if;
              else
                chan_wr_en(C_CH_SYS_INT_E) <= '1';
                chan_wr_addr(C_CH_SYS_INT_E) <= to_addr(perm_pipe_dst_pair);
                if perm_pipe_src_odd = '1' then
                  chan_wr_data(C_CH_SYS_INT_E) <= chan_rd_data(C_CH_SYS_NAT_O);
                else
                  chan_wr_data(C_CH_SYS_INT_E) <= chan_rd_data(C_CH_SYS_NAT_E);
                end if;
              end if;
            end if;

            perm_pipe_valid <= perm_req_valid;
            perm_pipe_src_odd <= perm_req_src_odd;
            perm_pipe_dst_odd <= perm_req_dst_odd;
            perm_pipe_dst_pair <= perm_req_dst_pair;

            if perm_issue_idx < frame_bits_i then
              nat_idx_v := qpp_curr_i;
              nat_pair_v := nat_idx_v / 2;
              if (nat_idx_v mod 2) = 0 then
                chan_rd_en(C_CH_SYS_NAT_E) <= '1';
                chan_rd_addr(C_CH_SYS_NAT_E) <= to_addr(nat_pair_v);
                perm_req_src_odd <= '0';
              else
                chan_rd_en(C_CH_SYS_NAT_O) <= '1';
                chan_rd_addr(C_CH_SYS_NAT_O) <= to_addr(nat_pair_v);
                perm_req_src_odd <= '1';
              end if;
              perm_req_dst_pair <= perm_issue_idx / 2;
              perm_req_dst_odd <= is_odd_sl(perm_issue_idx);
              perm_issue_idx <= perm_issue_idx + 1;
              qpp_curr_i <= qpp_add_mod(qpp_curr_i, qpp_delta_i, frame_bits_i);
              qpp_delta_i <= qpp_add_mod(qpp_delta_i, qpp_step_i, frame_bits_i);
              perm_req_valid <= '1';
            elsif perm_req_valid = '1' then
              perm_req_valid <= '0';
            elsif perm_pipe_valid = '0' then
              st <= ST_START_RUN;
            end if;

          when ST_START_RUN =>
            run_active <= '1';
            if (half_idx_i mod 2) = 0 then
              curr_run_is_int <= '0';
            else
              curr_run_is_int <= '1';
            end if;

            if (half_idx_i + 1) >= half_total_i then
              curr_run_last <= '1';
            else
              curr_run_last <= '0';
            end if;

            siso_start_q <= '1';
            feed_issue_idx <= 0;
            feed_req_valid <= '0';
            feed_pipe_valid <= '0';

            if pair_count_i = 0 then
              st <= ST_WAIT_RUN;
            else
              if (half_idx_i mod 2) = 0 then
                chan_rd_en(C_CH_SYS_NAT_E) <= '1';
                chan_rd_addr(C_CH_SYS_NAT_E) <= (others => '0');
                chan_rd_en(C_CH_SYS_NAT_O) <= '1';
                chan_rd_addr(C_CH_SYS_NAT_O) <= (others => '0');
                chan_rd_en(C_CH_PAR1_NAT_E) <= '1';
                chan_rd_addr(C_CH_PAR1_NAT_E) <= (others => '0');
                chan_rd_en(C_CH_PAR1_NAT_O) <= '1';
                chan_rd_addr(C_CH_PAR1_NAT_O) <= (others => '0');
                ext_rd_en(C_EXT_NAT_E) <= '1';
                ext_rd_addr(C_EXT_NAT_E) <= (others => '0');
                ext_rd_en(C_EXT_NAT_O) <= '1';
                ext_rd_addr(C_EXT_NAT_O) <= (others => '0');
              else
                chan_rd_en(C_CH_SYS_INT_E) <= '1';
                chan_rd_addr(C_CH_SYS_INT_E) <= (others => '0');
                chan_rd_en(C_CH_SYS_INT_O) <= '1';
                chan_rd_addr(C_CH_SYS_INT_O) <= (others => '0');
                chan_rd_en(C_CH_PAR2_INT_E) <= '1';
                chan_rd_addr(C_CH_PAR2_INT_E) <= (others => '0');
                chan_rd_en(C_CH_PAR2_INT_O) <= '1';
                chan_rd_addr(C_CH_PAR2_INT_O) <= (others => '0');
                ext_rd_en(C_EXT_INT_E) <= '1';
                ext_rd_addr(C_EXT_INT_E) <= (others => '0');
                ext_rd_en(C_EXT_INT_O) <= '1';
                ext_rd_addr(C_EXT_INT_O) <= (others => '0');
              end if;
              feed_issue_idx <= 1;
              feed_req_pair <= 0;
              feed_req_valid <= '1';
              st <= ST_FEED_RUN;
            end if;

          when ST_FEED_RUN =>
            if feed_pipe_valid = '1' then
              siso_in_valid_q <= '1';
              siso_in_pair_idx_q <= to_addr(feed_pipe_pair);
              if curr_run_is_int = '1' then
                siso_sys_even_q <= chan_rd_data(C_CH_SYS_INT_E);
                siso_sys_odd_q <= chan_rd_data(C_CH_SYS_INT_O);
                siso_par_even_q <= chan_rd_data(C_CH_PAR2_INT_E);
                siso_par_odd_q <= chan_rd_data(C_CH_PAR2_INT_O);
                siso_apri_even_q <= ext_rd_data(C_EXT_INT_E);
                siso_apri_odd_q <= ext_rd_data(C_EXT_INT_O);
              else
                siso_sys_even_q <= chan_rd_data(C_CH_SYS_NAT_E);
                siso_sys_odd_q <= chan_rd_data(C_CH_SYS_NAT_O);
                siso_par_even_q <= chan_rd_data(C_CH_PAR1_NAT_E);
                siso_par_odd_q <= chan_rd_data(C_CH_PAR1_NAT_O);
                siso_apri_even_q <= ext_rd_data(C_EXT_NAT_E);
                siso_apri_odd_q <= ext_rd_data(C_EXT_NAT_O);
              end if;
            end if;

            feed_pipe_valid <= feed_req_valid;
            feed_pipe_pair <= feed_req_pair;

            if feed_issue_idx < pair_count_i then
              if curr_run_is_int = '1' then
                chan_rd_en(C_CH_SYS_INT_E) <= '1';
                chan_rd_addr(C_CH_SYS_INT_E) <= to_addr(feed_issue_idx);
                chan_rd_en(C_CH_SYS_INT_O) <= '1';
                chan_rd_addr(C_CH_SYS_INT_O) <= to_addr(feed_issue_idx);
                chan_rd_en(C_CH_PAR2_INT_E) <= '1';
                chan_rd_addr(C_CH_PAR2_INT_E) <= to_addr(feed_issue_idx);
                chan_rd_en(C_CH_PAR2_INT_O) <= '1';
                chan_rd_addr(C_CH_PAR2_INT_O) <= to_addr(feed_issue_idx);
                ext_rd_en(C_EXT_INT_E) <= '1';
                ext_rd_addr(C_EXT_INT_E) <= to_addr(feed_issue_idx);
                ext_rd_en(C_EXT_INT_O) <= '1';
                ext_rd_addr(C_EXT_INT_O) <= to_addr(feed_issue_idx);
              else
                chan_rd_en(C_CH_SYS_NAT_E) <= '1';
                chan_rd_addr(C_CH_SYS_NAT_E) <= to_addr(feed_issue_idx);
                chan_rd_en(C_CH_SYS_NAT_O) <= '1';
                chan_rd_addr(C_CH_SYS_NAT_O) <= to_addr(feed_issue_idx);
                chan_rd_en(C_CH_PAR1_NAT_E) <= '1';
                chan_rd_addr(C_CH_PAR1_NAT_E) <= to_addr(feed_issue_idx);
                chan_rd_en(C_CH_PAR1_NAT_O) <= '1';
                chan_rd_addr(C_CH_PAR1_NAT_O) <= to_addr(feed_issue_idx);
                ext_rd_en(C_EXT_NAT_E) <= '1';
                ext_rd_addr(C_EXT_NAT_E) <= to_addr(feed_issue_idx);
                ext_rd_en(C_EXT_NAT_O) <= '1';
                ext_rd_addr(C_EXT_NAT_O) <= to_addr(feed_issue_idx);
              end if;
              feed_req_pair <= feed_issue_idx;
              feed_issue_idx <= feed_issue_idx + 1;
              feed_req_valid <= '1';
            elsif feed_req_valid = '1' then
              feed_req_valid <= '0';
            elsif feed_pipe_valid = '0' then
              st <= ST_WAIT_RUN;
            end if;

          when ST_WAIT_RUN =>
            if siso_done = '1' then
              run_active <= '0';
              feed_req_valid <= '0';
              feed_pipe_valid <= '0';
              perm_issue_idx <= 0;
              perm_req_valid <= '0';
              perm_pipe_valid <= '0';
              if curr_run_last = '1' then
                if curr_run_is_int = '1' then
                  qpp_curr_i <= 0;
                  qpp_delta_i <= qpp_add_mod(f1_i, f2_i, frame_bits_i);
                  qpp_step_i <= qpp_double_mod(f2_i, frame_bits_i);
                  st <= ST_FINAL_INT_TO_NAT;
                else
                  ser_issue_idx <= 0;
                  ser_req_valid <= '0';
                  ser_pipe_valid <= '0';
                  st <= ST_SERIALIZE;
                end if;
              else
                half_idx_i <= half_idx_i + 1;
                qpp_curr_i <= 0;
                qpp_delta_i <= qpp_add_mod(f1_i, f2_i, frame_bits_i);
                qpp_step_i <= qpp_double_mod(f2_i, frame_bits_i);
                if curr_run_is_int = '1' then
                  st <= ST_EXT_INT_TO_NAT;
                else
                  st <= ST_EXT_NAT_TO_INT;
                end if;
              end if;
            end if;

          when ST_EXT_NAT_TO_INT =>
            if perm_pipe_valid = '1' then
              if perm_pipe_dst_odd = '1' then
                ext_wr_en(C_EXT_INT_O) <= '1';
                ext_wr_addr(C_EXT_INT_O) <= to_addr(perm_pipe_dst_pair);
                if perm_pipe_src_odd = '1' then
                  ext_wr_data(C_EXT_INT_O) <= ext_rd_data(C_EXT_NAT_O);
                else
                  ext_wr_data(C_EXT_INT_O) <= ext_rd_data(C_EXT_NAT_E);
                end if;
              else
                ext_wr_en(C_EXT_INT_E) <= '1';
                ext_wr_addr(C_EXT_INT_E) <= to_addr(perm_pipe_dst_pair);
                if perm_pipe_src_odd = '1' then
                  ext_wr_data(C_EXT_INT_E) <= ext_rd_data(C_EXT_NAT_O);
                else
                  ext_wr_data(C_EXT_INT_E) <= ext_rd_data(C_EXT_NAT_E);
                end if;
              end if;
            end if;

            perm_pipe_valid <= perm_req_valid;
            perm_pipe_src_odd <= perm_req_src_odd;
            perm_pipe_dst_odd <= perm_req_dst_odd;
            perm_pipe_dst_pair <= perm_req_dst_pair;

            if perm_issue_idx < frame_bits_i then
              nat_idx_v := qpp_curr_i;
              nat_pair_v := nat_idx_v / 2;
              if (nat_idx_v mod 2) = 0 then
                ext_rd_en(C_EXT_NAT_E) <= '1';
                ext_rd_addr(C_EXT_NAT_E) <= to_addr(nat_pair_v);
                perm_req_src_odd <= '0';
              else
                ext_rd_en(C_EXT_NAT_O) <= '1';
                ext_rd_addr(C_EXT_NAT_O) <= to_addr(nat_pair_v);
                perm_req_src_odd <= '1';
              end if;
              perm_req_dst_pair <= perm_issue_idx / 2;
              perm_req_dst_odd <= is_odd_sl(perm_issue_idx);
              perm_issue_idx <= perm_issue_idx + 1;
              qpp_curr_i <= qpp_add_mod(qpp_curr_i, qpp_delta_i, frame_bits_i);
              qpp_delta_i <= qpp_add_mod(qpp_delta_i, qpp_step_i, frame_bits_i);
              perm_req_valid <= '1';
            elsif perm_req_valid = '1' then
              perm_req_valid <= '0';
            elsif perm_pipe_valid = '0' then
              st <= ST_START_RUN;
            end if;

          when ST_EXT_INT_TO_NAT =>
            if perm_pipe_valid = '1' then
              if perm_pipe_dst_odd = '1' then
                ext_wr_en(C_EXT_NAT_O) <= '1';
                ext_wr_addr(C_EXT_NAT_O) <= to_addr(perm_pipe_dst_pair);
                if perm_pipe_src_odd = '1' then
                  ext_wr_data(C_EXT_NAT_O) <= ext_rd_data(C_EXT_INT_O);
                else
                  ext_wr_data(C_EXT_NAT_O) <= ext_rd_data(C_EXT_INT_E);
                end if;
              else
                ext_wr_en(C_EXT_NAT_E) <= '1';
                ext_wr_addr(C_EXT_NAT_E) <= to_addr(perm_pipe_dst_pair);
                if perm_pipe_src_odd = '1' then
                  ext_wr_data(C_EXT_NAT_E) <= ext_rd_data(C_EXT_INT_O);
                else
                  ext_wr_data(C_EXT_NAT_E) <= ext_rd_data(C_EXT_INT_E);
                end if;
              end if;
            end if;

            perm_pipe_valid <= perm_req_valid;
            perm_pipe_src_odd <= perm_req_src_odd;
            perm_pipe_dst_odd <= perm_req_dst_odd;
            perm_pipe_dst_pair <= perm_req_dst_pair;

            if perm_issue_idx < frame_bits_i then
              nat_idx_v := qpp_curr_i;
              dst_pair_v := nat_idx_v / 2;
              if (perm_issue_idx mod 2) = 0 then
                ext_rd_en(C_EXT_INT_E) <= '1';
                ext_rd_addr(C_EXT_INT_E) <= to_addr(perm_issue_idx / 2);
                perm_req_src_odd <= '0';
              else
                ext_rd_en(C_EXT_INT_O) <= '1';
                ext_rd_addr(C_EXT_INT_O) <= to_addr(perm_issue_idx / 2);
                perm_req_src_odd <= '1';
              end if;
              perm_req_dst_pair <= dst_pair_v;
              perm_req_dst_odd <= is_odd_sl(nat_idx_v);
              perm_issue_idx <= perm_issue_idx + 1;
              qpp_curr_i <= qpp_add_mod(qpp_curr_i, qpp_delta_i, frame_bits_i);
              qpp_delta_i <= qpp_add_mod(qpp_delta_i, qpp_step_i, frame_bits_i);
              perm_req_valid <= '1';
            elsif perm_req_valid = '1' then
              perm_req_valid <= '0';
            elsif perm_pipe_valid = '0' then
              st <= ST_START_RUN;
            end if;

          when ST_FINAL_INT_TO_NAT =>
            if perm_pipe_valid = '1' then
              if perm_pipe_dst_odd = '1' then
                post_wr_en(C_FINAL_NAT_O) <= '1';
                post_wr_addr(C_FINAL_NAT_O) <= to_addr(perm_pipe_dst_pair);
                if perm_pipe_src_odd = '1' then
                  post_wr_data(C_FINAL_NAT_O) <= post_rd_data(C_POST_INT_O);
                else
                  post_wr_data(C_FINAL_NAT_O) <= post_rd_data(C_POST_INT_E);
                end if;
              else
                post_wr_en(C_FINAL_NAT_E) <= '1';
                post_wr_addr(C_FINAL_NAT_E) <= to_addr(perm_pipe_dst_pair);
                if perm_pipe_src_odd = '1' then
                  post_wr_data(C_FINAL_NAT_E) <= post_rd_data(C_POST_INT_O);
                else
                  post_wr_data(C_FINAL_NAT_E) <= post_rd_data(C_POST_INT_E);
                end if;
              end if;
            end if;

            perm_pipe_valid <= perm_req_valid;
            perm_pipe_src_odd <= perm_req_src_odd;
            perm_pipe_dst_odd <= perm_req_dst_odd;
            perm_pipe_dst_pair <= perm_req_dst_pair;

            if perm_issue_idx < frame_bits_i then
              nat_idx_v := qpp_curr_i;
              dst_pair_v := nat_idx_v / 2;
              if (perm_issue_idx mod 2) = 0 then
                post_rd_en(C_POST_INT_E) <= '1';
                post_rd_addr(C_POST_INT_E) <= to_addr(perm_issue_idx / 2);
                perm_req_src_odd <= '0';
              else
                post_rd_en(C_POST_INT_O) <= '1';
                post_rd_addr(C_POST_INT_O) <= to_addr(perm_issue_idx / 2);
                perm_req_src_odd <= '1';
              end if;
              perm_req_dst_pair <= dst_pair_v;
              perm_req_dst_odd <= is_odd_sl(nat_idx_v);
              perm_issue_idx <= perm_issue_idx + 1;
              qpp_curr_i <= qpp_add_mod(qpp_curr_i, qpp_delta_i, frame_bits_i);
              qpp_delta_i <= qpp_add_mod(qpp_delta_i, qpp_step_i, frame_bits_i);
              perm_req_valid <= '1';
            elsif perm_req_valid = '1' then
              perm_req_valid <= '0';
            elsif perm_pipe_valid = '0' then
              ser_issue_idx <= 0;
              ser_req_valid <= '0';
              ser_pipe_valid <= '0';
              st <= ST_SERIALIZE;
            end if;

          when ST_SERIALIZE =>
            if ser_pipe_valid = '1' then
              out_valid_q <= '1';
              out_idx_q <= to_addr(ser_pipe_idx);
              if ser_pipe_is_odd = '1' then
                l_post_q <= post_rd_data(C_FINAL_NAT_O);
              else
                l_post_q <= post_rd_data(C_FINAL_NAT_E);
              end if;
            end if;

            ser_pipe_valid <= ser_req_valid;
            ser_pipe_idx <= ser_req_idx;
            ser_pipe_is_odd <= ser_req_is_odd;

            if ser_issue_idx < frame_bits_i then
              if (ser_issue_idx mod 2) = 0 then
                post_rd_en(C_FINAL_NAT_E) <= '1';
                post_rd_addr(C_FINAL_NAT_E) <= to_addr(ser_issue_idx / 2);
                ser_req_is_odd <= '0';
              else
                post_rd_en(C_FINAL_NAT_O) <= '1';
                post_rd_addr(C_FINAL_NAT_O) <= to_addr(ser_issue_idx / 2);
                ser_req_is_odd <= '1';
              end if;
              ser_req_idx <= ser_issue_idx;
              ser_issue_idx <= ser_issue_idx + 1;
              ser_req_valid <= '1';
            elsif ser_req_valid = '1' then
              ser_req_valid <= '0';
            elsif ser_pipe_valid = '0' then
              st <= ST_FINISH;
            end if;

          when ST_FINISH =>
            done_q <= '1';
            run_active <= '0';
            st <= ST_IDLE;

          when others =>
            st <= ST_IDLE;
        end case;
      end if;
    end if;
  end process;

  out_valid <= out_valid_q;
  out_idx <= out_idx_q;
  l_post <= l_post_q;
  done <= done_q;
end architecture;
