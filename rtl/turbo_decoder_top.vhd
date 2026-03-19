library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity turbo_decoder_top is
  generic (
    G_K_MAX  : natural := 6144;
    G_ADDR_W : natural := 13;
    G_P      : natural := 8
  );
  port (
    clk, rst   : in std_logic;
    start      : in std_logic;
    n_iter     : in unsigned(3 downto 0);
    k_len      : in unsigned(G_ADDR_W-1 downto 0);
    f1, f2     : in unsigned(G_ADDR_W-1 downto 0);
    in_valid   : in std_logic;
    in_idx     : in unsigned(G_ADDR_W-1 downto 0);
    l_sys_in   : in llr_t;
    l_par1_in  : in llr_t;
    l_par2_in  : in llr_t;
    out_valid  : out std_logic;
    out_idx    : out unsigned(G_ADDR_W-1 downto 0);
    l_post     : out llr_t;
    done       : out std_logic
  );
end entity;

architecture rtl of turbo_decoder_top is

  signal run1, run2, siso1_done, siso2_done, phase, ctrl_done : std_logic;
  signal core_done_1, core_done_2 : std_logic_vector(G_P-1 downto 0);
  signal siso_out_valid : std_logic_vector(G_P-1 downto 0);
  
  type siso_out_idx_arr is array (0 to G_P-1) of unsigned(G_ADDR_W-1 downto 0);
  signal siso_out_idx : siso_out_idx_arr;
  signal siso_ext0, siso_ext1 : ext_llr_vec_t(0 to G_P-1);

  -- Folded RAM signals
  signal ram_we      : std_logic_vector(G_P-1 downto 0);
  signal ram_wr_addr : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal ram_wr_data : signed(G_P*ext_llr_t'length-1 downto 0);
  signal ram_rd_addr : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal ram_rd_data : signed(G_P*ext_llr_t'length-1 downto 0);

  -- Batcher Router signals
  signal router_addr_in  : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal router_data_in  : signed(G_P*llr_t'length-1 downto 0);
  signal router_sel_in   : unsigned(G_P*4-1 downto 0);
  signal router_addr_out : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal router_data_out : signed(G_P*llr_t'length-1 downto 0);

begin

  ctrl : entity work.turbo_iteration_ctrl
    port map (
      clk         => clk,
      rst         => rst,
      start       => start,
      n_iter      => n_iter,
      siso_done_1 => siso1_done,
      siso_done_2 => siso2_done,
      run_siso_1  => run1,
      run_siso_2  => run2,
      deint_phase => phase,
      done        => ctrl_done
    );

  done <= ctrl_done;
  
  -- Simple AND tree to sync done signals
  siso1_done <= '1' when core_done_1 = (core_done_1'range => '1') else '0';
  siso2_done <= '1' when core_done_2 = (core_done_2'range => '1') else '0';

  gen_siso : for i in 0 to G_P-1 generate
    siso_inst : entity work.siso_maxlogmap
      generic map (
        G_K_MAX  => G_K_MAX / G_P,
        G_ADDR_W => G_ADDR_W
      )
      port map (
        clk       => clk,
        rst       => rst,
        start     => run1 or run2,
        k_len     => k_len,
        in_valid  => in_valid,
        in_idx    => in_idx,
        sys0      => l_sys_in,
        sys1      => l_sys_in,
        par0      => l_par1_in,
        par1      => l_par1_in,
        apri0     => (others => '0'), -- Connect dynamically based on RAM later
        apri1     => (others => '0'), -- Connect dynamically based on RAM later
        out_valid => siso_out_valid(i),
        out_idx   => siso_out_idx(i),
        ext0      => siso_ext0(i),
        ext1      => siso_ext1(i),
        done      => core_done_1(i)
      );
      core_done_2(i) <= core_done_1(i);
  end generate;

  ram_inst : entity work.folded_llr_ram
    generic map (
      G_BANKS  => G_P,
      G_ADDR_W => G_ADDR_W
    )
    port map (
      clk     => clk,
      we      => ram_we,
      wr_addr => ram_wr_addr,
      wr_data => ram_wr_data,
      rd_addr => ram_rd_addr,
      rd_data => ram_rd_data
    );

  router_inst : entity work.batcher_router
    generic map (
      G_P      => G_P,
      G_ADDR_W => G_ADDR_W
    )
    port map (
      addr_in  => router_addr_in,
      data_in  => router_data_in,
      sel_in   => router_sel_in,
      addr_out => router_addr_out,
      data_out => router_data_out
    );

  -- Basic wiring for compilation (bypassing complex QPP math)
  process(all)
  begin
    for i in 0 to G_P-1 loop
      ram_we(i) <= siso_out_valid(i);
      
      -- Pack addresses
      ram_wr_addr((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= siso_out_idx(i);
      ram_rd_addr((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= siso_out_idx(i);
      
      -- Pack data (Ext LLRs)
      ram_wr_data((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= signed(siso_ext0(i));
      
      -- Dummy wiring for router inputs
      router_addr_in((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= siso_out_idx(i);
      router_data_in((i+1)*llr_t'length-1 downto i*llr_t'length) <= signed(l_sys_in);
      
      -- Dummy wiring for out outputs
      out_valid <= siso_out_valid(0);
      out_idx   <= siso_out_idx(0);
      l_post    <= llr_t(router_data_out(llr_t'length-1 downto 0));
    end loop;
    
    router_sel_in <= (others => '0');
  end process;

end architecture;
