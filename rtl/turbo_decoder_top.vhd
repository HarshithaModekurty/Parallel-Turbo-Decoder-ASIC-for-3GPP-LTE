library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity turbo_decoder_top is
  generic (
    G_K_MAX : natural := 6144;
    G_ADDR_W : natural := 13
  );
  port (
    clk, rst : in std_logic;
    start : in std_logic;
    n_iter : in unsigned(3 downto 0);
    k_len  : in unsigned(G_ADDR_W-1 downto 0);
    f1, f2 : in unsigned(G_ADDR_W-1 downto 0);
    in_valid : in std_logic;
    in_idx : in unsigned(G_ADDR_W-1 downto 0);
    l_sys_in, l_par1_in, l_par2_in : in llr_t;
    out_valid : out std_logic;
    out_idx   : out unsigned(G_ADDR_W-1 downto 0);
    l_post    : out llr_t;
    done      : out std_logic
  );
end entity;

architecture rtl of turbo_decoder_top is
  type llr_mem_t is array (0 to G_K_MAX-1) of llr_t;

  signal sys_buf  : llr_mem_t := (others => (others => '0'));
  signal par1_buf : llr_mem_t := (others => (others => '0'));
  signal par2_buf : llr_mem_t := (others => (others => '0'));
  signal sys2_buf : llr_mem_t := (others => (others => '0'));
  signal apr2_buf : llr_mem_t := (others => (others => '0'));

  signal run1,run2,siso1_done,siso2_done,phase,ctrl_done : std_logic := '0';
  signal ext1_v, ext2_v : std_logic := '0';
  signal ext1_idx,ext2_idx,pi_idx : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal ext1,ext2 : llr_t := (others => '0');
  signal apr1, apr2 : llr_t := (others => '0');
  signal pi_valid : std_logic := '0';
  signal ext_mem_r : llr_t := (others => '0');

  signal run1_d, run2_d : std_logic := '0';
  signal feed1_active, feed2_active : std_logic := '0';
  signal feed1_idx, feed2_idx : integer range 0 to G_K_MAX := 0;
  signal s1_in_valid : std_logic := '0';
  signal s1_in_idx : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal s1_lsys, s1_lpar : llr_t := (others => '0');

  signal s2_req_valid : std_logic := '0';
  signal s2_req_idx : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal s2_req_lpar : llr_t := (others => '0');
  signal s2_req_valid_d1 : std_logic := '0';
  signal s2_req_idx_d1 : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal s2_req_lpar_d1 : llr_t := (others => '0');
  signal s2_stage1_valid : std_logic := '0';
  signal s2_stage1_idx, s2_stage1_pi : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal s2_stage1_lsys, s2_stage1_lpar : llr_t := (others => '0');
  signal s2_stage2_valid : std_logic := '0';
  signal s2_stage2_idx : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal s2_stage2_lsys, s2_stage2_lpar : llr_t := (others => '0');
