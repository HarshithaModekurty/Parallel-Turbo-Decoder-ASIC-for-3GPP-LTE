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
  signal run1,run2,siso1_done,siso2_done,phase,ctrl_done : std_logic;
  signal ext1_v, ext2_v : std_logic;
  signal ext1_idx,ext2_idx,pi_idx : unsigned(G_ADDR_W-1 downto 0);
  signal ext1,ext2 : llr_t;
  signal apr1, apr2 : llr_t;
  signal pi_valid : std_logic;
  signal ext_mem_r : llr_t;
begin
  ctrl : entity work.turbo_iteration_ctrl
    port map (
      clk=>clk, rst=>rst, start=>start, n_iter=>n_iter,
      siso_done_1=>siso1_done, siso_done_2=>siso2_done,
      run_siso_1=>run1, run_siso_2=>run2, deint_phase=>phase, done=>ctrl_done);

  inter : entity work.qpp_interleaver
    generic map (G_K_MAX=>G_K_MAX, G_ADDR_W=>G_ADDR_W)
    port map (clk=>clk, rst=>rst, start=>'1', valid=>in_valid, k_len=>k_len, f1=>f1, f2=>f2,
      idx_i=>in_idx, idx_o=>pi_idx, idx_valid=>pi_valid);

  apr_ram : entity work.llr_ram
    generic map (G_DEPTH=>G_K_MAX, G_ADDR_W=>G_ADDR_W)
    port map (clk=>clk, we=>ext1_v, waddr=>ext1_idx, wdata=>ext1, raddr=>pi_idx, rdata=>ext_mem_r);

  apr1 <= ext_mem_r;
  apr2 <= ext_mem_r;

  siso1 : entity work.siso_maxlogmap
    generic map (G_K_MAX=>G_K_MAX, G_ADDR_W=>G_ADDR_W)
    port map (
      clk=>clk, rst=>rst, start=>run1, k_len=>k_len, in_valid=>in_valid, in_idx=>in_idx,
      l_sys=>l_sys_in, l_par=>l_par1_in, l_apri=>apr1,
      out_valid=>ext1_v, out_idx=>ext1_idx, l_ext=>ext1, done=>siso1_done);

  siso2 : entity work.siso_maxlogmap
    generic map (G_K_MAX=>G_K_MAX, G_ADDR_W=>G_ADDR_W)
    port map (
      clk=>clk, rst=>rst, start=>run2, k_len=>k_len, in_valid=>in_valid, in_idx=>pi_idx,
      l_sys=>l_sys_in, l_par=>l_par2_in, l_apri=>apr2,
      out_valid=>ext2_v, out_idx=>ext2_idx, l_ext=>ext2, done=>siso2_done);

  out_valid <= ext2_v;
  out_idx <= ext2_idx;
  l_post <= resize(ext2 + l_sys_in + apr2, llr_t'length);
  done <= ctrl_done;
end architecture;
