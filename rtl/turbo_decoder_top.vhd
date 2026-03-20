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
    out_idx    : out unsigned(G_P*G_ADDR_W-1 downto 0);
    l_post     : out signed(G_P*7-1 downto 0);
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

  signal ram_we      : std_logic_vector(G_P-1 downto 0);
  signal ram_wr_addr : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal ram_wr_data : signed(G_P*ext_llr_t'length-1 downto 0);
  signal ram_rd_addr : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal ram_rd_data : signed(G_P*ext_llr_t'length-1 downto 0);

  signal router_addr_in  : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal router_data_in  : signed(G_P*ext_llr_t'length-1 downto 0);
  signal router_sel_in   : unsigned(G_P*4-1 downto 0);
  signal router_addr_out : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal router_data_out : signed(G_P*ext_llr_t'length-1 downto 0);

  constant IN_W : natural := llr_t'length * 3;
  type ram_addr_arr_t is array (0 to G_P-1) of unsigned(G_ADDR_W-1 downto 0);
  type ram_data_arr_t is array (0 to G_P-1) of std_logic_vector(IN_W-1 downto 0);

  signal ram_in_wr_en    : std_logic_vector(G_P-1 downto 0);
  signal ram_in_wr_addr  : unsigned(G_ADDR_W-1 downto 0);
  signal ram_in_wr_data  : std_logic_vector(IN_W-1 downto 0);
  signal ram_in_rdA_addr : ram_addr_arr_t;
  signal ram_in_rdB_addr : ram_addr_arr_t;
  signal ram_in_rdA_data : ram_data_arr_t;
  signal ram_in_rdB_data : ram_data_arr_t;

  signal siso_in_valid_d : std_logic;

  signal seq_count : unsigned(G_ADDR_W-1 downto 0);
  signal seq_count_d : unsigned(G_ADDR_W-1 downto 0);
  signal seq_running : std_logic;
  signal k_slice : unsigned(G_ADDR_W-1 downto 0);

  signal qpp_start : std_logic;
  signal qpp_valid : std_logic;
  signal qpp_addr_out : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal qpp_sel_out  : unsigned(G_P*4-1 downto 0);
  signal qpp_sel_d    : unsigned(G_P*4-1 downto 0);
  signal qpp_idx_valid: std_logic;
  
  constant DEPTH_W : natural := 46;
  type qpp_addr_arr_t is array (0 to DEPTH_W-1) of unsigned(G_P*G_ADDR_W-1 downto 0);
  type qpp_sel_arr_t  is array (0 to DEPTH_W-1) of unsigned(G_P*4-1 downto 0);
  signal qpp_addr_dl : qpp_addr_arr_t := (others => (others => '0'));
  signal qpp_sel_dl  : qpp_sel_arr_t := (others => (others => '0'));

  signal iter_count : unsigned(3 downto 0);

begin

  ctrl : entity work.turbo_iteration_ctrl
    port map (
      clk         => clk, rst => rst,
      start       => start, n_iter => n_iter,
      siso_done_1 => siso1_done, siso_done_2 => siso2_done,
      run_siso_1  => run1, run_siso_2  => run2,
      deint_phase => phase, done => ctrl_done
    );

  done <= ctrl_done;
  k_slice <= k_len / G_P;
  siso1_done <= '1' when core_done_1 = (core_done_1'range => '1') else '0';
  siso2_done <= '1' when core_done_2 = (core_done_2'range => '1') else '0';

  process(clk)
    variable b, a : integer;
  begin
    if rising_edge(clk) then
      ram_in_wr_en <= (others => '0');
      if in_valid = '1' then
        b := to_integer(in_idx) mod G_P;
        a := to_integer(in_idx) / G_P;
        ram_in_wr_addr <= to_unsigned(a, G_ADDR_W);
        ram_in_wr_data <= std_logic_vector(l_sys_in) & std_logic_vector(l_par1_in) & std_logic_vector(l_par2_in);
        if b < G_P then
           ram_in_wr_en(b) <= '1';
        end if;
      end if;
      
      if rst='1' or start='1' then
           iter_count <= (others=>'0');
        elsif siso2_done = '1' then
           iter_count <= iter_count + 1;
        end if;
      end if;
    end process;

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
          if seq_count = k_slice - 1 then
             seq_running <= '0';
             siso_in_valid <= '0';
             seq_count <= (others => '0');
          else
             seq_count <= seq_count + 1;
          end if;
        else
          siso_in_valid <= '0';
        end if;
      end if;
    end if;
  end process;

  qpp_start <= run2; qpp_valid <= seq_running;

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
    generic map ( G_K_MAX => G_K_MAX, G_ADDR_W => G_ADDR_W, G_P => G_P )
    port map (
      clk => clk, rst => rst, start => qpp_start, valid => qpp_valid,
      k_len => k_len, f1 => f1, f2 => f2, addr_out => qpp_addr_out,
      sel_out => qpp_sel_out, idx_valid => qpp_idx_valid
    );

  gen_siso : for i in 0 to G_P-1 generate
    siso_in_idx(i) <= seq_count_d;
    siso_inst : entity work.siso_maxlogmap
      generic map ( G_K_MAX => G_K_MAX/G_P, G_ADDR_W => G_ADDR_W )
      port map (
        clk => clk, rst => rst, start => run1 or run2, k_len => k_len,
        in_valid => siso_in_valid_d, in_idx => siso_in_idx(i),
        sys0 => siso_sys(i), sys1 => siso_sys(i), par0 => siso_par0(i), par1 => siso_par1(i),
        apri0 => siso_apri0(i), apri1 => siso_apri1(i),
        out_valid => siso_out_valid(i), out_idx => siso_out_idx(i),
        ext0 => siso_ext0(i), ext1 => siso_ext1(i), done => core_done_1(i)
      );
      core_done_2(i) <= core_done_1(i);
  end generate;

  process(all)
    variable b : integer;
    variable a : unsigned(G_ADDR_W-1 downto 0);
  begin
    ram_rd_addr <= (others => '0');
    for i in 0 to G_P-1 loop
      if phase = '0' then
        ram_rd_addr((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= seq_count;
      else
        b := to_integer(qpp_sel_out((i+1)*4-1 downto i*4));
        a := qpp_addr_out((i+1)*G_ADDR_W-1 downto i*G_ADDR_W);
        if b < G_P then ram_rd_addr((b+1)*G_ADDR_W-1 downto b*G_ADDR_W) <= a; end if;
      end if;
    end loop;
  end process;

  gen_in_ram: for i in 0 to G_P-1 generate
    type mem_t is array (0 to G_K_MAX/G_P - 1) of std_logic_vector(IN_W-1 downto 0);
    signal bank_mem : mem_t := (others => (others => '0'));
    attribute ram_style : string;
    attribute ram_style of bank_mem : signal is "block";
  begin
    process(clk)
    begin
      if rising_edge(clk) then
        if ram_in_wr_en(i) = '1' then
          bank_mem(to_integer(ram_in_wr_addr)) <= ram_in_wr_data;
        end if;
        ram_in_rdA_data(i) <= bank_mem(to_integer(ram_in_rdA_addr(i)));
        ram_in_rdB_data(i) <= bank_mem(to_integer(ram_in_rdB_addr(i)));
      end if;
    end process;
  end generate;

  process(clk)
  begin
    if rising_edge(clk) then
      -- Pass phase delay so it matches RAM output
      qpp_sel_d <= qpp_sel_out;
    end if;
  end process;

  process(all)
    variable b : integer;
    variable a : unsigned(G_ADDR_W-1 downto 0);
    variable seq_limit : unsigned(G_ADDR_W-1 downto 0);
  begin
    -- Address routing to Input RAM Blocks
    seq_limit := seq_count;
    if to_integer(seq_limit) >= G_K_MAX/G_P then
       seq_limit := to_unsigned(G_K_MAX/G_P - 1, G_ADDR_W);
    end if;
    
    for i in 0 to G_P-1 loop
       ram_in_rdA_addr(i) <= (others => '0');
       ram_in_rdB_addr(i) <= seq_limit;
    end loop;
    
    for i in 0 to G_P-1 loop
      if phase = '0' then
        ram_in_rdA_addr(i) <= seq_limit;
      else
        b := to_integer(qpp_sel_out((i+1)*4-1 downto i*4));
        a := qpp_addr_out((i+1)*G_ADDR_W-1 downto i*G_ADDR_W);
        if b < G_P then
           if to_integer(a) >= G_K_MAX/G_P then a := to_unsigned(0, G_ADDR_W); end if;
           ram_in_rdA_addr(b) <= a;
        end if;
      end if;
    end loop;
  end process;

  process(clk)
    variable b : integer;
    variable vec_a, vec_b : std_logic_vector(IN_W-1 downto 0);
  begin
    if rising_edge(clk) then
      siso_in_valid_d <= siso_in_valid;
      seq_count_d     <= seq_count;

      for i in 0 to G_P-1 loop
        if phase = '0' then
          vec_a := ram_in_rdA_data(i);
          siso_sys(i)  <= signed(vec_a(3*llr_t'length-1 downto 2*llr_t'length));
          siso_par0(i) <= signed(vec_a(2*llr_t'length-1 downto 1*llr_t'length));
          siso_par1(i) <= (others => '0');
        else
          b := to_integer(qpp_sel_d((i+1)*4-1 downto i*4));
          if b >= G_P then b := 0; end if;
          
          vec_a := ram_in_rdA_data(b);
          vec_b := ram_in_rdB_data(i);
          siso_sys(i)  <= signed(vec_a(3*llr_t'length-1 downto 2*llr_t'length));
          siso_par0(i) <= (others => '0');
          siso_par1(i) <= signed(vec_b(1*llr_t'length-1 downto 0));
        end if;
      end loop;
    end if;
  end process;

  -- The folded RAM output is ALREADY 1-cycle delayed because it's a synchronousBRAM read.
  -- input_ram is also 1-cycle delayed (assigned in the process above).
  -- Therefore, they are naturally aligned outside the clock process.
  process(all)
    variable b : integer;
  begin
    for i in 0 to G_P-1 loop
      if phase = '0' then
        siso_apri0(i) <= ext_llr_t(ram_rd_data((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length));
        siso_apri1(i) <= (others => '0');
      else
        b := to_integer(qpp_sel_out((i+1)*4-1 downto i*4));
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
    generic map ( G_BANKS => G_P, G_ADDR_W => G_ADDR_W )
    port map (
      clk => clk, we => ram_we, wr_addr => ram_wr_addr, wr_data => ram_wr_data,
      rd_addr => ram_rd_addr, rd_data => ram_rd_data
    );

  router_inst : entity work.batcher_router
    generic map ( G_P => G_P, G_ADDR_W => G_ADDR_W, G_DATA_W => ext_llr_t'length )
    port map (
      addr_in => router_addr_in, data_in => router_data_in, sel_in => router_sel_in,
      addr_out => router_addr_out, data_out => router_data_out
    );

  process(all)
    variable b : integer;
    variable a : unsigned(G_ADDR_W-1 downto 0);
    variable t_post : signed(6 downto 0);
    variable t_sys, t_apri, t_ext : signed(6 downto 0);
  begin
    for i in 0 to G_P-1 loop
      ram_we(i) <= siso_out_valid(i);
      ram_wr_addr((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= router_addr_out((i+1)*G_ADDR_W-1 downto i*G_ADDR_W);
      ram_wr_data((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= signed(router_data_out((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length));
      
      if phase = '0' then
         router_sel_in((i+1)*4-1 downto i*4) <= to_unsigned(i, 4);
         router_addr_in((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= siso_out_idx(i);
         router_data_in((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= signed(siso_ext0(i));
      else
         b := to_integer(qpp_sel_dl(DEPTH_W-1)((i+1)*4-1 downto i*4));
         if b >= G_P then b := 0; end if;
         a := qpp_addr_dl(DEPTH_W-1)((i+1)*G_ADDR_W-1 downto i*G_ADDR_W);
         router_sel_in((i+1)*4-1 downto i*4) <= to_unsigned(b, 4);
         router_addr_in((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= a;
         router_data_in((i+1)*ext_llr_t'length-1 downto i*ext_llr_t'length) <= signed(siso_ext0(i));
      end if;
      
      -- Output calculation on the fly at final iteration
      t_sys := resize(siso_sys(i), 7);
      t_apri := resize(siso_apri0(i), 7);
      t_ext := resize(siso_ext0(i), 7);
      t_post := t_sys + t_apri + t_ext;
      
      l_post((i+1)*7-1 downto i*7) <= t_post;
      out_idx((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= siso_out_idx(i);
    end loop;
    
    if phase = '1' and iter_count = n_iter-1 then
       out_valid <= siso_out_valid(0);
    else
       out_valid <= '0';
    end if;
  end process;

end architecture;