begin
  ctrl : entity work.turbo_iteration_ctrl
    port map (
      clk=>clk, rst=>rst, start=>start, n_iter=>n_iter,
      siso_done_1=>siso1_done, siso_done_2=>siso2_done,
      run_siso_1=>run1, run_siso_2=>run2, deint_phase=>phase, done=>ctrl_done);

  -- Capture external LLR inputs and replay internally for each half-iteration.
  process(clk)
    variable in_i : integer;
    variable k_i : integer;
    variable idx_i : integer;
  begin
    if rising_edge(clk) then
      if rst='1' then
        run1_d <= '0';
        run2_d <= '0';
        feed1_active <= '0';
        feed2_active <= '0';
        feed1_idx <= 0;
        feed2_idx <= 0;
        s1_in_valid <= '0';
        s1_in_idx <= (others => '0');
        s1_lsys <= (others => '0');
        s1_lpar <= (others => '0');
        s2_req_valid <= '0';
        s2_req_idx <= (others => '0');
        s2_req_lpar <= (others => '0');
        s2_req_valid_d1 <= '0';
        s2_req_idx_d1 <= (others => '0');
        s2_req_lpar_d1 <= (others => '0');
        s2_stage1_valid <= '0';
        s2_stage1_idx <= (others => '0');
        s2_stage1_pi <= (others => '0');
        s2_stage1_lsys <= (others => '0');
        s2_stage1_lpar <= (others => '0');
        s2_stage2_valid <= '0';
        s2_stage2_idx <= (others => '0');
        s2_stage2_lsys <= (others => '0');
        s2_stage2_lpar <= (others => '0');
      else
        s1_in_valid <= '0';
        s2_req_valid <= '0';
        s2_stage1_valid <= '0';
        s2_stage2_valid <= '0';

        if in_valid='1' then
          in_i := to_integer(in_idx);
          if in_i >= 0 and in_i < G_K_MAX then
            sys_buf(in_i) <= l_sys_in;
            par1_buf(in_i) <= l_par1_in;
            par2_buf(in_i) <= l_par2_in;
          end if;
        end if;

        if run1='1' and run1_d='0' then
          feed1_active <= '1';
          feed1_idx <= 0;
        elsif run1='0' then
          feed1_active <= '0';
        end if;

        if run2='1' and run2_d='0' then
          feed2_active <= '1';
          feed2_idx <= 0;
        elsif run2='0' then
          feed2_active <= '0';
        end if;

        k_i := to_integer(k_len);
        if k_i > G_K_MAX then
          k_i := G_K_MAX;
        end if;

        if feed1_active='1' then
          if feed1_idx < k_i then
            s1_in_valid <= '1';
            s1_in_idx <= to_unsigned(feed1_idx, G_ADDR_W);
            s1_lsys <= sys_buf(feed1_idx);
            s1_lpar <= par1_buf(feed1_idx);
            feed1_idx <= feed1_idx + 1;
          else
            feed1_active <= '0';
          end if;
        end if;

        if feed2_active='1' then
          if feed2_idx < k_i then
            s2_req_valid <= '1';
            s2_req_idx <= to_unsigned(feed2_idx, G_ADDR_W);
            s2_req_lpar <= par2_buf(feed2_idx);
            feed2_idx <= feed2_idx + 1;
          else
            feed2_active <= '0';
          end if;
        end if;

        -- Align second-SISO stream to QPP + RAM latency.
        s2_req_valid_d1 <= s2_req_valid;
        s2_req_idx_d1 <= s2_req_idx;
        s2_req_lpar_d1 <= s2_req_lpar;

        if pi_valid='1' and s2_req_valid_d1='1' then
          s2_stage1_valid <= '1';
          s2_stage1_idx <= s2_req_idx_d1;
          s2_stage1_pi <= pi_idx;
          s2_stage1_lpar <= s2_req_lpar_d1;
          idx_i := to_integer(pi_idx);
          if idx_i >= 0 and idx_i < G_K_MAX then
            s2_stage1_lsys <= sys_buf(idx_i);
          else
            s2_stage1_lsys <= (others => '0');
          end if;
        end if;

        s2_stage2_valid <= s2_stage1_valid;
        s2_stage2_idx <= s2_stage1_idx;
        s2_stage2_lsys <= s2_stage1_lsys;
        s2_stage2_lpar <= s2_stage1_lpar;
        if s2_stage2_valid='1' then
          idx_i := to_integer(s2_stage2_idx);
          if idx_i >= 0 and idx_i < G_K_MAX then
            sys2_buf(idx_i) <= s2_stage2_lsys;
            apr2_buf(idx_i) <= ext_mem_r;
          end if;
        end if;

        run1_d <= run1;
        run2_d <= run2;
      end if;
    end if;
  end process;

  inter : entity work.qpp_interleaver
    generic map (G_K_MAX=>G_K_MAX, G_ADDR_W=>G_ADDR_W)
    port map (clk=>clk, rst=>rst, start=>'1', valid=>s2_req_valid, k_len=>k_len, f1=>f1, f2=>f2,
      idx_i=>s2_req_idx, idx_o=>pi_idx, idx_valid=>pi_valid);

  apr_ram : entity work.llr_ram
    generic map (G_DEPTH=>G_K_MAX, G_ADDR_W=>G_ADDR_W)
    port map (clk=>clk, we=>ext1_v, waddr=>ext1_idx, wdata=>ext1, raddr=>s2_stage1_pi, rdata=>ext_mem_r);

  -- Baseline keeps first-SISO a-priori at zero for stability in this modular model.
  apr1 <= (others => '0');
  apr2 <= ext_mem_r;

  siso1 : entity work.siso_maxlogmap
    generic map (G_K_MAX=>G_K_MAX, G_ADDR_W=>G_ADDR_W)
    port map (
      clk=>clk, rst=>rst, start=>run1, k_len=>k_len, in_valid=>s1_in_valid, in_idx=>s1_in_idx,
      l_sys=>s1_lsys, l_par=>s1_lpar, l_apri=>apr1,
      out_valid=>ext1_v, out_idx=>ext1_idx, l_ext=>ext1, done=>siso1_done);

  siso2 : entity work.siso_maxlogmap
    generic map (G_K_MAX=>G_K_MAX, G_ADDR_W=>G_ADDR_W)
    port map (
      clk=>clk, rst=>rst, start=>run2, k_len=>k_len, in_valid=>s2_stage2_valid, in_idx=>s2_stage2_idx,
      l_sys=>s2_stage2_lsys, l_par=>s2_stage2_lpar, l_apri=>apr2,
      out_valid=>ext2_v, out_idx=>ext2_idx, l_ext=>ext2, done=>siso2_done);

  out_valid <= ext2_v;
  out_idx <= ext2_idx;
  process(all)
    variable idx_i : integer;
    variable post_m : metric_t;
  begin
    l_post <= (others => '0');
    if ext2_v='1' and not is_x(std_logic_vector(ext2_idx)) then
      idx_i := to_integer(ext2_idx);
      if idx_i >= 0 and idx_i < G_K_MAX then
        post_m := sat_add(
                    resize_llr_to_metric(ext2),
                    sat_add(resize_llr_to_metric(sys2_buf(idx_i)), resize_llr_to_metric(apr2_buf(idx_i)))
                  );
        l_post <= metric_to_llr_sat(post_m);
      end if;
    end if;
  end process;
  done <= ctrl_done;
end architecture;
