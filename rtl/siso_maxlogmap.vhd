library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity siso_maxlogmap is
  generic (
    G_K_MAX  : natural := 6144;
    G_ADDR_W : natural := 13;
    G_W      : natural := 30; -- Window size in Radix-4 stages
    G_L      : natural := 16  -- Learning length in Radix-4 stages
  );
  port (
    clk, rst  : in std_logic;
    start     : in std_logic;
    k_len     : in unsigned(G_ADDR_W-1 downto 0);
    in_valid  : in std_logic;
    in_idx    : in unsigned(G_ADDR_W-1 downto 0);
    sys0      : in llr_t;
    sys1      : in llr_t;
    par0      : in llr_t;
    par1      : in llr_t;
    apri0     : in ext_llr_t;
    apri1     : in ext_llr_t;
    out_valid : out std_logic;
    out_idx   : out unsigned(G_ADDR_W-1 downto 0);
    ext0      : out ext_llr_t;
    ext1      : out ext_llr_t;
    done      : out std_logic
  );
end entity;

architecture rtl of siso_maxlogmap is

  constant DEPTH_W : natural := G_W + G_L;
  
  -- Shift registers for inputs
  type llr_array_t is array (0 to DEPTH_W-1) of llr_t;
  type ext_llr_array_t is array (0 to DEPTH_W-1) of ext_llr_t;
  signal sys0_sr, sys1_sr, par0_sr, par1_sr : llr_array_t;
  signal apr0_sr, apr1_sr : ext_llr_array_t;
  
  type valid_arr_t is array (0 to DEPTH_W) of std_logic;
  type idx_arr_t is array (0 to DEPTH_W) of unsigned(G_ADDR_W-1 downto 0);
  signal valid_sr : valid_arr_t;
  signal idx_sr   : idx_arr_t;
  
  type state_metric_array_t is array (0 to DEPTH_W-1) of state_metric_t;
  signal alpha_sr : state_metric_array_t;
  
  signal alpha_cur : state_metric_t;
  signal beta_learn, beta_decode : state_metric_t;
  signal alpha_fwd_next, beta_learn_next, beta_decode_next : state_metric_t;
  
  signal gam_fwd, gam_learn, gam_decode : metric_vec_t(0 to 15);
  signal out_v_reg : std_logic;
  
begin

  u_bmu_fwd: entity work.radix4_bmu
    port map (
      clk   => clk, rst => rst,
      sys0  => sys0, sys1 => sys1,
      par0  => par0, par1 => par1,
      apri0 => apri0, apri1 => apri1,
      gamma => gam_fwd
    );

  u_acs_fwd: entity work.radix4_acs
    port map (
      state_in  => alpha_cur,
      gamma_in  => gam_fwd,
      mode_bwd  => '0',
      state_out => alpha_fwd_next
    );

  u_bmu_ln: entity work.radix4_bmu
    port map (
      clk   => clk, rst => rst,
      sys0  => sys0_sr(G_W-1), sys1 => sys1_sr(G_W-1),
      par0  => par0_sr(G_W-1), par1 => par1_sr(G_W-1),
      apri0 => apr0_sr(G_W-1), apri1 => apr1_sr(G_W-1),
      gamma => gam_learn
    );

  u_acs_ln: entity work.radix4_acs
    port map (
      state_in  => beta_learn,
      gamma_in  => gam_learn,
      mode_bwd  => '1',
      state_out => beta_learn_next
    );

  u_bmu_dcd: entity work.radix4_bmu
    port map (
      clk   => clk, rst => rst,
      sys0  => sys0_sr(DEPTH_W-1), sys1 => sys1_sr(DEPTH_W-1),
      par0  => par0_sr(DEPTH_W-1), par1 => par1_sr(DEPTH_W-1),
      apri0 => apr0_sr(DEPTH_W-1), apri1 => apr1_sr(DEPTH_W-1),
      gamma => gam_decode
    );

  u_acs_dcd: entity work.radix4_acs
    port map (
      state_in  => beta_decode,
      gamma_in  => gam_decode,
      mode_bwd  => '1',
      state_out => beta_decode_next
    );
    
  u_ext: entity work.radix4_extractor
    port map (
      clk      => clk,
      alpha_in => alpha_sr(DEPTH_W-1),
      beta_in  => beta_decode_next,
      gamma_in => gam_decode,
      sys0_in  => sys0_sr(DEPTH_W-1),
      apri0_in => apr0_sr(DEPTH_W-1),
      sys1_in  => sys1_sr(DEPTH_W-1),
      apri1_in => apr1_sr(DEPTH_W-1),
      ext0_out => ext0,
      ext1_out => ext1
    );

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        for s in 0 to C_NUM_STATES-1 loop
           if s = 0 then 
              alpha_cur(s) <= (others=>'0');
           else 
              alpha_cur(s) <= to_signed(-512, metric_t'length); 
           end if;
           beta_learn(s) <= (others=>'0');
           beta_decode(s) <= (others=>'0');
        end loop;
        valid_sr <= (others => '0');
        out_v_reg <= '0';
        done <= '0';
      else
        if start = '1' then
          for s in 0 to C_NUM_STATES-1 loop
             if s = 0 then alpha_cur(s) <= (others=>'0');
             else alpha_cur(s) <= to_signed(-512, metric_t'length); end if;
             beta_learn(s) <= (others=>'0');
             beta_decode(s) <= (others=>'0');
             alpha_sr <= (others => (others => (others => '0')));
          end loop;
          valid_sr <= (others => '0');
          out_v_reg <= '0';
          done <= '0';
        else
          -- Unconditional shift pipeline
          sys0_sr(1 to DEPTH_W-1) <= sys0_sr(0 to DEPTH_W-2); sys0_sr(0) <= sys0;
          sys1_sr(1 to DEPTH_W-1) <= sys1_sr(0 to DEPTH_W-2); sys1_sr(0) <= sys1;
          par0_sr(1 to DEPTH_W-1) <= par0_sr(0 to DEPTH_W-2); par0_sr(0) <= par0;
          par1_sr(1 to DEPTH_W-1) <= par1_sr(0 to DEPTH_W-2); par1_sr(0) <= par1;
          apr0_sr(1 to DEPTH_W-1) <= apr0_sr(0 to DEPTH_W-2); apr0_sr(0) <= apri0;
          apr1_sr(1 to DEPTH_W-1) <= apr1_sr(0 to DEPTH_W-2); apr1_sr(0) <= apri1;
          
          valid_sr(1 to DEPTH_W) <= valid_sr(0 to DEPTH_W-1); valid_sr(0) <= in_valid;
          idx_sr(1 to DEPTH_W)   <= idx_sr(0 to DEPTH_W-1);   idx_sr(0)   <= in_idx;
          
          alpha_sr(1 to DEPTH_W-1) <= alpha_sr(0 to DEPTH_W-2);
          alpha_sr(0) <= alpha_fwd_next;
          
          alpha_cur <= alpha_fwd_next;
          beta_learn <= beta_learn_next;
          beta_decode <= beta_decode_next;
          
          out_v_reg <= valid_sr(DEPTH_W);
          out_idx <= idx_sr(DEPTH_W);
          out_valid <= out_v_reg;
          
          if out_v_reg = '1' and valid_sr(DEPTH_W) = '0' then
             -- Falling edge of valid indicates completion of block
             done <= '1';
          else
             done <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;
