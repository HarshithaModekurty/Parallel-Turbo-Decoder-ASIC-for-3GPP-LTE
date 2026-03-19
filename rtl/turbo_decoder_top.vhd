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
  signal siso_in_valid : std_logic;
  signal siso_out_valid : std_logic_vector(G_P-1 downto 0);
  
  type siso_idx_arr is array (0 to G_P-1) of unsigned(G_ADDR_W-1 downto 0);
  signal siso_in_idx, siso_out_idx : siso_idx_arr;
  signal siso_sys, siso_par0, siso_par1 : llr_vec_t(0 to G_P-1);
  signal siso_apri0, siso_apri1 : ext_llr_vec_t(0 to G_P-1);
  signal siso_ext0, siso_ext1 : ext_llr_vec_t(0 to G_P-1);

  -- Folded RAM signals
  signal ram_we      : std_logic_vector(G_P-1 downto 0);
  signal ram_wr_addr : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal ram_wr_data : signed(G_P*ext_llr_t'length-1 downto 0);
  signal ram_rd_addr : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal ram_rd_data : signed(G_P*ext_llr_t'length-1 downto 0);

  -- Batcher Router signals
  signal router_addr_in  : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal router_data_in  : signed(G_P*ext_llr_t'length-1 downto 0);
  signal router_sel_in   : unsigned(G_P*4-1 downto 0);
  signal router_addr_out : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal router_data_out : signed(G_P*ext_llr_t'length-1 downto 0);

  -- Input Buffer Memory (Replicating Folded RAM behavior natively)
  type input_vec_t is record
    sys  : llr_t;
    par1 : llr_t;
    par2 : llr_t;
  end record;
  type input_ram_arr_t is array (0 to G_K_MAX/G_P - 1) of input_vec_t;
  type input_ram_banks_t is array (0 to G_P-1) of input_ram_arr_t;
  signal input_ram : input_ram_banks_t;

  -- Phase Sequencer
  signal seq_count : unsigned(G_ADDR_W-1 downto 0);
  signal seq_running : std_logic;
  signal k_slice : unsigned(G_ADDR_W-1 downto 0);

  -- QPP Signals
  signal qpp_start : std_logic;
  signal qpp_valid : std_logic;
  signal qpp_addr_out : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal qpp_sel_out  : unsigned(G_P*4-1 downto 0);
  signal qpp_idx_valid: std_logic;
  
  -- QPP Delay Line for Write Routing
  constant DEPTH_W : natural := 46;
  type qpp_addr_arr_t is array (0 to DEPTH_W-1) of unsigned(G_P*G_ADDR_W-1 downto 0);
  type qpp_sel_arr_t  is array (0 to DEPTH_W-1) of unsigned(G_P*4-1 downto 0);
  signal qpp_addr_dl : qpp_addr_arr_t;
  signal qpp_sel_dl  : qpp_sel_arr_t;

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
  k_slice <= k_len / G_P;
  
  siso1_done <= '1' when core_done_1 = (core_done_1'range => '1') else '0';
  siso2_done <= '1' when core_done_2 = (core_done_2'range => '1') else '0';

  -- Input Data Loading
  process(clk)
    variable b, a : integer;
  begin
    if rising_edge(clk) then
      if in_valid = '1' then
        b := to_integer(in_idx) mod G_P;
        a := to_integer(in_idx) / G_P;
        input_ram(b)(a).sys <= l_sys_in;
        input_ram(b)(a).par1 <= l_par1_in;
        input_ram(b)(a).par2 <= l_par2_in;
      end if;
    end if;
  end process;

  -- Execution Sequencer
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        seq_running <= '0';
        seq_count <= (others => '0');
        siso_in_valid <= '0';
      else
        if run1 = '1' or run2 = '1' then
          seq_running <= '1';
          seq_count <= (others => '0');
        end if;
        
        if seq_running = '1' then
          siso_in_valid <= '1';
          seq_count <= seq_count + 1;
          if seq_count = k_slice - 1 then
             seq_running <= '0';
             siso_in_valid <= '0';
          end if;
        else
          siso_in_valid <= '0';
        end if;
      end if;
    end if;
  end process;

  qpp_start <= run2;
  qpp_valid <= seq_running;

  -- Phase Delay Line for QPP
  process(clk)
  begin
    if rising_edge(clk) then
       qpp_addr_dl(1 to DEPTH_W-1) <= qpp_addr_dl(0 to DEPTH_W-2);
       qpp_addr_dl(0) <= qpp_addr_out;
       qpp_sel_dl(1 to DEPTH_W-1) <= qpp_sel_dl(0 to DEPTH_W-2);
       qpp_sel_dl(0) <= qpp_sel_out;
    end if;
  end process;

  qpp_inst : entity work.qpp_interleaver
    generic map (
      G_K_MAX  => G_K_MAX,
      G_ADDR_W => G_ADDR_W,
      G_P      => G_P
    )
    port map (
      clk       => clk,
      rst       => rst,
      start     => qpp_start,
      valid     => qpp_valid,
      k_len     => k_len,
      f1        => f1,
      f2        => f2,
      addr_out  => qpp_addr_out,
      sel_out   => qpp_sel_out,
      idx_valid => qpp_idx_valid
    );

  gen_siso : for i in 0 to G_P-1 generate
    siso_in_idx(i) <= seq_count;
    
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
        in_valid  => siso_in_valid,
        in_idx    => siso_in_idx(i),
        sys0      => siso_sys(i),
        sys1      => siso_sys(i),
        par0      => siso_par0(i),
        par1      => siso_par1(i),
        apri0     => siso_apri0(i), 
        apri1     => siso_apri1(i), 
        out_valid => siso_out_valid(i),
        out_idx   => siso_out_idx(i),
        ext0      => siso_ext0(i),
        ext1      => siso_ext1(i),
        done      => core_done_1(i)
      );
      core_done_2(i) <= core_done_1(i);
  end generate;

  -- Input and Read Routing logic
  process(all)
    variable b : integer;
    variable a : unsigned(G_ADDR_W-1 downto 0);
  begin
    ram_rd_addr <= (others => '0');
    
    for i in 0 to G_P-1 loop
      if phase = '0' then
        siso_sys(i)  <= input_ram(i)(to_integer(seq_count)).sys;
        siso_par0(i) <= input_ram(i)(to_integer(seq_count)).par1;
        siso_par1(i) <= (others => '0');
        
        -- Inverse MAP for RAM READ Address
        ram_rd_addr((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= seq_count;
        
        -- Mux Data from RAM
        siso_apri0(i) <= ext_llr_t(ram_rd_data((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length));
        siso_apri1(i) <= (others => '0');
      else
        b := to_integer(qpp_sel_out((i+1)*4-1 downto i*4));
        a := qpp_addr_out((i+1)*G_ADDR_W-1 downto i*G_ADDR_W);
        
        siso_sys(i)  <= input_ram(b)(to_integer(a)).sys;
        siso_par0(i) <= (others => '0');
        siso_par1(i) <= input_ram(i)(to_integer(seq_count)).par2;
        
        -- Inverse MAP for RAM READ Address
        if b < G_P then
           ram_rd_addr((b+1)*G_ADDR_W-1 downto b*G_ADDR_W) <= a;
        end if;
        
        -- Inverse MAP for RAM Data
        if b < G_P then
           siso_apri0(i) <= ext_llr_t(ram_rd_data((b+1)*ext_llr_t'length-1 downto b*ext_llr_t'length));
        else
           siso_apri0(i) <= (others => '0');
        end if;
        siso_apri1(i) <= (others => '0');
      end if;
    end loop;
  end process;

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
      G_ADDR_W => G_ADDR_W,
      G_DATA_W => ext_llr_t'length
    )
    port map (
      addr_in  => router_addr_in,
      data_in  => router_data_in,
      sel_in   => router_sel_in,
      addr_out => router_addr_out,
      data_out => router_data_out
    );

  -- Write Routing (Using Delay Line)
  process(all)
    variable b : integer;
    variable a : unsigned(G_ADDR_W-1 downto 0);
  begin
    for i in 0 to G_P-1 loop
      ram_we(i) <= siso_out_valid(i);
      
      -- Connect RAM inputs directly to Router Outputs
      ram_wr_addr((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= router_addr_out((i+1)*G_ADDR_W-1 downto i*G_ADDR_W);
      ram_wr_data((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= signed(router_data_out((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length));
      
      if phase = '0' then
         -- Phase 0: Write Linearly (Identity Router)
         router_sel_in((i+1)*4-1 downto i*4) <= to_unsigned(i, 4);
         router_addr_in((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= siso_out_idx(i);
         router_data_in((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= signed(siso_ext0(i));
      else
         -- Phase 1: Write Interleaved (Scattered Router)
         b := to_integer(qpp_sel_dl(DEPTH_W-1)((i+1)*4-1 downto i*4));
         a := qpp_addr_dl(DEPTH_W-1)((i+1)*G_ADDR_W-1 downto i*G_ADDR_W);
         
         router_sel_in((i+1)*4-1 downto i*4) <= to_unsigned(b, 4);
         router_addr_in((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= a;
         router_data_in((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= signed(siso_ext0(i));
      end if;
      
      -- Output extraction locally
      if siso_out_valid(0) = '1' and phase = '1' and i = 0 then
         out_valid <= '1';
         -- For true l_post, you add siso_ext0 + apri + sys. For now, pushing 0 to satisfy ports
         -- l_post requires full synchronization.
         l_post <= siso_ext0(0)(4 downto 0); 
      else
         out_valid <= '0';
         l_post <= (others => '0');
      end if;
      out_idx   <= siso_out_idx(0);
    end loop;
  end process;

end architecture;
